import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';

class StorageService {
  StorageService({Directory? documentsDirectory, Directory? tempDirectory})
      : _documentsDirectory = documentsDirectory,
        _tempDirectory = tempDirectory;

  /// Override path_provider's directories (used by tests).
  final Directory? _documentsDirectory;
  final Directory? _tempDirectory;

  Future<Directory> get _tempDir async =>
      _tempDirectory ?? await getTemporaryDirectory();

  static const _fileName = 'conversations.json';

  Future<Directory> get _docsDir async =>
      _documentsDirectory ?? await getApplicationDocumentsDirectory();

  Future<File> get _file async {
    final dir = await _docsDir;
    return File('${dir.path}/$_fileName');
  }

  Future<List<Conversation>> loadConversations() async {
    final file = await _file;
    final fromMain = await _tryReadConversations(file);
    if (fromMain != null) {
      // Some records couldn't be read and are about to be dropped from the
      // list (and, on the next save, from disk) — keep the original.
      if (!fromMain.complete) await _preserveUnreadable(file);
      return fromMain.conversations;
    }
    // Main file missing or undecodable (e.g. the app was killed mid-write) —
    // fall back to the previous version instead of losing all history.
    if (await file.exists()) await _preserveUnreadable(file);
    final fromBackup = await _tryReadConversations(File('${file.path}.bak'));
    return fromBackup?.conversations ?? [];
  }

  /// Reads one conversations file. Null when it is missing or can't be
  /// decoded at all; otherwise the readable records, with [complete] false
  /// if any record had to be skipped — one bad record must not cost the
  /// whole history.
  Future<({List<Conversation> conversations, bool complete})?>
      _tryReadConversations(File file) async {
    try {
      if (!await file.exists()) return null;
      final json = await file.readAsString();
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      final conversations = <Conversation>[];
      var complete = true;
      for (final record in decoded) {
        try {
          conversations
              .add(Conversation.fromJson(record as Map<String, dynamic>));
        } catch (_) {
          complete = false;
        }
      }
      return (conversations: conversations, complete: complete);
    } catch (_) {
      return null;
    }
  }

  /// Keeps a byte-for-byte copy of a file that couldn't be fully read. The
  /// next two saves would otherwise rotate it into `.bak` and then overwrite
  /// that, destroying the only copy.
  Future<void> _preserveUnreadable(File file) async {
    try {
      await file.copy('${file.path}.corrupt');
    } catch (_) {
      // Best effort — failing to keep a copy must not block loading.
    }
  }

  // Chains writes so overlapping calls (the persist timer fires every
  // second during streaming) can't interleave on the same file.
  Future<void> _conversationWrites = Future.value();

  /// Each conversation's encoded UTF-8 JSON as of the last partial save, by
  /// id. Lets the saves made while a reply streams skip re-encoding every
  /// other conversation — and every base64 image in them. Only partial saves
  /// keep it: a full save drops it, so an idle app doesn't hold a second copy
  /// of the whole history in memory.
  final Map<String, List<int>> _encodedConversations = {};

  /// How many conversations have been JSON-encoded so far. Tests read the
  /// difference around a save to see what it actually re-encoded.
  @visibleForTesting
  int encodedConversationCount = 0;

  /// Writes [conversations] to disk. Every conversation is re-encoded unless
  /// [changed] is given: then only those ids (plus any with no cached
  /// encoding) are, and the rest reuse their previous bytes. Pass [changed]
  /// only when nothing but those conversations was modified since the last
  /// save — anything else must go through a full save.
  Future<void> saveConversations(List<Conversation> conversations,
      {Set<String>? changed}) {
    // Snapshot the state now; the write itself may be queued.
    final chunks = _encodeSnapshot(conversations, changed);
    final write = _conversationWrites.then((_) => _writeConversations(chunks));
    // Keep the chain alive even if a write fails.
    _conversationWrites = write.catchError((_) {});
    return write;
  }

  /// One encoded chunk per conversation, in list order. The cache describes
  /// in-memory state rather than the file, so a failed write can't leave it
  /// stale; rebuilding it from the list drops deleted conversations, so they
  /// can never be written back from it.
  List<List<int>> _encodeSnapshot(
      List<Conversation> conversations, Set<String>? changed) {
    final encoder = JsonUtf8Encoder();
    final next = <String, List<int>>{};
    final chunks = <List<int>>[];
    for (final c in conversations) {
      var bytes = (changed == null || changed.contains(c.id))
          ? null
          : _encodedConversations[c.id];
      if (bytes == null) {
        bytes = encoder.convert(c.toJson());
        encodedConversationCount++;
      }
      next[c.id] = bytes;
      chunks.add(bytes);
    }
    // The next exchange's first partial save re-encodes everything once.
    _encodedConversations.clear();
    if (changed != null) _encodedConversations.addAll(next);
    return chunks;
  }

  static const _arrayStart = [0x5B]; // [
  static const _arraySeparator = [0x2C]; // ,
  static const _arrayEnd = [0x5D]; // ]

  Future<void> _writeConversations(List<List<int>> chunks) async {
    final file = await _file;
    // Write to a temp file, rotate the current file to .bak, then rename
    // the temp file into place. rename() is atomic on the same filesystem,
    // so a process kill can never leave a truncated main file — at worst
    // the .bak still holds the previous good version.
    final tmp = File('${file.path}.tmp');
    // Streamed chunk by chunk: the result is the same bytes jsonEncode of the
    // whole list would give, without ever holding it as one string.
    final sink = tmp.openWrite();
    try {
      sink.add(_arrayStart);
      for (var i = 0; i < chunks.length; i++) {
        if (i > 0) sink.add(_arraySeparator);
        sink.add(chunks[i]);
      }
      sink.add(_arrayEnd);
      await sink.flush();
    } finally {
      await sink.close();
    }
    // IOSink.flush() only hands the bytes to the OS; fsync like
    // writeAsString(flush: true) did, so the renamed file is durable.
    final raf = await tmp.open(mode: FileMode.append);
    try {
      await raf.flush();
    } finally {
      await raf.close();
    }
    if (await file.exists()) {
      await _renameOver(file, '${file.path}.bak');
    }
    await _renameOver(tmp, file.path);
  }

  Future<void> _renameOver(File from, String to) async {
    try {
      await from.rename(to);
    } on FileSystemException {
      // Windows can refuse to rename over an existing file.
      final target = File(to);
      if (await target.exists()) await target.delete();
      await from.rename(to);
    }
  }

  Future<void> deleteAll() {
    // Nothing is left to reuse, and the cache holds every conversation's bytes.
    _encodedConversations.clear();
    // Queued behind any save in flight: deleting underneath a write made its
    // temp file vanish before the rename, or let the history reappear.
    final delete = _conversationWrites.then((_) => _deleteConversationFiles());
    _conversationWrites = delete.catchError((_) {});
    return delete;
  }

  Future<void> _deleteConversationFiles() async {
    final file = await _file;
    // Remove the backup, the preserved-unreadable copy and any stray temp
    // file too, so deleted history can't resurrect through the corruption
    // fallback.
    for (final f in [
      file,
      File('${file.path}.bak'),
      File('${file.path}.tmp'),
      File('${file.path}.corrupt'),
    ]) {
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  /// Ids can come from an imported file, so they must not be able to add
  /// path separators or `..` to an export file name.
  static String _safeFileStem(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<File> exportConversation(Conversation conversation) async {
    final dir = await _tempDir;
    final file =
        File('${dir.path}/conversation_${_safeFileStem(conversation.id)}.json');
    await file.writeAsString(jsonEncode(conversation.toJson()));
    return file;
  }

  String conversationToMarkdown(Conversation conversation) {
    final created =
        conversation.createdAt.toLocal().toString().split('.').first;
    final buffer = StringBuffer()
      ..writeln('# ${conversation.title}')
      ..writeln()
      ..writeln('Model: `${conversation.model}` — $created')
      ..writeln();

    for (final msg in conversation.messages) {
      // Internal roles don't belong in a shared transcript.
      if (msg.role == 'tool' || msg.role == 'system') continue;
      // Assistant turns that only carried tool calls have no text to show.
      if (msg.role == 'assistant' && msg.content.trim().isEmpty) continue;
      buffer
        ..writeln('---')
        ..writeln()
        ..writeln(msg.role == 'user' ? '**You:**' : '**Assistant:**')
        ..writeln();
      if (msg.files != null && msg.files!.isNotEmpty) {
        for (final f in msg.files!) {
          buffer.writeln('_Attached: ${f['name']}_');
        }
        buffer.writeln();
      }
      if (msg.images != null && msg.images!.isNotEmpty) {
        buffer
          ..writeln('_Attached ${msg.images!.length} image(s)_')
          ..writeln();
      }
      buffer.writeln(msg.content);
      // An answer cut off inside a code fence would otherwise render the rest
      // of the transcript as code.
      final fences =
          msg.content.split('\n').where((l) => l.startsWith('```')).length;
      if (fences.isOdd) buffer.writeln('```');
      buffer.writeln();
    }
    return buffer.toString();
  }

  Future<File> exportConversationMarkdown(Conversation conversation) async {
    final dir = await _tempDir;
    final file =
        File('${dir.path}/conversation_${_safeFileStem(conversation.id)}.md');
    await file.writeAsString(conversationToMarkdown(conversation));
    return file;
  }

  Future<File> exportAllConversations(List<Conversation> conversations) async {
    final dir = await _tempDir;
    final file = File('${dir.path}/llm_disco_export.json');
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'conversations': conversations.map((c) => c.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(data));
    return file;
  }

  Future<List<Conversation>> importConversations(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final decoded = jsonDecode(content);

    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('conversations')) {
        // Wrapped format: { "version": 1, "conversations": [...] }
        final list = decoded['conversations'] as List<dynamic>;
        return list
            .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (decoded.containsKey('id')) {
        // Single conversation
        return [Conversation.fromJson(decoded)];
      }
    } else if (decoded is List<dynamic>) {
      // Raw list of conversations
      return decoded
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw const FormatException('Unrecognized export format');
  }

  // Saved connection profiles

  static const _savedConnectionsFile = 'saved_connections.json';

  Future<File> get _savedConnections async {
    final dir = await _docsDir;
    return File('${dir.path}/$_savedConnectionsFile');
  }

  Future<List<Map<String, dynamic>>> loadSavedConnections() async {
    try {
      final file = await _savedConnections;
      if (!await file.exists()) return [];
      final json = await file.readAsString();
      final List<dynamic> list = jsonDecode(json);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSavedConnections(List<Map<String, dynamic>> connections) async {
    final file = await _savedConnections;
    await _writeAtomically(file, jsonEncode(connections));
  }

  // Chains config writes: two overlapping saves of the same file would
  // otherwise share one temp file.
  Future<void> _configWrites = Future.value();

  /// Temp file + rename, like the conversations file: a process kill mid-write
  /// can't leave a truncated file and silently lose profiles or the token.
  Future<void> _writeAtomically(File file, String contents) {
    final write = _configWrites.then((_) async {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(contents, flush: true);
      await _renameOver(tmp, file.path);
    });
    // Keep the chain alive even if a write fails.
    _configWrites = write.catchError((_) {});
    return write;
  }

  // Connection settings persistence

  static const _settingsFile = 'connection_settings.json';

  Future<File> get _settings async {
    final dir = await _docsDir;
    return File('${dir.path}/$_settingsFile');
  }

  Future<Map<String, dynamic>?> loadConnectionSettings() async {
    try {
      final file = await _settings;
      if (!await file.exists()) return null;
      final json = await file.readAsString();
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveConnectionSettings({
    required String ip,
    required String port,
    required bool useHttp,
    String? searxngUrl,
    String? authToken,
  }) async {
    final file = await _settings;
    final data = <String, dynamic>{
      'ip': ip,
      'port': port,
      'useHttp': useHttp,
    };
    if (searxngUrl != null && searxngUrl.isNotEmpty) {
      data['searxngUrl'] = searxngUrl;
    }
    if (authToken != null && authToken.isNotEmpty) {
      data['authToken'] = authToken;
    }
    await _writeAtomically(file, jsonEncode(data));
  }
}
