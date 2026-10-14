import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/providers/chat_provider.dart';
import 'package:llm_disco_test1/models/conversation.dart';
import 'package:llm_disco_test1/models/model_capabilities.dart';
import 'package:llm_disco_test1/services/ollama_service.dart';
import '../helpers/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(<ChatMessage>[]);
    registerFallbackValue(<Conversation>[]);
  });

  group('ChatProvider', () {
    late ChatProvider provider;

    setUp(() {
      provider = ChatProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('initial state', () {
      expect(provider.conversations, isEmpty);
      expect(provider.activeConversation, isNull);
      expect(provider.isStreaming, isFalse);
    });

    test('createConversation', () {
      final conv = provider.createConversation('llama3');

      expect(provider.conversations.length, 1);
      expect(provider.activeConversation, conv);
      expect(conv.model, 'llama3');
      expect(conv.title, 'New Chat');

      // second one should go to the front of the list
      final second = provider.createConversation('phi3');
      expect(provider.conversations.first, second);
    });

    test('conversation ids are unique even within the same millisecond', () {
      // A timestamp alone collides here, which would break delete-by-id
      // and produce duplicate Dismissible keys in the sidebar.
      final ids = [
        for (var i = 0; i < 50; i++) provider.createConversation('llama3').id,
      ];

      expect(ids.toSet(), hasLength(ids.length));
    });

    test('delete conversation', () {
      // set up two conversations so we can test different scenarios
      final p = ChatProvider(initialConversations: [
        Conversation(id: 'a', model: 'llama3'),
        Conversation(id: 'b', model: 'phi3'),
      ]);
      addTearDown(p.dispose);

      // deleting the active one should clear activeConversation
      p.setActiveConversation(p.conversations.first);
      p.deleteConversation('a');
      expect(p.activeConversation, isNull);
      expect(p.conversations.length, 1);

      // deleting the last one
      p.deleteConversation('b');
      expect(p.conversations, isEmpty);
    });

    test('rename conversation', () {
      final conv = provider.createConversation('llama3');

      provider.renameConversation(conv.id, 'My Chat');
      expect(provider.conversations.first.title, 'My Chat');

      // whitespace-only should be ignored
      provider.renameConversation(conv.id, '   ');
      expect(provider.conversations.first.title, 'My Chat');

      // should trim whitespace
      provider.renameConversation(conv.id, '  Trimmed  ');
      expect(provider.conversations.first.title, 'Trimmed');
    });

    test('importConversations skips duplicates', () {
      final existing = provider.createConversation('llama3');
      final imported = [
        Conversation(id: existing.id, model: 'llama3', title: 'Duplicate'),
        Conversation(id: 'new-id', model: 'phi3', title: 'New Conv'),
      ];

      final added = provider.importConversations(imported);

      expect(added, 1);
      expect(provider.conversations.length, 2);
    });

    test('setService and disconnectService', () {
      provider.createConversation('llama3');
      provider.createConversation('phi3');

      final mock = MockOllamaService();
      provider.setService(mock);

      // disconnect should clear active but keep conversations
      provider.disconnectService();
      expect(provider.activeConversation, isNull);
      expect(provider.isStreaming, isFalse);
      expect(provider.conversations.length, 2);
    });

    test('searxng and image helpers', () {
      // searxng url should be trimmed, empty becomes null
      provider.setSearxngUrl('  http://example.com  ');
      expect(provider.searxngUrl, 'http://example.com');

      provider.setSearxngUrl('   ');
      expect(provider.searxngUrl, isNull);

      // pending images
      provider.addPendingImage('base64data');
      expect(provider.pendingImages, ['base64data']);

      provider.clearPendingImages();
      expect(provider.pendingImages, isEmpty);
    });

    group('composer state is per conversation', () {
      test('attachments staged in one chat stay with that chat', () {
        final a = provider.createConversation('llama3');
        provider.addPendingImage('photo-for-a');
        provider.setPendingFile('notes.txt', 'ZGF0YQ==', 'text/plain');

        final b = provider.createConversation('llama3');
        expect(provider.pendingImages, isEmpty);
        expect(provider.pendingFileName, isNull);

        provider.setActiveConversation(a);
        expect(provider.pendingImages, ['photo-for-a']);
        expect(provider.pendingFileName, 'notes.txt');

        provider.setActiveConversation(b);
        provider.clearPendingFile();
        provider.setActiveConversation(a);
        expect(provider.pendingFileName, 'notes.txt');
      });

      test("a send only takes the active chat's attachments", () async {
        final mock = MockOllamaService();
        provider.setService(mock);
        when(() => mock.streamChat(any(), any(),
                think: any(named: 'think'),
                tools: any(named: 'tools'),
                numCtx: any(named: 'numCtx')))
            .thenAnswer((_) => Stream.fromIterable(
                [const ChatStreamEvent(contentToken: 'ok', done: true)]));
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenAnswer((_) async => '');

        final a = provider.createConversation('llama3');
        provider.addPendingImage('photo-for-a');
        final b = provider.createConversation('llama3');

        await provider.sendMessage('hello from b');

        expect(b.messages.first.images, isNull);
        provider.setActiveConversation(a);
        expect(provider.pendingImages, ['photo-for-a']);
      });

      test('composer text is remembered per conversation id', () {
        expect(provider.composerTextFor('a'), '');
        provider.setComposerText('a', 'half a thought');
        provider.setComposerText('b', 'something else');

        expect(provider.composerTextFor('a'), 'half a thought');
        expect(provider.composerTextFor('b'), 'something else');

        provider.setComposerText('a', '');
        expect(provider.composerTextFor('a'), '');
      });

      test('clear forgets every draft', () {
        provider.createConversation('llama3');
        provider.addPendingImage('photo');
        provider.setComposerText('x', 'draft');

        provider.clear();

        expect(provider.pendingImages, isEmpty);
        expect(provider.composerTextFor('x'), '');
      });
    });

    test('clear wipes everything', () {
      provider.createConversation('llama3');
      provider.createConversation('phi3');
      provider.setService(MockOllamaService());

      provider.clear();

      expect(provider.conversations, isEmpty);
      expect(provider.activeConversation, isNull);
      expect(provider.isStreaming, isFalse);
    });

    test('setActiveConversation', () {
      final conv1 = provider.createConversation('llama3');
      provider.createConversation('phi3');

      provider.setActiveConversation(conv1);
      expect(provider.activeConversation, conv1);
    });

    test('follow-up after a tool call includes the tool_calls message',
        () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      provider.setSearxngUrl('http://searx.local');
      final conv = provider.createConversation('qwen3');
      conv.webSearchEnabled = true;

      final toolCalls = [
        {
          'function': {
            'name': 'web_search',
            'arguments': {'query': 'dart'},
          },
        },
      ];

      var call = 0;
      final captured = <List<ChatMessage>>[];
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((inv) {
        captured.add(
            List.of(inv.positionalArguments[1] as List<ChatMessage>));
        call++;
        if (call == 1) {
          // model answers with a pure tool call: no content at all
          return Stream.fromIterable(
              [ChatStreamEvent(toolCalls: toolCalls, done: true)]);
        }
        return Stream.fromIterable(
            [const ChatStreamEvent(contentToken: 'answer', done: true)]);
      });
      when(() => mock.searchSearXNG(any(), any())).thenAnswer((_) async => [
            {'title': 't', 'url': 'u', 'content': 'c'},
          ]);

      await provider.sendMessage('question');

      expect(captured.length, 2);
      // The second request must carry the assistant message that requested
      // the tool — otherwise the tool result has no matching call and
      // strict tool templates (qwen3, llama3.1+) degrade.
      final assistantWithTools = captured[1]
          .where((m) => m.role == 'assistant' && m.toolCalls != null);
      expect(assistantWithTools, isNotEmpty);
    });

    test('sampling parameters and system prompt reach the request', () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      final conv = provider.createConversation('llama3');
      conv.systemPrompt = 'Be terse.';
      conv.temperature = 0.7;
      conv.topK = 40;
      conv.topP = 0.9;
      conv.repeatPenalty = 1.1;
      conv.seed = 42;

      late Invocation call;
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
            temperature: any(named: 'temperature'),
            topK: any(named: 'topK'),
            topP: any(named: 'topP'),
            repeatPenalty: any(named: 'repeatPenalty'),
            seed: any(named: 'seed'),
          )).thenAnswer((inv) {
        call = inv;
        return Stream.fromIterable(
            [const ChatStreamEvent(contentToken: 'ok', done: true)]);
      });

      await provider.sendMessage('hi');

      expect(call.namedArguments[#temperature], 0.7);
      expect(call.namedArguments[#topK], 40);
      expect(call.namedArguments[#topP], 0.9);
      expect(call.namedArguments[#repeatPenalty], 1.1);
      expect(call.namedArguments[#seed], 42);

      final sent = call.positionalArguments[1] as List<ChatMessage>;
      expect(sent.first.role, 'system');
      expect(sent.first.content, 'Be terse.');
      // the system message is injected per-request, not stored in history
      expect(conv.messages.where((m) => m.role == 'system'), isEmpty);
    });

    test('context usage is tracked from the final stream event', () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      final conv = provider.createConversation('llama3');

      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => Stream.fromIterable([
            const ChatStreamEvent(contentToken: 'hi'),
            const ChatStreamEvent(
              done: true,
              evalCount: 20,
              evalDuration: 1000000000,
              promptEvalCount: 100,
            ),
          ]));

      await provider.sendMessage('hello');

      // prompt tokens + generated tokens = context consumed so far
      expect(conv.lastContextTokens, 120);
    });

    group('model-generated titles', () {
      late MockOllamaService mock;

      setUp(() {
        mock = MockOllamaService();
        provider.setService(mock);
        when(() => mock.streamChat(
              any(),
              any(),
              think: any(named: 'think'),
              tools: any(named: 'tools'),
              numCtx: any(named: 'numCtx'),
            )).thenAnswer((_) => Stream.fromIterable([
              const ChatStreamEvent(
                  contentToken: 'Paris is the capital.', done: true),
            ]));
      });

      test('replaces the truncated title after the first exchange', () async {
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenAnswer((_) async => ' "Trip to Paris" \n');
        final conv = provider.createConversation('llama3');

        await provider.sendMessage('Tell me about Paris');
        await pumpEventQueue();

        // quotes and whitespace stripped from the model's reply
        expect(conv.title, 'Trip to Paris');
      });

      test('only generates once and never overwrites a manual rename',
          () async {
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenAnswer((_) async => 'Generated Title');
        final conv = provider.createConversation('llama3');

        await provider.sendMessage('Tell me about Paris');
        await pumpEventQueue();
        provider.renameConversation(conv.id, 'My Title');
        await provider.sendMessage('And Rome?');
        await pumpEventQueue();

        expect(conv.title, 'My Title');
        verify(() => mock.generateText(any(), any(),
            think: any(named: 'think'))).called(1);
      });

      test('a failing title request leaves the fallback title', () async {
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenThrow(Exception('offline'));
        final conv = provider.createConversation('llama3');

        await provider.sendMessage('Tell me about Paris');
        await pumpEventQueue();

        expect(conv.title, 'Tell me about Paris');
      });
    });

    test('editAndResend truncates from the edited message and resends',
        () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      final conv = provider.createConversation('llama3');

      var reply = 'first answer';
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => Stream.fromIterable(
          [ChatStreamEvent(contentToken: reply, done: true)]));

      await provider.sendMessage('first question');
      reply = 'second answer';

      await provider.editAndResend(conv.messages.first, 'edited question');

      expect(conv.messages.length, 2);
      expect(conv.messages[0].role, 'user');
      expect(conv.messages[0].content, 'edited question');
      expect(conv.messages[1].content, 'second answer');
    });

    test('changeConversationModel updates the model in place', () {
      final conv = provider.createConversation('llama3');
      conv.messages.add(ChatMessage(role: 'user', content: 'hi'));

      provider.changeConversationModel(conv.id, 'phi3');

      expect(conv.model, 'phi3');
      expect(conv.messages, hasLength(1)); // history kept
    });

    group('streaming is scoped to its own conversation', () {
      late MockOllamaService mock;
      late StreamController<ChatStreamEvent> controller;

      setUp(() {
        mock = MockOllamaService();
        controller = StreamController<ChatStreamEvent>();
        provider.setService(mock);
        when(() => mock.streamChat(
              any(),
              any(),
              think: any(named: 'think'),
              tools: any(named: 'tools'),
              numCtx: any(named: 'numCtx'),
            )).thenAnswer((_) => controller.stream);
      });

      test('a failure after switching chats leaves the other chat intact',
          () async {
        final a = provider.createConversation('llama3');
        final b = provider.createConversation('phi3');
        b.messages.addAll([
          ChatMessage(role: 'user', content: 'earlier q'),
          ChatMessage(role: 'assistant', content: 'earlier answer'),
        ]);
        provider.setActiveConversation(a);

        final send = provider.sendMessage('hi');
        await Future<void>.delayed(Duration.zero);
        provider.setActiveConversation(b); // user browses away mid-stream
        controller.addError(Exception('server died'));
        await controller.close();
        await send;

        // B's finished answer must not be clobbered or removed
        expect(b.messages.map((m) => m.content),
            ['earlier q', 'earlier answer']);
        expect(b.messages.last.isError, isFalse);
        // the error belongs to the conversation that was generating
        expect(a.messages.last.isError, isTrue);
      });

      test('isStreaming follows the active conversation', () async {
        final a = provider.createConversation('llama3');
        final b = provider.createConversation('phi3');
        provider.setActiveConversation(a);

        final send = provider.sendMessage('hi');
        await Future<void>.delayed(Duration.zero);
        expect(provider.isStreaming, isTrue);

        provider.setActiveConversation(b);
        expect(provider.isStreaming, isFalse); // B itself is idle
        expect(provider.isAnyStreaming, isTrue); // but A is generating

        provider.setActiveConversation(a);
        expect(provider.isStreaming, isTrue);

        controller.add(const ChatStreamEvent(contentToken: 'ok', done: true));
        await controller.close();
        await send;
        expect(provider.isAnyStreaming, isFalse);
      });

      test('tokens/sec belongs to the conversation that generated it',
          () async {
        final a = provider.createConversation('llama3');
        final b = provider.createConversation('phi3');
        provider.setActiveConversation(a);

        final send = provider.sendMessage('hi');
        await Future<void>.delayed(Duration.zero);
        controller.add(const ChatStreamEvent(
            done: true, evalCount: 20, evalDuration: 1000000000));
        await controller.close();
        await send;

        expect(provider.lastTokensPerSec, closeTo(20, 0.01));
        provider.setActiveConversation(b);
        expect(provider.lastTokensPerSec, isNull);
      });

      test('a second send is refused while another chat is generating',
          () async {
        final a = provider.createConversation('llama3');
        final b = provider.createConversation('phi3');
        provider.setActiveConversation(a);

        final send = provider.sendMessage('first');
        await Future<void>.delayed(Duration.zero);

        provider.setActiveConversation(b);
        await provider.sendMessage('second'); // must not start a 2nd stream

        expect(b.messages, isEmpty);
        verify(() => mock.streamChat(
              any(),
              any(),
              think: any(named: 'think'),
              tools: any(named: 'tools'),
              numCtx: any(named: 'numCtx'),
            )).called(1);

        controller.add(const ChatStreamEvent(contentToken: 'ok', done: true));
        await controller.close();
        await send;
      });

      test('deleting the streaming conversation cancels its stream', () async {
        final a = provider.createConversation('llama3');
        provider.setActiveConversation(a);
        when(() => mock.cancelStream()).thenAnswer((_) {});

        final send = provider.sendMessage('hi');
        await Future<void>.delayed(Duration.zero);
        provider.deleteConversationForUndo(a.id);

        verify(() => mock.cancelStream()).called(1);

        controller.addError(Exception('closed'));
        await controller.close();
        await send;
        expect(provider.isAnyStreaming, isFalse);
      });
    });

    test('deleteAllConversations clears the list and storage', () async {
      final storage = MockStorageService();
      when(() => storage.deleteAll()).thenAnswer((_) async {});
      when(() => storage.saveConversations(any())).thenAnswer((_) async {});
      final p = ChatProvider(
        storageService: storage,
        initialConversations: [Conversation(id: 'a', model: 'llama3')],
      );
      addTearDown(p.dispose);

      await p.deleteAllConversations();

      expect(p.conversations, isEmpty);
      expect(p.activeConversation, isNull);
      // must remove the .bak too, or history resurrects on next load
      verify(() => storage.deleteAll()).called(1);
    });

    group('stream interruption', () {
      late MockOllamaService mock;
      late StreamController<ChatStreamEvent> controller;

      setUp(() {
        mock = MockOllamaService();
        controller = StreamController<ChatStreamEvent>();
        provider.setService(mock);
        when(() => mock.streamChat(
              any(),
              any(),
              think: any(named: 'think'),
              tools: any(named: 'tools'),
              numCtx: any(named: 'numCtx'),
            )).thenAnswer((_) => controller.stream);
      });

      // Simulates the http client being closed by cancelStream: the
      // in-flight stream errors out.
      Future<void> failStream() async {
        controller.addError(Exception('Connection closed'));
        await controller.close();
      }

      test('stop before any output removes the empty bubble', () async {
        final conv = provider.createConversation('llama3');

        final send = provider.sendMessage('hi');
        await Future<void>.delayed(Duration.zero);
        provider.stopStreaming();
        await failStream();
        await send;

        // just the user message — no error bubble for a user-initiated stop
        expect(conv.messages.length, 1);
        expect(conv.messages.single.role, 'user');
        expect(provider.isStreaming, isFalse);
      });

      test('stop during thinking keeps the bubble without an error',
          () async {
        final conv = provider.createConversation('deepseek-r1');

        final send = provider.sendMessage('hi');
        await Future<void>.delayed(Duration.zero);
        controller.add(const ChatStreamEvent(thinkingToken: 'hmm'));
        await Future<void>.delayed(Duration.zero);
        provider.stopStreaming();
        await failStream();
        await send;

        final last = conv.messages.last;
        expect(last.role, 'assistant');
        expect(last.thinking, 'hmm');
        expect(last.content.startsWith('[Error:'), isFalse);
      });

      test('stop mid-response marks it interrupted, not error', () async {
        final conv = provider.createConversation('llama3');

        final send = provider.sendMessage('hi');
        await Future<void>.delayed(Duration.zero);
        controller.add(const ChatStreamEvent(contentToken: 'Hello'));
        await Future<void>.delayed(Duration.zero);
        provider.stopStreaming();
        await failStream();
        await send;

        expect(conv.messages.last.content,
            'Hello\n\n*[Response interrupted]*');
      });

      test('a genuine failure still shows an error bubble', () async {
        final conv = provider.createConversation('llama3');

        final send = provider.sendMessage('hi');
        await Future<void>.delayed(Duration.zero);
        await failStream(); // no stopStreaming — this is a real error
        await send;

        expect(conv.messages.last.role, 'assistant');
        expect(conv.messages.last.isError, isTrue);
        expect(conv.messages.last.content, contains('Connection closed'));
      });
    });

    group('truncated replies', () {
      late MockOllamaService mock;
      late Conversation conv;

      setUp(() {
        mock = MockOllamaService();
        provider.setService(mock);
        conv = provider.createConversation('llama3');
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenAnswer((_) async => '');
      });

      void stubStream(Stream<ChatStreamEvent> Function() answer) {
        when(() => mock.streamChat(
              any(),
              any(),
              think: any(named: 'think'),
              tools: any(named: 'tools'),
              numCtx: any(named: 'numCtx'),
            )).thenAnswer((_) => answer());
      }

      group('done_reason', () {
        test('length flags the reply as cut off', () async {
          stubStream(() => Stream.fromIterable([
                const ChatStreamEvent(contentToken: 'Half an answer'),
                const ChatStreamEvent(done: true, doneReason: 'length'),
              ]));

          await provider.sendMessage('hi');

          final reply = conv.messages.last;
          expect(reply.cutOff, isTrue);
          // the text itself is untouched and it isn't an error
          expect(reply.content, 'Half an answer');
          expect(reply.isError, isFalse);
        });

        test('stop leaves the reply unflagged', () async {
          stubStream(() => Stream.fromIterable([
                const ChatStreamEvent(contentToken: 'All of it'),
                const ChatStreamEvent(done: true, doneReason: 'stop'),
              ]));

          await provider.sendMessage('hi');

          expect(conv.messages.last.cutOff, isFalse);
        });

        test('a done line without a reason leaves the reply unflagged',
            () async {
          stubStream(() => Stream.fromIterable([
                const ChatStreamEvent(contentToken: 'All of it', done: true),
              ]));

          await provider.sendMessage('hi');

          expect(conv.messages.last.cutOff, isFalse);
        });

        test('length with only thinking and no answer is still flagged',
            () async {
          // A thinking model that spends its whole budget reasoning: the flag
          // is what explains the missing answer.
          stubStream(() => Stream.fromIterable([
                const ChatStreamEvent(thinkingToken: 'Let me think'),
                const ChatStreamEvent(thinkingToken: ' some more'),
                const ChatStreamEvent(done: true, doneReason: 'length'),
              ]));

          await provider.sendMessage('hi');

          final reply = conv.messages.last;
          expect(reply.cutOff, isTrue);
          expect(reply.content, isEmpty);
          expect(reply.thinking, 'Let me think some more');
          expect(reply.isError, isFalse);
        });

        test('the flag is set on the leg that was cut off, not the others',
            () async {
          provider.setSearxngUrl('http://searx.local');
          conv.webSearchEnabled = true;
          when(() => mock.searchSearXNG(any(), any())).thenAnswer((_) async => [
                {'title': 't', 'url': 'u', 'content': 'c'},
              ]);
          var leg = 0;
          stubStream(() {
            leg++;
            if (leg == 1) {
              return Stream.fromIterable([
                ChatStreamEvent(
                    toolCalls: [searchCall('dart')],
                    done: true,
                    doneReason: 'stop'),
              ]);
            }
            return Stream.fromIterable([
              const ChatStreamEvent(contentToken: 'Cut sh'),
              const ChatStreamEvent(done: true, doneReason: 'length'),
            ]);
          });

          await provider.sendMessage('question');

          final assistants =
              conv.messages.where((m) => m.role == 'assistant').toList();
          expect(assistants, hasLength(2));
          expect(assistants.first.cutOff, isFalse);
          expect(assistants.last.cutOff, isTrue);
        });

        test('a retry that completes clears the flag with the old reply',
            () async {
          var reason = 'length';
          stubStream(() => Stream.fromIterable([
                const ChatStreamEvent(contentToken: 'text'),
                ChatStreamEvent(done: true, doneReason: reason),
              ]));
          await provider.sendMessage('hi');
          expect(conv.messages.last.cutOff, isTrue);

          reason = 'stop';
          await provider.retryLastMessage();

          expect(conv.messages.where((m) => m.role == 'assistant'),
              hasLength(1));
          expect(conv.messages.last.cutOff, isFalse);
        });
      });

      group('a stream that closes before it finished', () {
        // What OllamaService throws when the response ends without a
        // `done: true` line.
        Exception closedEarly() =>
            Exception('Connection closed before the reply finished');

        test('keeps the partial text, labelled as interrupted', () async {
          stubStream(() async* {
            yield const ChatStreamEvent(contentToken: 'Half an ');
            yield const ChatStreamEvent(contentToken: 'answer');
            throw closedEarly();
          });

          await provider.sendMessage('hi');

          final reply = conv.messages.last;
          expect(reply.role, 'assistant');
          expect(reply.content, 'Half an answer\n\n*[Response interrupted]*');
          expect(reply.isError, isFalse);
          expect(provider.isAnyStreaming, isFalse);
        });

        test('keeps partial text that arrived after thinking', () async {
          stubStream(() async* {
            yield const ChatStreamEvent(thinkingToken: 'hmm');
            yield const ChatStreamEvent(contentToken: 'Half');
            throw closedEarly();
          });

          await provider.sendMessage('hi');

          final reply = conv.messages.last;
          expect(reply.content, 'Half\n\n*[Response interrupted]*');
          expect(reply.thinking, 'hmm');
          expect(reply.isError, isFalse);
        });

        test('with nothing received it is an error bubble you can retry',
            () async {
          stubStream(() async* {
            throw closedEarly();
          });

          await provider.sendMessage('hi');

          final reply = conv.messages.last;
          expect(reply.isError, isTrue);
          expect(reply.content, contains('Connection closed before'));
          expect(conv.messages.length, 2);
        });

        test('is not flagged as cut off', () async {
          stubStream(() async* {
            yield const ChatStreamEvent(contentToken: 'Half');
            throw closedEarly();
          });

          await provider.sendMessage('hi');

          expect(conv.messages.last.cutOff, isFalse);
        });

        test('after a user stop it still renders as a stop, not an error',
            () async {
          // The stop closes the client; if that ever surfaces as a clean
          // close, the service reports it with the same exception — the
          // exchange's own cancelled flag decides how it reads.
          final controller = StreamController<ChatStreamEvent>();
          when(() => mock.cancelStream()).thenAnswer((_) {});
          stubStream(() => controller.stream);

          final send = provider.sendMessage('hi');
          await Future<void>.delayed(Duration.zero);
          controller.add(const ChatStreamEvent(contentToken: 'Hello'));
          await Future<void>.delayed(Duration.zero);
          provider.stopStreaming();
          controller.addError(closedEarly());
          await controller.close();
          await send;

          final reply = conv.messages.last;
          expect(reply.content, 'Hello\n\n*[Response interrupted]*');
          expect(reply.isError, isFalse);
        });

        test('a stop before any output removes the bubble without an error',
            () async {
          final controller = StreamController<ChatStreamEvent>();
          when(() => mock.cancelStream()).thenAnswer((_) {});
          stubStream(() => controller.stream);

          final send = provider.sendMessage('hi');
          await Future<void>.delayed(Duration.zero);
          provider.stopStreaming();
          controller.addError(closedEarly());
          await controller.close();
          await send;

          expect(conv.messages.map((m) => m.role), ['user']);
        });
      });

      // The same flows with the real OllamaService against a local server,
      // so the cut is produced by actual HTTP behaviour instead of a mock
      // that is told what to throw.
      group('against a real server', () {
        late HttpServer server;
        late ChatProvider real;
        late Conversation realConv;

        late HttpOverrides? previousOverrides;

        setUp(() {
          // flutter_test answers every HTTP request with a 400 by default.
          previousOverrides = HttpOverrides.current;
          HttpOverrides.global = null;
        });

        tearDown(() {
          HttpOverrides.global = previousOverrides;
        });

        Future<void> serve(void Function(HttpRequest) handler) async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen(handler);
          addTearDown(() => server.close(force: true));
          real = ChatProvider();
          addTearDown(real.dispose);
          real.setService(OllamaService('http://127.0.0.1:${server.port}'));
          realConv = real.createConversation('llama3');
        }

        String line(Map<String, dynamic> json) => '${jsonEncode(json)}\n';

        Map<String, dynamic> token(String text) => {
              'message': {'role': 'assistant', 'content': text},
              'done': false,
            };

        test('a clean close without a done line is shown as interrupted',
            () async {
          await serve((req) {
            req.response
              ..write(line(token('Half an ')))
              ..write(line(token('answer')));
            req.response.close(); // ends cleanly, no done line
          });

          await real.sendMessage('hi');

          final reply = realConv.messages.last;
          expect(reply.content, 'Half an answer\n\n*[Response interrupted]*');
          expect(reply.isError, isFalse);
        });

        test('a complete reply is untouched and length is flagged', () async {
          await serve((req) {
            req.response
              ..write(line(token('Cut ')))
              ..write(line({
                'message': {'role': 'assistant', 'content': 'off'},
                'done': true,
                'done_reason': 'length',
              }));
            req.response.close();
          });

          await real.sendMessage('hi');

          final reply = realConv.messages.last;
          expect(reply.content, 'Cut off');
          expect(reply.cutOff, isTrue);
          expect(reply.isError, isFalse);
        });

        test('a user stop mid-reply renders as a stop', () async {
          await serve((req) async {
            req.response.bufferOutput = false;
            req.response.write(line(token('Hello')));
            await req.response.flush();
            // never finishes on its own
          });

          final send = real.sendMessage('hi');
          // wait until the first token reached the bubble
          while (realConv.messages.length < 2 ||
              realConv.messages.last.content.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          real.stopStreaming();
          await send.timeout(const Duration(seconds: 5));

          final reply = realConv.messages.last;
          expect(reply.content, 'Hello\n\n*[Response interrupted]*');
          expect(reply.isError, isFalse);
          expect(real.isAnyStreaming, isFalse);
        });
      });
    });

    test('error responses are excluded from the resent history', () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      provider.createConversation('llama3');

      var call = 0;
      final captured = <List<ChatMessage>>[];
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((inv) {
        captured.add(List.of(inv.positionalArguments[1] as List<ChatMessage>));
        call++;
        if (call == 1) return Stream.error(Exception('server died'));
        return Stream.fromIterable(
            [const ChatStreamEvent(contentToken: 'ok', done: true)]);
      });

      await provider.sendMessage('first');
      await provider.sendMessage('second');

      expect(captured, hasLength(2));
      expect(captured[1].any((m) => m.isError), isFalse);
    });

    test('deleteMessagePair removes the user message and its responses', () {
      final conv = provider.createConversation('llama3');
      final q1 = ChatMessage(role: 'user', content: 'q1');
      conv.messages.addAll([
        q1,
        ChatMessage(role: 'assistant', content: 'a1'),
        ChatMessage(role: 'tool', content: 't1'),
        ChatMessage(role: 'user', content: 'q2'),
        ChatMessage(role: 'assistant', content: 'a2'),
      ]);

      provider.deleteMessagePair(q1);

      expect(conv.messages.map((m) => m.content), ['q2', 'a2']);
    });

    test('deleteConversationForUndo returns the removed entry for restore',
        () {
      final a = provider.createConversation('llama3');
      provider.createConversation('phi3');

      final removed = provider.deleteConversationForUndo(a.id);

      expect(removed, isNotNull);
      expect(removed!.$1.id, a.id);
      expect(provider.conversations, hasLength(1));

      provider.restoreConversation(removed.$1, removed.$2);
      expect(provider.conversations, hasLength(2));
      expect(provider.conversations.map((c) => c.id), contains(a.id));
    });

    group('undo for deleted conversations', () {
      test('a second delete keeps the first one restorable, in order', () {
        final a = provider.createConversation('llama3');
        final b = provider.createConversation('phi3');
        final c = provider.createConversation('qwen3');
        final original = provider.conversations.map((x) => x.id).toList();

        provider.deleteConversationWithUndo(a.id);
        provider.deleteConversationWithUndo(c.id);
        expect(provider.undoableDeletes, 2);
        expect(provider.conversations.map((x) => x.id), [b.id]);

        provider.undoDelete();

        expect(provider.undoableDeletes, 0);
        expect(provider.conversations.map((x) => x.id), original);
      });

      // testWidgets for its fake clock: pump() advances the undo timer.
      testWidgets('the offer expires after the undo window', (tester) async {
        final a = provider.createConversation('llama3');
        provider.deleteConversationWithUndo(a.id);

        await tester
            .pump(ChatProvider.undoWindow - const Duration(seconds: 1));
        expect(provider.undoableDeletes, 1);

        await tester.pump(const Duration(seconds: 1));
        expect(provider.undoableDeletes, 0);
        provider.undoDelete();
        expect(provider.conversations, isEmpty);
      });

      testWidgets('a further delete restarts the window for the whole batch',
          (tester) async {
        final a = provider.createConversation('llama3');
        final b = provider.createConversation('phi3');
        provider.deleteConversationWithUndo(a.id);
        await tester.pump(const Duration(seconds: 4));
        provider.deleteConversationWithUndo(b.id);
        await tester.pump(const Duration(seconds: 4));

        // 8 s after the first delete, but only 4 s after the second
        expect(provider.undoableDeletes, 2);

        await tester.pump(const Duration(seconds: 1));
        expect(provider.undoableDeletes, 0);
      });

      test('delete all leaves nothing to undo', () async {
        final a = provider.createConversation('llama3');
        provider.createConversation('phi3');
        provider.deleteConversationWithUndo(a.id);

        await provider.deleteAllConversations();
        provider.undoDelete();

        expect(provider.undoableDeletes, 0);
        expect(provider.conversations, isEmpty);
      });
    });

    test('multiple pending images attach to the sent message', () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      final conv = provider.createConversation('llava');
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => Stream.fromIterable(
          [const ChatStreamEvent(contentToken: 'ok', done: true)]));

      provider.addPendingImage('img1');
      provider.addPendingImage('img2');
      provider.addPendingImage('img3');
      provider.removePendingImageAt(1);
      expect(provider.pendingImages, ['img1', 'img3']);

      await provider.sendMessage('look');

      expect(conv.messages.first.images, ['img1', 'img3']);
      expect(provider.pendingImages, isEmpty);
    });

    test('draft is consumed once', () {
      provider.setDraft('Summarize this: ');
      expect(provider.takeDraft(), 'Summarize this: ');
      expect(provider.takeDraft(), isNull);
    });

    test('auto-title is emoji-safe and single-line', () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => Stream.fromIterable(
          [const ChatStreamEvent(contentToken: 'ok', done: true)]));
      when(() => mock.generateText(any(), any(), think: any(named: 'think')))
          .thenAnswer((_) async => '');

      final emoji = provider.createConversation('llama3');
      await provider.sendMessage('🎉' * 40);
      // 30 whole emoji + ellipsis — never a split surrogate pair
      expect(emoji.title, '${'🎉' * 30}...');

      final newline = provider.createConversation('llama3');
      await provider.sendMessage('line one\nline two of a much longer text');
      expect(newline.title.contains('\n'), isFalse);
    });

    test('a failure mid-tool-loop rolls back dangling tool results',
        () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      provider.setSearxngUrl('http://searx.local');
      final conv = provider.createConversation('qwen3');
      conv.webSearchEnabled = true;

      var call = 0;
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) {
        call++;
        if (call == 1) {
          // First leg succeeds and asks for a web search…
          return Stream.fromIterable([
            ChatStreamEvent(
              toolCalls: [
                {
                  'function': {
                    'name': 'web_search',
                    'arguments': {'query': 'dart'},
                  },
                },
              ],
              done: true,
            ),
          ]);
        }
        // …the follow-up stream dies.
        return Stream.error(Exception('server died'));
      });
      when(() => mock.searchSearXNG(any(), any())).thenAnswer((_) async => [
            {'title': 't', 'url': 'u', 'content': 'c'},
          ]);

      await provider.sendMessage('search something');

      // Exactly one clean pair may survive: no orphaned tool results whose
      // parent bubble became an error and gets filtered out on resend.
      expect(conv.messages.map((m) => m.role), ['user', 'assistant']);
      expect(conv.messages.last.isError, isTrue);
      expect(conv.messages.last.toolCalls, isNull);
    });

    group('titles survive retrying and editing the opener', () {
      late MockOllamaService mock;

      setUp(() {
        mock = MockOllamaService();
        provider.setService(mock);
        when(() => mock.streamChat(
              any(),
              any(),
              think: any(named: 'think'),
              tools: any(named: 'tools'),
              numCtx: any(named: 'numCtx'),
            )).thenAnswer((_) => Stream.fromIterable(
            [const ChatStreamEvent(contentToken: 'ok', done: true)]));
      });

      test('retrying the opener keeps a generated title', () async {
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenAnswer((_) async => 'Generated Title');
        final conv = provider.createConversation('llama3');

        await provider.sendMessage('Tell me about Paris');
        await pumpEventQueue();
        expect(conv.title, 'Generated Title');

        await provider.retryLastMessage();
        await pumpEventQueue();

        // A retry must not downgrade the generated title to the fallback,
        // nor ask the model for another one.
        expect(conv.title, 'Generated Title');
        verify(() => mock.generateText(any(), any(),
            think: any(named: 'think'))).called(1);
      });

      test('editing the opener moves a fallback title in step', () async {
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenAnswer((_) async => '');
        final conv = provider.createConversation('llama3');

        await provider.sendMessage('first question');
        expect(conv.title, 'first question');

        await provider.editAndResend(conv.messages.first, 'edited question');

        expect(conv.title, 'edited question');
      });

      test('editing the opener never downgrades a generated title',
          () async {
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenAnswer((_) async => 'Generated Title');
        final conv = provider.createConversation('llama3');

        await provider.sendMessage('Tell me about Paris');
        await pumpEventQueue();
        expect(conv.title, 'Generated Title');

        await provider.editAndResend(conv.messages.first, 'Edited opener');
        await pumpEventQueue();

        expect(conv.title, 'Generated Title');
      });
    });

    test('retry/edit refuse to touch history while another chat generates',
        () async {
      final mock = MockOllamaService();
      final controller = StreamController<ChatStreamEvent>();
      provider.setService(mock);
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => controller.stream);

      final a = provider.createConversation('llama3');
      final b = provider.createConversation('phi3');
      b.messages.addAll([
        ChatMessage(role: 'user', content: 'b q'),
        ChatMessage(role: 'assistant', content: 'b a'),
      ]);
      provider.setActiveConversation(a);

      final send = provider.sendMessage('hi');
      await Future<void>.delayed(Duration.zero);
      provider.setActiveConversation(b);

      // Both destructive paths must bail out BEFORE mutating history —
      // otherwise a refused retry would still delete the exchange.
      await provider.retryLastMessage();
      await provider.editAndResend(b.messages.first, 'rewritten');

      expect(b.messages.map((m) => m.content), ['b q', 'b a']);

      controller.add(const ChatStreamEvent(contentToken: 'done', done: true));
      await controller.close();
      await send;
    });

    test('retry/edit refuse while disconnected', () async {
      final conv = provider.createConversation('llama3');
      conv.messages.addAll([
        ChatMessage(role: 'user', content: 'q'),
        ChatMessage(role: 'assistant', content: 'a'),
      ]);
      // No service set — both calls must be no-ops.

      await provider.retryLastMessage();
      await provider.editAndResend(conv.messages.first, 'x');

      expect(conv.messages.length, 2);
      expect(conv.messages.first.content, 'q');
      expect(conv.messages.last.content, 'a');
    });

    group('web search tool loop', () {
      late MockOllamaService mock;
      late Conversation conv;

      setUp(() {
        mock = MockOllamaService();
        provider.setService(mock);
        provider.setSearxngUrl('http://searx.local');
        conv = provider.createConversation('qwen3');
        conv.webSearchEnabled = true;
        when(() => mock.cancelStream()).thenAnswer((_) {});
        when(() => mock.generateText(any(), any(), think: any(named: 'think')))
            .thenAnswer((_) async => '');
      });

      /// Stubs `streamChat`; [answer] gets the 1-based leg number and the
      /// invocation (positional 0 = model, 1 = messages, named #tools).
      void stubLegs(Stream<ChatStreamEvent> Function(int leg, Invocation inv) answer) {
        var leg = 0;
        when(() => mock.streamChat(
              any(),
              any(),
              think: any(named: 'think'),
              tools: any(named: 'tools'),
              numCtx: any(named: 'numCtx'),
            )).thenAnswer((inv) => answer(++leg, inv));
      }

      void verifyLegs(int times) {
        verify(() => mock.streamChat(
              any(),
              any(),
              think: any(named: 'think'),
              tools: any(named: 'tools'),
              numCtx: any(named: 'numCtx'),
            )).called(times);
      }

      Stream<ChatStreamEvent> toolCallLeg(Object? query) =>
          Stream.fromIterable(
              [ChatStreamEvent(toolCalls: [searchCall(query)], done: true)]);

      Stream<ChatStreamEvent> answerLeg([String text = 'answer']) =>
          Stream.fromIterable(
              [ChatStreamEvent(contentToken: text, done: true)]);

      const oneResult = [
        {'title': 't', 'url': 'u', 'content': 'c'},
      ];

      group('stopping', () {
        test('stop during a pending search ends the exchange quietly',
            () async {
          final search = Completer<List<Map<String, dynamic>>>();
          stubLegs((_, _) => toolCallLeg('dart'));
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) => search.future);

          final send = provider.sendMessage('question');
          await pumpEventQueue();
          verify(() => mock.searchSearXNG(any(), 'dart')).called(1);
          provider.stopStreaming();
          search.complete([...oneResult]);
          await send;
          await pumpEventQueue();

          // no second leg, no error bubble, nothing half-finished left behind
          verifyLegs(1);
          expect(conv.messages.map((m) => m.role), ['user']);
          expect(provider.isAnyStreaming, isFalse);
          expect(provider.isStreaming, isFalse);
        });

        test('stop returns without waiting for a slow search', () async {
          final search = Completer<List<Map<String, dynamic>>>();
          stubLegs((_, _) => toolCallLeg('dart'));
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) => search.future);

          final send = provider.sendMessage('question');
          await pumpEventQueue();
          provider.stopStreaming();
          await send; // would hang until the search finished before the fix

          expect(provider.isAnyStreaming, isFalse);
          // the late result is discarded, not acted on
          search.complete([...oneResult]);
          await pumpEventQueue();
          verifyLegs(1);
          expect(conv.messages.map((m) => m.role), ['user']);
        });

        test('stop after the tool-call leg finished starts no search',
            () async {
          final controller = StreamController<ChatStreamEvent>();
          stubLegs((_, _) => controller.stream);

          final send = provider.sendMessage('question');
          await pumpEventQueue();
          controller.add(ChatStreamEvent(toolCalls: [searchCall('dart')]));
          await pumpEventQueue();
          // The stream was not torn down (the mock's cancel is a no-op), so
          // the leg ends normally — but the stop must still win.
          provider.stopStreaming();
          await controller.close();
          await send;

          verifyNever(() => mock.searchSearXNG(any(), any()));
          verifyLegs(1);
          expect(conv.messages.map((m) => m.role), ['user']);
        });

        test('a stop keeps the partial text of the interrupted leg',
            () async {
          final controller = StreamController<ChatStreamEvent>();
          stubLegs((_, _) => controller.stream);

          final send = provider.sendMessage('question');
          await pumpEventQueue();
          controller.add(ChatStreamEvent(
              contentToken: 'Let me look', toolCalls: [searchCall('dart')]));
          await pumpEventQueue();
          provider.stopStreaming();
          await controller.close();
          await send;

          expect(conv.messages.map((m) => m.role), ['user', 'assistant']);
          expect(conv.messages.last.content,
              'Let me look\n\n*[Response interrupted]*');
          expect(conv.messages.last.toolCalls, isNull);
          expect(conv.messages.last.isError, isFalse);
        });

        test('a stop does not make the next exchange\'s failure look like one',
            () async {
          final search = Completer<List<Map<String, dynamic>>>();
          stubLegs((leg, _) {
            if (leg == 1) return toolCallLeg('dart');
            return Stream.error(Exception('server died'));
          });
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) => search.future);

          final first = provider.sendMessage('one');
          await pumpEventQueue();
          provider.stopStreaming();
          search.complete([...oneResult]);
          await first;

          await provider.sendMessage('two');

          // the stale stop flag used to swallow this error
          expect(conv.messages.last.isError, isTrue);
          expect(conv.messages.last.content, contains('server died'));
        });

        test('an error in a later leg still produces an error bubble',
            () async {
          stubLegs((leg, _) => leg == 1
              ? toolCallLeg('dart')
              : Stream.error(Exception('server died')));
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) async => [...oneResult]);

          await provider.sendMessage('question');

          expect(conv.messages.map((m) => m.role), ['user', 'assistant']);
          expect(conv.messages.last.isError, isTrue);
        });

        test('an exchange orphaned by disconnect never touches the next one',
            () async {
          final search = Completer<List<Map<String, dynamic>>>();
          stubLegs((_, _) => toolCallLeg('dart'));
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) => search.future);

          final orphan = provider.sendMessage('first');
          await pumpEventQueue();
          provider.disconnectService();

          // quick reconnect to a fresh service, then a new send
          final mock2 = MockOllamaService();
          final controller = StreamController<ChatStreamEvent>();
          when(() => mock2.streamChat(
                any(),
                any(),
                think: any(named: 'think'),
                tools: any(named: 'tools'),
                numCtx: any(named: 'numCtx'),
              )).thenAnswer((_) => controller.stream);
          when(() => mock2.generateText(any(), any(),
              think: any(named: 'think'))).thenAnswer((_) async => '');
          provider.setService(mock2);
          final other = provider.createConversation('phi3');
          final next = provider.sendMessage('second');
          await pumpEventQueue();

          // the orphan winds down in the background…
          search.complete([...oneResult]);
          await orphan;
          await pumpEventQueue();

          // …without clearing the new exchange's streaming state…
          expect(provider.isAnyStreaming, isTrue);
          expect(provider.isStreaming, isTrue);
          // …or starting another leg on either service
          verifyLegs(1);
          verify(() => mock2.streamChat(
                any(),
                any(),
                think: any(named: 'think'),
                tools: any(named: 'tools'),
                numCtx: any(named: 'numCtx'),
              )).called(1);

          controller.add(const ChatStreamEvent(contentToken: 'ok', done: true));
          await controller.close();
          await next;
          expect(other.messages.map((m) => m.content), ['second', 'ok']);
          expect(provider.isAnyStreaming, isFalse);
        });

        test('an orphan on the same chat leaves the later exchange\'s messages',
            () async {
          final search = Completer<List<Map<String, dynamic>>>();
          stubLegs((_, _) => toolCallLeg('dart'));
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) => search.future);

          final orphan = provider.sendMessage('first');
          await pumpEventQueue();
          provider.disconnectService();

          final mock2 = MockOllamaService();
          final controller = StreamController<ChatStreamEvent>();
          when(() => mock2.streamChat(
                any(),
                any(),
                think: any(named: 'think'),
                tools: any(named: 'tools'),
                numCtx: any(named: 'numCtx'),
              )).thenAnswer((_) => controller.stream);
          provider.setService(mock2);
          provider.setActiveConversation(conv); // same chat again
          final next = provider.sendMessage('second');
          await pumpEventQueue();
          search.complete([...oneResult]);
          await orphan;
          await pumpEventQueue();

          // The orphan's rollback must not eat the new exchange's bubbles,
          // and the new exchange's own rollback must still find its tail.
          expect(conv.messages.map((m) => m.role),
              ['user', 'user', 'assistant']);
          controller.addError(Exception('server died'));
          await controller.close();
          await next;
          expect(conv.messages.map((m) => m.role),
              ['user', 'user', 'assistant']);
          expect(conv.messages.last.isError, isTrue);
        });
      });

      test('parallel tool calls from separate chunks are all executed',
          () async {
        stubLegs((leg, _) => leg == 1
            ? Stream.fromIterable([
                ChatStreamEvent(toolCalls: [searchCall('alpha')]),
                ChatStreamEvent(toolCalls: [searchCall('beta')], done: true),
              ])
            : answerLeg());
        when(() => mock.searchSearXNG(any(), any()))
            .thenAnswer((_) async => [...oneResult]);

        await provider.sendMessage('question');

        verify(() => mock.searchSearXNG(any(), 'alpha')).called(1);
        verify(() => mock.searchSearXNG(any(), 'beta')).called(1);
        expect(conv.messages.map((m) => m.role),
            ['user', 'assistant', 'tool', 'tool', 'assistant']);
        expect(conv.messages[1].toolCalls, hasLength(2));
      });

      group('iteration cap', () {
        test('the last leg is sent without tools so the model must answer',
            () async {
          final toolsPerLeg = <Object?>[];
          stubLegs((leg, inv) {
            toolsPerLeg.add(inv.namedArguments[#tools]);
            return leg < 5 ? toolCallLeg('q$leg') : answerLeg('final answer');
          });
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) async => [...oneResult]);

          await provider.sendMessage('question');

          expect(toolsPerLeg, hasLength(5));
          expect(toolsPerLeg.take(4), everyElement(isNotNull));
          expect(toolsPerLeg.last, isNull);
          expect(conv.messages.last.role, 'assistant');
          expect(conv.messages.last.content, 'final answer');
        });

        test('tool calls on the tool-less last leg are ignored', () async {
          stubLegs((leg, _) => toolCallLeg('q$leg'));
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) async => [...oneResult]);

          await provider.sendMessage('question');

          verifyLegs(5);
          verify(() => mock.searchSearXNG(any(), any())).called(4);
          // no dangling tool-calling bubble after the last tool result — the
          // answerless last leg is reported, not left as an empty bubble
          expect(conv.messages.last.role, 'assistant');
          expect(conv.messages.last.isError, isTrue);
          expect(conv.messages.last.toolCalls, isNull);
          expect(provider.isAnyStreaming, isFalse);
        });
      });

      group('models without the tools capability', () {
        test('are not sent tools even when the chat has web search on',
            () async {
          Object? sentTools = 'unset';
          stubLegs((_, inv) {
            sentTools = inv.namedArguments[#tools];
            return answerLeg();
          });

          await provider.sendMessage('question',
              capabilities: const ModelCapabilities(supportsTools: false));

          expect(sentTools, isNull);
        });

        test('tools are still sent while capabilities are unknown', () async {
          Object? sentTools;
          stubLegs((_, inv) {
            sentTools = inv.namedArguments[#tools];
            return answerLeg();
          });

          await provider.sendMessage('question');

          expect(sentTools, isNotNull);
        });
      });

      group('empty replies', () {
        test('a completely empty reply becomes an error bubble', () async {
          stubLegs((_, _) =>
              Stream.fromIterable([const ChatStreamEvent(done: true)]));

          await provider.sendMessage('question');

          expect(conv.messages.map((m) => m.role), ['user', 'assistant']);
          expect(conv.messages.last.isError, isTrue);
          expect(conv.messages.last.content, isNotEmpty);
        });

        test('an empty final answer after a tool call becomes an error bubble',
            () async {
          stubLegs((leg, _) => leg == 1
              ? toolCallLeg('dart')
              : Stream.fromIterable([const ChatStreamEvent(done: true)]));
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) async => [...oneResult]);

          await provider.sendMessage('question');

          expect(conv.messages.map((m) => m.role),
              ['user', 'assistant', 'tool', 'assistant']);
          expect(conv.messages.last.isError, isTrue);
        });

        test('a thinking-only reply is kept', () async {
          stubLegs((_, _) => Stream.fromIterable(
              [const ChatStreamEvent(thinkingToken: 'hmm', done: true)]));

          await provider.sendMessage('question');

          expect(conv.messages.map((m) => m.role), ['user', 'assistant']);
          expect(conv.messages.last.thinking, 'hmm');
        });
      });

      group('malformed tool calls', () {
        ChatMessage? lastToolMessage() =>
            conv.messages.where((m) => m.role == 'tool').lastOrNull;

        test('a non-string query is coerced to text', () async {
          stubLegs((leg, _) => leg == 1 ? toolCallLeg(42) : answerLeg());
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) async => [...oneResult]);

          await provider.sendMessage('question');

          verify(() => mock.searchSearXNG(any(), '42')).called(1);
          expect(conv.messages.last.content, 'answer');
        });

        test('arguments sent as a JSON string are parsed and echoed as an object',
            () async {
          final captured = <List<ChatMessage>>[];
          stubLegs((leg, inv) {
            captured.add(List.of(inv.positionalArguments[1] as List<ChatMessage>));
            return leg == 1
                ? Stream.fromIterable([
                    const ChatStreamEvent(toolCalls: [
                      {
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "dart"}',
                        },
                      },
                    ], done: true),
                  ])
                : answerLeg();
          });
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) async => [...oneResult]);

          await provider.sendMessage('question');

          verify(() => mock.searchSearXNG(any(), 'dart')).called(1);
          // Ollama rejects string arguments in the resent history
          final echoed = captured[1].firstWhere((m) => m.toolCalls != null);
          final arguments =
              (echoed.toolCalls!.single['function'] as Map)['arguments'];
          expect(arguments, {'query': 'dart'});
        });

        test('unusable calls become tool results instead of failing the exchange',
            () async {
          stubLegs((leg, _) => leg == 1
              ? Stream.fromIterable([
                  const ChatStreamEvent(toolCalls: [
                    {
                      'function': {
                        'name': 'web_search',
                        'arguments': '{not json',
                      },
                    },
                    {'id': 'no-function'},
                    {
                      'function': {'name': 'web_search', 'arguments': '[1]'},
                    },
                  ], done: true),
                ])
              : answerLeg());

          await provider.sendMessage('question');

          verifyNever(() => mock.searchSearXNG(any(), any()));
          final tools = conv.messages.where((m) => m.role == 'tool').toList();
          // exactly one tool message per call, in order
          expect(tools, hasLength(3));
          expect(tools[0].content, startsWith('Invalid tool arguments'));
          expect(tools[1].content, startsWith('Invalid tool call'));
          expect(tools[2].content, startsWith('Invalid tool arguments'));
          expect(conv.messages.last.content, 'answer');
          expect(conv.messages.any((m) => m.isError), isFalse);
        });

        test('missing arguments search with an empty query', () async {
          stubLegs((leg, _) => leg == 1
              ? Stream.fromIterable([
                  const ChatStreamEvent(toolCalls: [
                    {
                      'function': {'name': 'web_search'},
                    },
                  ], done: true),
                ])
              : answerLeg());
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) async => [...oneResult]);

          await provider.sendMessage('question');

          verify(() => mock.searchSearXNG(any(), '')).called(1);
        });

        test('zero search results are reported as such', () async {
          stubLegs((leg, _) => leg == 1 ? toolCallLeg('dart') : answerLeg());
          when(() => mock.searchSearXNG(any(), any()))
              .thenAnswer((_) async => []);

          await provider.sendMessage('question');

          expect(lastToolMessage()!.content, 'No results found.');
        });
      });

      test('a model switch mid-exchange applies from the next message',
          () async {
        final models = <Object?>[];
        stubLegs((leg, inv) {
          models.add(inv.positionalArguments[0]);
          return leg == 1 ? toolCallLeg('dart') : answerLeg();
        });
        when(() => mock.searchSearXNG(any(), any())).thenAnswer((_) async {
          // user picks another model while the search runs
          provider.changeConversationModel(conv.id, 'phi3');
          return [...oneResult];
        });

        await provider.sendMessage('question');
        await pumpEventQueue();

        expect(models, ['qwen3', 'qwen3']);
        // the title request belongs to the exchange too
        verify(() => mock.generateText('qwen3', any(),
            think: any(named: 'think'))).called(1);

        await provider.sendMessage('next');
        expect(models.last, 'phi3');
      });
    });

    test('retry does not consume attachments staged for the next message',
        () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      final conv = provider.createConversation('llava');
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => Stream.fromIterable(
          [const ChatStreamEvent(contentToken: 'ok', done: true)]));
      when(() => mock.generateText(any(), any(), think: any(named: 'think')))
          .thenAnswer((_) async => '');

      await provider.sendMessage('text only');
      provider.addPendingImage('staged-image');
      provider.setPendingFile('notes.txt', 'ZGF0YQ==', 'text/plain');

      await provider.retryLastMessage();

      expect(conv.messages.first.content, 'text only');
      expect(conv.messages.first.images, isNull);
      expect(conv.messages.first.files, isNull);
      expect(provider.pendingImages, ['staged-image']);
      expect(provider.pendingFileName, 'notes.txt');
    });

    test('retry and edit re-send the old message\'s own attachments only',
        () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      final conv = provider.createConversation('llava');
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => Stream.fromIterable(
          [const ChatStreamEvent(contentToken: 'ok', done: true)]));
      when(() => mock.generateText(any(), any(), think: any(named: 'think')))
          .thenAnswer((_) async => '');

      void seed() {
        conv.messages
          ..clear()
          ..addAll([
            ChatMessage(
              role: 'user',
              content: 'look',
              images: ['old-1', 'old-2'],
              files: [
                {'name': 'a.txt', 'data': 'YQ==', 'type': 'text/plain'},
                {'name': 'b.txt', 'data': 'Yg==', 'type': 'text/plain'},
              ],
            ),
            ChatMessage(role: 'assistant', content: 'seen'),
          ]);
      }

      provider.addPendingImage('staged-image');

      seed();
      await provider.retryLastMessage();
      expect(conv.messages.first.images, ['old-1', 'old-2']);
      expect(conv.messages.first.files!.map((f) => f['name']),
          ['a.txt', 'b.txt']);
      expect(provider.pendingImages, ['staged-image']);

      seed();
      await provider.editAndResend(conv.messages.first, 'look again');
      expect(conv.messages.first.content, 'look again');
      expect(conv.messages.first.images, ['old-1', 'old-2']);
      expect(conv.messages.first.files, hasLength(2));
      expect(provider.pendingImages, ['staged-image']);

      // …and a plain edit of a text-only message must not pick the staged
      // image up either
      conv.messages
        ..clear()
        ..addAll([
          ChatMessage(role: 'user', content: 'plain'),
          ChatMessage(role: 'assistant', content: 'ok'),
        ]);
      await provider.editAndResend(conv.messages.first, 'plain again');
      expect(conv.messages.first.images, isNull);
      expect(provider.pendingImages, ['staged-image']);
    });

    test('editing a later message with the opener\'s text keeps the title',
        () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      final conv = provider.createConversation('llama3');
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => Stream.fromIterable(
          [const ChatStreamEvent(contentToken: 'ok', done: true)]));
      when(() => mock.generateText(any(), any(), think: any(named: 'think')))
          .thenAnswer((_) async => '');

      await provider.sendMessage('continue');
      await provider.sendMessage('continue');
      expect(conv.title, 'continue');

      await provider.editAndResend(conv.messages[2], 'something else');

      expect(conv.title, 'continue');
    });

    test('importConversations dedupes within the imported batch', () {
      final added = provider.importConversations([
        Conversation(id: 'dup', model: 'llama3', title: 'first'),
        Conversation(id: 'dup', model: 'llama3', title: 'second'),
        Conversation(id: 'other', model: 'phi3'),
      ]);

      expect(added, 2);
      expect(provider.conversations.map((c) => c.id).toSet(),
          {'dup', 'other'});
      expect(provider.conversations, hasLength(2));
    });

    test('restoreConversation is a no-op when the id is already present', () {
      final a = provider.createConversation('llama3');
      final removed = provider.deleteConversationForUndo(a.id)!;

      provider.restoreConversation(removed.$1, removed.$2);
      provider.restoreConversation(removed.$1, removed.$2); // double undo

      expect(provider.conversations.where((c) => c.id == a.id), hasLength(1));
    });

    group('save failures', () {
      Future<List<Object>> uncaughtErrorsFrom(
          MockStorageService storage) async {
        final p = ChatProvider(storageService: storage);
        addTearDown(p.dispose);
        final errors = <Object>[];
        await runZonedGuarded(() async {
          p.createConversation('llama3');
          p.renameConversation(p.conversations.first.id, 'renamed');
          await pumpEventQueue();
        }, (e, _) => errors.add(e));
        verify(() => storage.saveConversations(any())).called(2);
        return errors;
      }

      test('an asynchronous failure does not escape as an unhandled error',
          () async {
        final storage = MockStorageService();
        when(() => storage.saveConversations(any()))
            .thenAnswer((_) async => throw Exception('disk full'));

        expect(await uncaughtErrorsFrom(storage), isEmpty);
      });

      test('a synchronous failure does not escape either', () async {
        final storage = MockStorageService();
        when(() => storage.saveConversations(any()))
            .thenThrow(Exception('unwritable'));

        expect(await uncaughtErrorsFrom(storage), isEmpty);
      });
    });

    test('long generated titles and prompts are cut on grapheme boundaries',
        () async {
      final mock = MockOllamaService();
      provider.setService(mock);
      final conv = provider.createConversation('llama3');
      when(() => mock.streamChat(
            any(),
            any(),
            think: any(named: 'think'),
            tools: any(named: 'tools'),
            numCtx: any(named: 'numCtx'),
          )).thenAnswer((_) => Stream.fromIterable(
          [const ChatStreamEvent(contentToken: 'ok', done: true)]));
      String? prompt;
      when(() => mock.generateText(any(), any(), think: any(named: 'think')))
          .thenAnswer((inv) async {
        prompt = inv.positionalArguments[1] as String;
        // an odd prefix puts the 60th UTF-16 unit in the middle of an emoji
        return 'a${'😀' * 70}';
      });

      await provider.sendMessage('a${'😀' * 600}');
      await pumpEventQueue();

      expect(conv.title, 'a${'😀' * 59}…');
      expect(prompt, contains('User: a${'😀' * 499}\n\nAssistant:'));
    });
  });
}

Map<String, dynamic> searchCall(Object? query) => {
      'function': {
        'name': 'web_search',
        'arguments': {'query': query},
      },
    };
