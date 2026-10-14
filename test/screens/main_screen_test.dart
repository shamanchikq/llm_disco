import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/models/conversation.dart';
import 'package:llm_disco_test1/providers/chat_provider.dart';
import 'package:llm_disco_test1/providers/connection_provider.dart';
import 'package:llm_disco_test1/providers/model_provider.dart';
import 'package:llm_disco_test1/screens/main_screen.dart';
import 'package:llm_disco_test1/services/ollama_service.dart';
import 'package:llm_disco_test1/services/storage_service.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';
import 'package:llm_disco_test1/widgets/message_bubble.dart';
import '../helpers/mocks.dart';

// 1x1 PNGs: red and blue.
const _redPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
const _bluePng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC';

Widget _wrap(ChatProvider chat, {ModelProvider? models}) {
  return MultiProvider(
    providers: [
      Provider<StorageService>.value(value: MockStorageService()),
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider(create: (_) => ConnectionProvider()),
      ChangeNotifierProvider.value(value: models ?? ModelProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const MainScreen(),
    ),
  );
}

/// A ModelProvider with [names] installed (first one selected).
Future<ModelProvider> _modelsWith(
    WidgetTester tester, List<String> names) async {
  final models = ModelProvider();
  final service = MockOllamaService();
  when(() => service.fetchModels()).thenAnswer((_) async => names);
  when(() => service.fetchModelInfo(any()))
      .thenAnswer((_) async => <String, dynamic>{'capabilities': []});
  await models.fetchModels(service);
  await tester.pump();
  return models;
}

/// A service whose chat stream stays open until the test feeds/closes it.
(MockOllamaService, StreamController<ChatStreamEvent>) _openService() {
  final service = MockOllamaService();
  final controller = StreamController<ChatStreamEvent>();
  when(() => service.streamChat(
        any(),
        any(),
        think: any(named: 'think'),
        tools: any(named: 'tools'),
        numCtx: any(named: 'numCtx'),
      )).thenAnswer((_) => controller.stream);
  return (service, controller);
}

List<Uint8List> _shownImages(WidgetTester tester) => [
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        (image.image as MemoryImage).bytes,
    ];

ScrollPosition _listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
        .first)
    .position;

/// [pairs] user/assistant exchanges, tall enough to scroll.
Conversation _longChat(String id, {int pairs = 30}) {
  final filler = List.filled(8, 'lorem ipsum dolor sit amet').join(' ');
  return Conversation(id: id, model: 'llama3', title: 'Chat $id', messages: [
    for (var i = 0; i < pairs; i++) ...[
      ChatMessage(role: 'user', content: 'q$i $filler'),
      ChatMessage(role: 'assistant', content: 'a$i $filler'),
    ],
  ]);
}

void main() {
  group('settings parsing', () {
    test('empty means "use the default"', () {
      expect(parseDecimalSetting('').value, isNull);
      expect(parseDecimalSetting('   ').error, isNull);
      expect(parseIntSetting('').value, isNull);
      expect(parseIntSetting(' ').error, isNull);
    });

    test('comma decimals are accepted', () {
      expect(parseDecimalSetting('0,3').value, 0.3);
      expect(parseDecimalSetting(' 0.7 ').value, 0.7);
      expect(parseDecimalSetting('1,05', min: 0, minExclusive: true).value,
          1.05);
    });

    test('non-numeric and non-finite decimals are rejected', () {
      for (final bad in ['abc', 'NaN', 'nan', '1e999', '-1e999', 'Infinity',
          '1.2.3', '0,3,1', '--1']) {
        final r = parseDecimalSetting(bad);
        expect(r.value, isNull, reason: bad);
        expect(r.error, isNotNull, reason: bad);
      }
    });

    test('decimal ranges', () {
      // temperature >= 0
      expect(parseDecimalSetting('0', min: 0).value, 0);
      expect(parseDecimalSetting('-5', min: 0).error, isNotNull);
      // top_p within 0..1, inclusive
      expect(parseDecimalSetting('1', min: 0, max: 1).value, 1);
      expect(parseDecimalSetting('7', min: 0, max: 1).error, isNotNull);
      expect(parseDecimalSetting('-0,1', min: 0, max: 1).error, isNotNull);
      // repeat_penalty > 0
      expect(parseDecimalSetting('0', min: 0, minExclusive: true).error,
          isNotNull);
      expect(parseDecimalSetting('1,1', min: 0, minExclusive: true).value,
          1.1);
    });

    test('integers ignore spaces and underscores', () {
      expect(parseIntSetting('8192').value, 8192);
      expect(parseIntSetting(' 8 192 ').value, 8192);
      expect(parseIntSetting('8_192').value, 8192);
    });

    test('bad integers are rejected', () {
      for (final bad in ['abc', '3.5', '3,5', '1e3', '99999999999999999999']) {
        expect(parseIntSetting(bad, min: 1).error, isNotNull, reason: bad);
      }
      expect(parseIntSetting('0', min: 1).error, isNotNull);
      expect(parseIntSetting('-4', min: 1).error, isNotNull);
      expect(parseIntSetting('1', min: 1).value, 1);
      // seed has no lower bound
      expect(parseIntSetting('-4').value, -4);
    });
  });

  group('chat settings sheet', () {
    Future<Conversation> openSheet(WidgetTester tester,
        {void Function(Conversation)? setup}) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final chat = ChatProvider();
      addTearDown(chat.dispose);
      final conversation = chat.createConversation('llama3');
      setup?.call(conversation);
      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ctx'));
      await tester.pumpAndSettle();
      expect(find.text('Chat settings'), findsOneWidget);
      return conversation;
    }

    testWidgets('an invalid value keeps the sheet open and saves nothing',
        (tester) async {
      final conversation = await openSheet(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'Temperature'), '-5');
      await tester.enterText(
          find.widgetWithText(TextField, 'Top P'), '0,5');
      await tester.enterText(
          find.widgetWithText(TextField, 'Tokens'), '8192');
      await tester.enterText(find.byType(TextField).first, 'Be brief');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // still open, error shown next to the bad field
      expect(find.text('Chat settings'), findsOneWidget);
      expect(find.text('Must be 0 or more'), findsOneWidget);
      // nothing half-applied
      expect(conversation.temperature, isNull);
      expect(conversation.topP, isNull);
      expect(conversation.numCtx, isNull);
      expect(conversation.systemPrompt, isNull);
    });

    testWidgets('correcting the value saves everything and closes',
        (tester) async {
      final conversation = await openSheet(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'Temperature'), 'warm');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number'), findsOneWidget);

      // editing the field clears its error; comma decimals now work
      await tester.enterText(
          find.widgetWithText(TextField, 'Temperature'), '0,3');
      await tester.pump();
      expect(find.text('Enter a number'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Top K'), '40');
      await tester.enterText(
          find.widgetWithText(TextField, 'Tokens'), '8 192');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Chat settings'), findsNothing);
      expect(conversation.temperature, 0.3);
      expect(conversation.topK, 40);
      expect(conversation.numCtx, 8192);
    });

    testWidgets('a non-finite number never reaches the conversation',
        (tester) async {
      final conversation = await openSheet(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'Repeat penalty'), '1e999');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Chat settings'), findsOneWidget);
      expect(conversation.repeatPenalty, isNull);
      expect(() => conversation.toJson(), returnsNormally);
    });

    testWidgets('clearing a field resets it to the default', (tester) async {
      final conversation =
          await openSheet(tester, setup: (c) => c.temperature = 0.9);
      expect(find.text('0.9'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Temperature'), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Chat settings'), findsNothing);
      expect(conversation.temperature, isNull);
    });
  });

  group('message list', () {
    testWidgets('a new image message does not show the previous image',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        Conversation(id: 'c', model: 'llava', messages: [
          ChatMessage(role: 'user', content: 'one', images: [_redPng]),
          ChatMessage(role: 'assistant', content: 'a red pixel'),
        ]),
      ]);
      addTearDown(chat.dispose);
      final (service, stream) = _openService();
      chat.setService(service);
      chat.setActiveConversation(chat.conversations.first);

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();
      expect(_shownImages(tester), [base64Decode(_redPng)]);

      // The user message and the assistant placeholder arrive in one frame.
      chat.addPendingImage(_bluePng);
      unawaited(chat.sendMessage('two'));
      await tester.pump();

      final shown = _shownImages(tester);
      expect(shown, hasLength(2));
      expect(shown, containsAll([base64Decode(_redPng), base64Decode(_bluePng)]));

      await stream.close();
      await tester.pumpAndSettle();
    });

    testWidgets('an expanded Thinking section survives the end of streaming',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        Conversation(id: 'c', model: 'llama3'),
      ]);
      addTearDown(chat.dispose);
      final (service, stream) = _openService();
      chat.setService(service);
      chat.setActiveConversation(chat.conversations.first);

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      unawaited(chat.sendMessage('why?'));
      await tester.pump();
      stream
        ..add(const ChatStreamEvent(thinkingToken: 'pondering deeply'))
        ..add(const ChatStreamEvent(contentToken: 'because'));
      await tester.pump();

      await tester.tap(find.text('Thinking'));
      await tester.pump();
      expect(find.text('pondering deeply'), findsOneWidget);

      // Swipe is off while streaming, but the wrapper type must not change
      // when it ends or the section would be remounted (collapsed).
      expect(
          tester.widget<Dismissible>(find.byType(Dismissible)).direction,
          DismissDirection.none);
      stream.add(const ChatStreamEvent(done: true));
      await stream.close();
      await tester.pumpAndSettle();

      expect(
          tester.widget<Dismissible>(find.byType(Dismissible)).direction,
          DismissDirection.endToStart);
      expect(find.text('pondering deeply'), findsOneWidget);
    });

    testWidgets('a tool-call-only assistant message leaves no "…" bubble',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        Conversation(id: 'c', model: 'llama3', messages: [
          ChatMessage(role: 'user', content: 'weather?'),
          ChatMessage(role: 'assistant', content: '', toolCalls: [
            {
              'function': {
                'name': 'web_search',
                'arguments': {'query': 'weather'},
              },
            },
          ]),
          ChatMessage(role: 'tool', content: 'sunny'),
          ChatMessage(role: 'assistant', content: 'It is sunny.'),
        ]),
      ]);
      addTearDown(chat.dispose);
      chat.setActiveConversation(chat.conversations.first);

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      final roles = tester
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .map((b) => b.message.role)
          .toList();
      expect(roles, unorderedEquals(['user', 'assistant']));
      expect(find.text('...'), findsNothing);
      expect(find.textContaining('It is sunny.', findRichText: true),
          findsOneWidget);
    });

    testWidgets('the newest tool-call-only message stays as the indicator',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        Conversation(id: 'c', model: 'llama3', messages: [
          ChatMessage(role: 'user', content: 'weather?'),
        ]),
      ]);
      addTearDown(chat.dispose);
      chat.setActiveConversation(chat.conversations.first);
      // Added after construction: the provider drops a trailing empty
      // assistant message it finds in stored history.
      chat.activeConversation!.messages.add(
        ChatMessage(role: 'assistant', content: '', toolCalls: [
          {
            'function': {'name': 'web_search', 'arguments': {}},
          },
        ]),
      );

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      expect(find.byType(MessageBubble), findsNWidgets(2));
    });

    testWidgets('an empty last response offers retry', (tester) async {
      final chat = ChatProvider(initialConversations: [
        Conversation(id: 'c', model: 'llama3', messages: [
          ChatMessage(role: 'user', content: 'hello?'),
        ]),
      ]);
      addTearDown(chat.dispose);
      chat.setActiveConversation(chat.conversations.first);
      chat.activeConversation!.messages
          .add(ChatMessage(role: 'assistant', content: ''));

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      // the user bubble's copy only: an empty response has nothing to copy
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(
          tester.widget<Dismissible>(find.byType(Dismissible)).direction,
          DismissDirection.endToStart);
    });

    testWidgets('an error bubble keeps its own retry only', (tester) async {
      final chat = ChatProvider(initialConversations: [
        Conversation(id: 'c', model: 'llama3', messages: [
          ChatMessage(role: 'user', content: 'hello?'),
          ChatMessage(role: 'assistant', content: 'boom', isError: true),
        ]),
      ]);
      addTearDown(chat.dispose);
      chat.setActiveConversation(chat.conversations.first);

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(
          tester.widget<Dismissible>(find.byType(Dismissible)).direction,
          DismissDirection.none);
    });
  });

  group('scroll state per conversation', () {
    testWidgets('a conversation opens at the bottom, not at the old offset',
        (tester) async {
      final chat = ChatProvider(
          initialConversations: [_longChat('a'), _longChat('b')]);
      addTearDown(chat.dispose);
      chat.setActiveConversation(chat.conversations.first);

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, 700));
        await tester.pumpAndSettle();
      }
      expect(_listPosition(tester).pixels, greaterThan(400));
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      chat.setActiveConversation(chat.conversations.last);
      await tester.pumpAndSettle();

      expect(_listPosition(tester).pixels, 0);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });

    testWidgets('the jump pill does not leak through an empty chat',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        _longChat('a'),
        Conversation(id: 'empty', model: 'llama3'),
        _longChat('c'),
      ]);
      addTearDown(chat.dispose);
      chat.setActiveConversation(chat.conversations.first);

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, 700));
        await tester.pumpAndSettle();
      }
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      chat.setActiveConversation(chat.conversations[1]); // empty chat
      await tester.pumpAndSettle();
      chat.setActiveConversation(chat.conversations[2]); // chat C
      await tester.pumpAndSettle();

      expect(_listPosition(tester).pixels, 0);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });
  });

  group('new chat', () {
    testWidgets('with no installed model nothing is created and it says why',
        (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);

      await tester.pumpWidget(_wrap(chat));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();

      expect(chat.conversations, isEmpty);
      expect(find.textContaining('Manage models'), findsOneWidget);
    });

    testWidgets('an empty active chat is kept, not duplicated',
        (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      final models = await _modelsWith(tester, ['llama3']);
      chat.createConversation('llama3');

      await tester.pumpWidget(_wrap(chat, models: models));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New chat'));
      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();

      expect(chat.conversations, hasLength(1));
    });

    testWidgets('creates a chat on the selected model once one has content',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        Conversation(id: 'old', model: 'phi3', messages: [
          ChatMessage(role: 'user', content: 'hi'),
        ]),
      ]);
      addTearDown(chat.dispose);
      chat.setActiveConversation(chat.conversations.first);
      final models = await _modelsWith(tester, ['llama3']);

      await tester.pumpWidget(_wrap(chat, models: models));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();

      expect(chat.conversations, hasLength(2));
      expect(chat.activeConversation!.model, 'llama3');
    });

    testWidgets('the no-conversation empty state has a New chat button',
        (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      final models = await _modelsWith(tester, ['llama3']);

      await tester.pumpWidget(_wrap(chat, models: models));
      await tester.pumpAndSettle();
      expect(chat.activeConversation, isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'New chat'));
      await tester.pumpAndSettle();

      expect(chat.conversations, hasLength(1));
      expect(chat.activeConversation!.model, 'llama3');
      // now there is an input to type in, and the button is gone
      expect(find.widgetWithText(FilledButton, 'New chat'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
