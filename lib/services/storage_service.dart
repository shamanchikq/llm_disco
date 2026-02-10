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
