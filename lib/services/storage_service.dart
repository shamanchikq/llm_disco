import 'dart:convert';
import 'dart:io';

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
    if (fromMain != null) return fromMain;
    // Main file missing or corrupt (e.g. the app was killed mid-write) —
    // fall back to the previous version instead of losing all history.
    final fromBackup = await _tryReadConversations(File('${file.path}.bak'));
    return fromBackup ?? [];
  }

  Future<List<Conversation>?> _tryReadConversations(File file) async {
    try {
      if (!await file.exists()) return null;
      final json = await file.readAsString();
      final List<dynamic> list = jsonDecode(json);
      return list.map((e) => Conversation.fromJson(e)).toList();
    } catch (_) {
      return null;
    }
  }

  // Chains writes so overlapping calls (the persist timer fires every
  // second during streaming) can't interleave on the same file.
  Future<void> _conversationWrites = Future.value();

  Future<void> saveConversations(List<Conversation> conversations) {
    // Snapshot the state now; the write itself may be queued.
    final json = jsonEncode(conversations.map((c) => c.toJson()).toList());
    final write = _conversationWrites.then((_) => _writeConversations(json));
    // Keep the chain alive even if a write fails.
    _conversationWrites = write.catchError((_) {});
    return write;
  }

  Future<void> _writeConversations(String json) async {
    final file = await _file;
    // Write to a temp file, rotate the current file to .bak, then rename
    // the temp file into place. rename() is atomic on the same filesystem,
    // so a process kill can never leave a truncated main file — at worst
    // the .bak still holds the previous good version.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
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

  Future<void> deleteAll() async {
    final file = await _file;
    // Remove the backup and any stray temp file too, so deleted history
    // can't resurrect through the corruption fallback.
    for (final f in [file, File('${file.path}.bak'), File('${file.path}.tmp')]) {
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  Future<File> exportConversation(Conversation conversation) async {
    final dir = await _tempDir;
    final file = File('${dir.path}/conversation_${conversation.id}.json');
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
      buffer
        ..writeln(msg.content)
        ..writeln();
    }
    return buffer.toString();
  }

  Future<File> exportConversationMarkdown(Conversation conversation) async {
    final dir = await _tempDir;
    final file = File('${dir.path}/conversation_${conversation.id}.md');
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
    await file.writeAsString(jsonEncode(connections));
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
    await file.writeAsString(jsonEncode(data));
  }
}
