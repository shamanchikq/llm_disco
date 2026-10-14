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

    group('unreadable records', () {
      File corruptCopy() => File('${dir.path}/conversations.json.corrupt');

      test('one bad record does not empty the whole history', () async {
        final good = jsonEncode(conv('good').toJson());
        final text = '[$good, {"id": "broken", "model": 1}]';
        await File('${dir.path}/conversations.json').writeAsString(text);

        final loaded = await storage.loadConversations();

        expect(loaded.map((c) => c.id), ['good']);
        // the skipped record's data is kept for recovery
        expect(await corruptCopy().readAsString(), text);
      });

      test('a fully readable file leaves no .corrupt copy', () async {
        await storage.saveConversations([conv('a')]);

        await storage.loadConversations();

        expect(await corruptCopy().exists(), isFalse);
      });

      test('an undecodable file with no backup loads empty but stays recoverable',
          () async {
        const text = '[{"id": "tru';
        await File('${dir.path}/conversations.json').writeAsString(text);

        expect(await storage.loadConversations(), isEmpty);
        // The app now starts empty and saves; the first save rotates the
        // unreadable file into .bak and the second overwrites that.
        await storage.saveConversations([conv('fresh1')]);
        await storage.saveConversations([conv('fresh2')]);

        expect(await corruptCopy().readAsString(), text);
      });

      test('an undecodable file still falls back to the backup', () async {
        await storage.saveConversations([conv('good')]);
        await storage.saveConversations([conv('latest')]);
        const text = '[{"id": "tru';
        await File('${dir.path}/conversations.json').writeAsString(text);

        final loaded = await storage.loadConversations();

        expect(loaded.map((c) => c.id), ['good']);
        expect(await corruptCopy().readAsString(), text);
      });

      test('a later problem overwrites the single .corrupt file', () async {
        await File('${dir.path}/conversations.json').writeAsString('[1');
        await storage.loadConversations();
        await File('${dir.path}/conversations.json').writeAsString('[2');
        await storage.loadConversations();

        expect(await corruptCopy().readAsString(), '[2');
      });

      test('deleteAll removes the .corrupt copy too', () async {
        await File('${dir.path}/conversations.json').writeAsString('[1');
        await storage.loadConversations();
        expect(await corruptCopy().exists(), isTrue);

        await storage.deleteAll();

        expect(await corruptCopy().exists(), isFalse);
      });
    });

    test('deleteAll waits for in-flight saves instead of racing them',
        () async {
      // A save already queued keeps writing while the files are deleted:
      // its .tmp used to vanish before the rename (PathNotFoundException),
      // or the deleted history reappeared.
      final saves = [
        for (var i = 0; i < 5; i++) storage.saveConversations([conv('c$i')]),
      ];

      await storage.deleteAll();
      await Future.wait(saves); // none of them may have thrown

      final leftovers = dir
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('conversations.json'));
      expect(leftovers, isEmpty);
      expect(await storage.loadConversations(), isEmpty);
    });

    test('saved connections and settings are written atomically', () async {
      // leftover temp file from an interrupted earlier write
      await File('${dir.path}/connection_settings.json.tmp')
          .writeAsString('{"ip": "tru');

      await storage.saveConnectionSettings(
          ip: '10.0.0.5', port: '11434', useHttp: true, authToken: 'tok');
      await storage.saveConnectionSettings(
          ip: '10.0.0.6', port: '11434', useHttp: false, authToken: 'tok2');
      await storage.saveSavedConnections([
        {'name': 'home', 'ip': '10.0.0.5'},
      ]);
      await storage.saveSavedConnections([
        {'name': 'home', 'ip': '10.0.0.5'},
        {'name': 'work', 'ip': '10.0.0.9'},
      ]);

      final settings = await storage.loadConnectionSettings();
      expect(settings!['ip'], '10.0.0.6');
      expect(settings['authToken'], 'tok2');
      expect((await storage.loadSavedConnections()).map((c) => c['name']),
          ['home', 'work']);
      // temp files are renamed into place, never left behind
      expect(dir.listSync().map((e) => e.path),
          isNot(contains(endsWith('.tmp'))));
    });

    test('overlapping settings writes cannot interleave', () async {
      await Future.wait([
        for (var i = 0; i < 10; i++)
          storage.saveConnectionSettings(
              ip: '10.0.0.$i', port: '11434', useHttp: true),
      ]);

      final settings = await storage.loadConnectionSettings();
      expect(settings!['ip'], '10.0.0.9');
    });

    group('export file names', () {
      Conversation withId(String id) => Conversation(
            id: id,
            model: 'llama3',
            messages: [ChatMessage(role: 'user', content: 'hi')],
          );

      test('ids from imported files cannot escape the temp directory',
          () async {
        final nested = Directory('${dir.path}/export')..createSync();
        final scoped =
            StorageService(documentsDirectory: dir, tempDirectory: nested);

        final json = await scoped.exportConversation(withId('../../evil/x'));
        final md = await scoped
            .exportConversationMarkdown(withId('a/b\\c:d*e?f"g<h>i|j'));

        for (final f in [json, md]) {
          expect(f.parent.path, nested.path);
          expect(await f.exists(), isTrue);
        }
        expect(json.uri.pathSegments.last,
            matches(RegExp(r'^conversation_[A-Za-z0-9_-]+\.json$')));
        expect(md.uri.pathSegments.last,
            matches(RegExp(r'^conversation_[A-Za-z0-9_-]+\.md$')));
        expect(File('${dir.path}/evil').existsSync(), isFalse);
      });

      test('ordinary ids are left as they were', () async {
        final f = await storage.exportConversation(withId('1699-3_ab-C'));

        expect(f.uri.pathSegments.last, 'conversation_1699-3_ab-C.json');
      });
    });

    group('markdown transcript', () {
      test('assistant messages that only carried tool calls are skipped', () {
        final c = Conversation(
          id: '1',
          model: 'llama3',
          messages: [
            ChatMessage(role: 'user', content: 'Search for dart'),
            ChatMessage(role: 'assistant', content: '', toolCalls: [
              {
                'function': {'name': 'web_search', 'arguments': {}},
              },
            ]),
            ChatMessage(role: 'tool', content: 'raw'),
            ChatMessage(role: 'assistant', content: 'Dart is a language.'),
          ],
        );

        final md = storage.conversationToMarkdown(c);

        expect('**Assistant:**'.allMatches(md), hasLength(1));
        expect(md, contains('Dart is a language.'));
      });

      test('an answer cut off inside a code fence is closed', () {
        final c = Conversation(
          id: '1',
          model: 'llama3',
          messages: [
            ChatMessage(role: 'user', content: 'code please'),
            ChatMessage(
                role: 'assistant', content: 'Here:\n```dart\nvoid main() {'),
            ChatMessage(role: 'user', content: 'thanks'),
          ],
        );

        final md = storage.conversationToMarkdown(c);

        // the fence is closed right after the broken message, so the next
        // message is not rendered as code
        expect(md, contains('void main() {\n```\n'));
        expect(md.indexOf('```\n', md.indexOf('void main')),
            lessThan(md.indexOf('thanks')));
      });

      test('balanced fences are left alone', () {
        final c = Conversation(
          id: '1',
          model: 'llama3',
          messages: [
            ChatMessage(
                role: 'assistant', content: '```dart\nvoid main() {}\n```'),
          ],
        );

        final md = storage.conversationToMarkdown(c);

        expect('```'.allMatches(md), hasLength(2));
      });
    });

    group('partial saves', () {
      File mainFile() => File('${dir.path}/conversations.json');

      Conversation titled(String id, String title) =>
          Conversation(id: id, model: 'llama3', title: title);

      /// What the file held before partial saves existed.
      List<int> jsonEncodeBytes(List<Conversation> conversations) =>
          utf8.encode(jsonEncode(conversations.map((c) => c.toJson()).toList()));

      /// How many conversations [save] had to encode.
      Future<int> encodedBy(Future<void> Function() save) async {
        final before = storage.encodedConversationCount;
        await save();
        return storage.encodedConversationCount - before;
      }

      test('a full save encodes every conversation', () async {
        final all = [conv('a'), conv('b'), conv('c')];

        expect(await encodedBy(() => storage.saveConversations(all)), 3);
      });

      test('a partial save encodes only the changed conversation', () async {
        final a = titled('a', 'A');
        final b = titled('b', 'B');
        final c = titled('c', 'C');
        // Partial saves keep the cache; an empty set encodes whatever is new.
        await storage.saveConversations([a, b, c], changed: <String>{});

        b.title = 'B, edited';
        final encoded = await encodedBy(
            () => storage.saveConversations([a, b, c], changed: {'b'}));

        expect(encoded, 1);
        final loaded = await storage.loadConversations();
        expect(loaded.map((x) => x.title), ['A', 'B, edited', 'C']);
      });

      test('the file after a partial save equals a full save of the same data',
          () async {
        final a = Conversation(id: 'a', model: 'llama3', messages: [
          ChatMessage(role: 'user', content: 'hi', images: ['aW1hZ2U=']),
        ]);
        final b = titled('b', 'B');
        final c = titled('c', 'C');
        await storage.saveConversations([a, b, c]);

        b.messages.add(ChatMessage(role: 'assistant', content: 'streamed'));
        await storage.saveConversations([a, b, c], changed: {'b'});
        final afterPartial = await mainFile().readAsBytes();

        // a fresh service has no cache, so it encodes everything
        final other = await Directory.systemTemp.createTemp('llm_disco_full');
        addTearDown(() => other.delete(recursive: true));
        await StorageService(documentsDirectory: other)
            .saveConversations([a, b, c]);
        final afterFull =
            await File('${other.path}/conversations.json').readAsBytes();

        expect(afterPartial, afterFull);
        expect(afterPartial, jsonEncodeBytes([a, b, c]));
      });

      test('the bytes match jsonEncode for awkward content', () async {
        final tricky = Conversation(
          id: 'tricky',
          model: 'llama3',
          title: 'caf\u00e9 \u{1F600} \u4e2d\u6587 "quoted" \\ \u0001',
          messages: [
            ChatMessage(
              role: 'user',
              content: 'line\nbreak\ttab lone \uD800 surrogate',
              images: ['aW1hZ2U='],
              files: [
                {'name': 'n.txt', 'data': 'ZGF0YQ==', 'type': 'text/plain'},
              ],
            ),
            ChatMessage(
                role: 'assistant',
                content: '',
                toolCalls: [
                  {
                    'function': {
                      'name': 'web_search',
                      'arguments': {'query': 'dart', 'n': 1.5},
                    },
                  },
                ],
                cutOff: true),
          ],
          temperature: 0.7,
          seed: 42,
        );
        final all = [tricky, conv('plain')];

        await storage.saveConversations(all);

        expect(await mainFile().readAsBytes(), jsonEncodeBytes(all));
      });

      test('an empty list is written as an empty array', () async {
        await storage.saveConversations([conv('a')]);
        await storage.saveConversations([], changed: <String>{});

        expect(await mainFile().readAsString(), '[]');
      });

      test('unchanged conversations are reused from the cache', () async {
        final a = titled('a', 'A');
        final b = titled('b', 'B');
        await storage.saveConversations([a, b], changed: <String>{});

        // Edited in memory but not named in `changed`: the caller promised
        // nothing else moved, so the cached encoding is what gets written.
        b.title = 'B, edited';
        await storage.saveConversations([a, b], changed: {'a'});

        final loaded = await storage.loadConversations();
        expect(loaded.map((x) => x.title), ['A', 'B']);
      });

      test('a conversation missing from the cache is encoded anyway',
          () async {
        // Nothing has been saved by this service yet (e.g. right after a
        // launch), so no id is cached — even a "partial" save has to write
        // everything.
        final all = [titled('a', 'A'), titled('b', 'B'), titled('c', 'C')];

        final encoded = await encodedBy(
            () => storage.saveConversations(all, changed: {'a'}));

        expect(encoded, 3);
        final loaded = await storage.loadConversations();
        expect(loaded.map((x) => x.title), ['A', 'B', 'C']);
      });

      test('a conversation added since the last save is encoded', () async {
        final a = titled('a', 'A');
        await storage.saveConversations([a], changed: <String>{});

        final b = titled('b', 'B');
        final encoded = await encodedBy(
            () => storage.saveConversations([b, a], changed: {'a'}));

        expect(encoded, 2); // a (changed) and b (not cached)
        expect((await storage.loadConversations()).map((x) => x.id),
            ['b', 'a']);
      });

      test('a dropped conversation is never written back from the cache',
          () async {
        final a = titled('a', 'A');
        final b = titled('b', 'old B');
        await storage.saveConversations([a, b], changed: <String>{});

        // b is deleted; the file loses it
        await storage.saveConversations([a], changed: {'a'});
        expect((await storage.loadConversations()).map((x) => x.id), ['a']);

        // A different conversation now reuses the id (an import, an undo of
        // a re-created chat). Its stale encoding must be gone.
        final newB = titled('b', 'new B');
        await storage.saveConversations([a, newB], changed: {'a'});

        final loaded = await storage.loadConversations();
        expect(loaded.map((x) => x.title), ['A', 'new B']);
      });

      test('deleteAll forgets the cached encodings', () async {
        final a = titled('a', 'A');
        await storage.saveConversations([a], changed: <String>{});
        await storage.deleteAll();

        final encoded = await encodedBy(
            () => storage.saveConversations([a], changed: <String>{}));

        expect(encoded, 1);
        expect((await storage.loadConversations()).single.id, 'a');
      });

      test('a full save drops the cache, so idle memory holds no second copy',
          () async {
        final a = titled('a', 'A');
        final b = titled('b', 'B');
        await storage.saveConversations([a, b], changed: <String>{});

        b.title = 'B, renamed'; // user-driven change, saved in full
        await storage.saveConversations([a, b]);
        a.title = 'A, streaming';
        final encoded = await encodedBy(
            () => storage.saveConversations([a, b], changed: {'a'}));

        // nothing cached after the full save: both are encoded afresh
        expect(encoded, 2);
        final loaded = await storage.loadConversations();
        expect(loaded.map((x) => x.title), ['A, streaming', 'B, renamed']);
      });

      test('the snapshot is taken when save is called, not when it runs',
          () async {
        final a = titled('a', 'A');
        final b = titled('b', 'B');
        await storage.saveConversations([a, b]);

        a.title = 'A, saved';
        final write = storage.saveConversations([a, b], changed: {'a'});
        a.title = 'A, too late'; // edited while the write is queued
        await write;

        final loaded = await storage.loadConversations();
        expect(loaded.first.title, 'A, saved');
      });

      test('still rotates the previous version into .bak', () async {
        final a = titled('a', 'first');
        await storage.saveConversations([a]);
        a.title = 'second';
        await storage.saveConversations([a], changed: {'a'});

        final bak = jsonDecode(
                await File('${dir.path}/conversations.json.bak').readAsString())
            as List<dynamic>;
        expect((bak.single as Map)['title'], 'first');
        expect(File('${dir.path}/conversations.json.tmp').existsSync(),
            isFalse);
      });

      test('a failed write leaves the queue and the cache usable', () async {
        final missing = Directory('${dir.path}/not-yet');
        final s = StorageService(documentsDirectory: missing);
        final a = titled('a', 'A');
        final b = titled('b', 'B');

        await expectLater(s.saveConversations([a, b], changed: <String>{}),
            throwsA(isA<FileSystemException>()));

        missing.createSync();
        a.title = 'A, edited';
        final before = s.encodedConversationCount;
        await s.saveConversations([a, b], changed: {'a'});

        // only `a` was re-encoded: b's encoding survived the failed write
        expect(s.encodedConversationCount - before, 1);
        final written = jsonDecode(
                await File('${missing.path}/conversations.json').readAsString())
            as List<dynamic>;
        expect(written.map((e) => (e as Map)['title']), ['A, edited', 'B']);
      });
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
