import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/models/conversation.dart';
import 'package:llm_disco_test1/services/storage_service.dart';

void main() {
  group('StorageService conversations', () {
    late Directory dir;
    late StorageService storage;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('llm_disco_storage_test');
      storage = StorageService(documentsDirectory: dir, tempDirectory: dir);
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Conversation conv(String id) => Conversation(id: id, model: 'llama3');

    test('save and load round-trip', () async {
      await storage.saveConversations([conv('a'), conv('b')]);

      final loaded = await storage.loadConversations();

      expect(loaded.map((c) => c.id), ['a', 'b']);
    });

    test('keeps the previous version as a backup', () async {
      await storage.saveConversations([conv('old')]);
      await storage.saveConversations([conv('new')]);

      final bak = File('${dir.path}/conversations.json.bak');
      expect(await bak.exists(), isTrue);
      final decoded = jsonDecode(await bak.readAsString()) as List<dynamic>;
      expect((decoded.first as Map)['id'], 'old');
    });

    test('falls back to the backup when the main file is corrupt', () async {
      await storage.saveConversations([conv('good')]);
      await storage.saveConversations([conv('latest')]);
      // simulate a write truncated by a process kill
      await File('${dir.path}/conversations.json')
          .writeAsString('[{"id": "tru');

      final loaded = await storage.loadConversations();

      // history must survive — the previous good version is used
      expect(loaded.map((c) => c.id), ['good']);
    });

    test('deleteAll removes the backup too', () async {
      await storage.saveConversations([conv('old')]);
      await storage.saveConversations([conv('new')]);

      await storage.deleteAll();

      // deleted history must not resurrect from the backup
      expect(await storage.loadConversations(), isEmpty);
    });

    test('conversationToMarkdown renders title, roles and content', () {
      final c = Conversation(
        id: '1',
        model: 'llama3',
        title: 'Test Chat',
        messages: [
          ChatMessage(role: 'user', content: 'Hello'),
          ChatMessage(role: 'assistant', content: 'Hi *there*'),
          ChatMessage(role: 'tool', content: 'raw tool output'),
        ],
      );

      final md = storage.conversationToMarkdown(c);

      expect(md, contains('# Test Chat'));
      expect(md, contains('llama3'));
      expect(md, contains('Hello'));
      expect(md, contains('Hi *there*'));
      // internal tool messages don't belong in a shared transcript
      expect(md, isNot(contains('raw tool output')));
    });

    test('exportConversationMarkdown writes an .md file', () async {
      final c = Conversation(
        id: 'md-1',
        model: 'llama3',
        title: 'Exported',
        messages: [ChatMessage(role: 'user', content: 'Hello')],
      );

      final file = await storage.exportConversationMarkdown(c);

      expect(file.path, endsWith('.md'));
      expect(await file.readAsString(), contains('# Exported'));
    });

    test('connection settings round-trip including the auth token', () async {
      await storage.saveConnectionSettings(
        ip: '10.0.0.5',
        port: '11434',
        useHttp: true,
        searxngUrl: 'http://10.0.0.5:8080',
        authToken: 'secret-token',
      );

      final loaded = await storage.loadConnectionSettings();

      expect(loaded!['ip'], '10.0.0.5');
      expect(loaded['authToken'], 'secret-token');
    });

    test('rapid unawaited saves end with the last state on disk', () async {
      // mirrors the 1-second persist timer firing during streaming
      final futures = [
        for (var i = 0; i < 10; i++) storage.saveConversations([conv('c$i')]),
      ];
      await Future.wait(futures);

      final loaded = await storage.loadConversations();

      expect(loaded.single.id, 'c9');
    });
  });
}
