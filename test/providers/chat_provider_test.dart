import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/providers/chat_provider.dart';
import 'package:llm_disco_test1/models/conversation.dart';
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
  });
}
