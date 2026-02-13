import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';

class StorageService {
  static const _fileName = 'conversations.json';

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<Conversation>> loadConversations() async {
    try {
      final file = await _file;
      if (!await file.exists()) return [];
      final json = await file.readAsString();
      final List<dynamic> list = jsonDecode(json);
      return list.map((e) => Conversation.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversations(List<Conversation> conversations) async {
    final file = await _file;
    final json = jsonEncode(conversations.map((c) => c.toJson()).toList());
    await file.writeAsString(json);
  }

  Future<void> deleteAll() async {
    final file = await _file;
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> exportConversation(Conversation conversation) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/conversation_${conversation.id}.json');
    await file.writeAsString(jsonEncode(conversation.toJson()));
    return file;
  }

  Future<File> exportAllConversations(List<Conversation> conversations) async {
    final dir = await getTemporaryDirectory();
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
    final dir = await getApplicationDocumentsDirectory();
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
    final dir = await getApplicationDocumentsDirectory();
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
    await file.writeAsString(jsonEncode(data));
  }
}
