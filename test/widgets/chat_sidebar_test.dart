import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/models/conversation.dart';
import 'package:llm_disco_test1/providers/chat_provider.dart';
import 'package:llm_disco_test1/providers/connection_provider.dart';
import 'package:llm_disco_test1/providers/model_provider.dart';
import 'package:llm_disco_test1/services/storage_service.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';
import 'package:llm_disco_test1/widgets/chat_sidebar.dart';
import '../helpers/mocks.dart';

Widget wrapSidebar(ChatProvider chat,
    {ModelProvider? models, StorageService? storage}) {
  return MultiProvider(
    providers: [
      Provider<StorageService>.value(value: storage ?? MockStorageService()),
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider(create: (_) => ConnectionProvider()),
      ChangeNotifierProvider.value(value: models ?? ModelProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: ChatSidebar()),
    ),
  );
}

/// The sidebar mounted as a real drawer, so closing it can be observed.
Widget wrapSidebarDrawer(ChatProvider chat, GlobalKey<ScaffoldState> key,
    {ModelProvider? models, StorageService? storage}) {
  return MultiProvider(
    providers: [
      Provider<StorageService>.value(value: storage ?? MockStorageService()),
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider(create: (_) => ConnectionProvider()),
      ChangeNotifierProvider.value(value: models ?? ModelProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        key: key,
        drawer: const ChatSidebar(),
        body: const SizedBox.expand(),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<Conversation>[]);
    registerFallbackValue(Conversation(id: 'fallback', model: 'llama3'));
  });

  group('conversationGroupFor', () {
    // Noon on a Wednesday, local time.
    final now = DateTime(2026, 6, 17, 12);

    test('buckets by calendar day', () {
      expect(conversationGroupFor(DateTime(2026, 6, 17, 0, 1), now), 'Today');
      expect(conversationGroupFor(DateTime(2026, 6, 16, 23, 59), now),
          'Yesterday');
      expect(conversationGroupFor(DateTime(2026, 6, 10, 8), now),
          'Previous 7 days'); // exactly 7 days back
      expect(conversationGroupFor(DateTime(2026, 6, 9, 20), now), 'Older');
    });

    test('a day after a spring-forward change still reads as yesterday', () {
      // Local midnights on either side of a 23-hour day are 23 hours
      // apart; `inDays` on that gives 0. Runs in whatever zone the host has
      // (the bug shows under e.g. TZ=America/New_York).
      final after = DateTime(2026, 3, 9, 12);
      expect(conversationGroupFor(DateTime(2026, 3, 8, 12), after),
          'Yesterday');
      expect(conversationGroupFor(DateTime(2026, 3, 8, 0, 30), after),
          'Yesterday');
      expect(conversationGroupFor(DateTime(2026, 3, 9, 0, 30), after),
          'Today');
      // Eight calendar days back, across the change: must not slip into
      // "Previous 7 days".
      final later = DateTime(2026, 3, 16, 12);
      expect(conversationGroupFor(DateTime(2026, 3, 8, 12), later), 'Older');
      expect(conversationGroupFor(DateTime(2026, 3, 9, 12), later),
          'Previous 7 days');
    });
  });

  testWidgets('search filters conversations by title and message text',
      (tester) async {
    final chat = ChatProvider(initialConversations: [
      Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
      Conversation(
        id: '2',
        model: 'llama3',
        title: 'Code review',
        messages: [ChatMessage(role: 'user', content: 'flutter tips please')],
      ),
    ]);
    addTearDown(chat.dispose);

    await tester.pumpWidget(wrapSidebar(chat));
    await tester.pumpAndSettle();

    expect(find.text('Paris trip'), findsOneWidget);
    expect(find.text('Code review'), findsOneWidget);

    // matches message content, not just titles
    await tester.enterText(find.byType(TextField), 'flutter');
    await tester.pumpAndSettle();

    expect(find.text('Paris trip'), findsNothing);
    expect(find.text('Code review'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'paris');
    await tester.pumpAndSettle();

    expect(find.text('Paris trip'), findsOneWidget);
    expect(find.text('Code review'), findsNothing);
  });

  testWidgets('conversation tile has a visible options button', (tester) async {
    final chat = ChatProvider(initialConversations: [
      Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
    ]);
    addTearDown(chat.dispose);

    await tester.pumpWidget(wrapSidebar(chat));
    await tester.pumpAndSettle();

    // discoverable without long-pressing: ⋯ opens the options sheet
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Export as Markdown'), findsOneWidget);
  });

  testWidgets('swipe-delete offers undo', (tester) async {
    final chat = ChatProvider(initialConversations: [
      Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
    ]);
    addTearDown(chat.dispose);

    await tester.pumpWidget(wrapSidebar(chat));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Paris trip'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(chat.conversations, isEmpty);
    expect(find.text('Chat deleted'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();

    expect(chat.conversations, hasLength(1));
    expect(find.text('Paris trip'), findsOneWidget);
  });

  testWidgets('a second swipe-delete keeps the first one undoable',
      (tester) async {
    final chat = ChatProvider(initialConversations: [
      Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
      Conversation(id: '2', model: 'llama3', title: 'Tax notes'),
    ]);
    addTearDown(chat.dispose);

    await tester.pumpWidget(wrapSidebar(chat));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Paris trip'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Tax notes'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(chat.conversations, isEmpty);
    expect(find.text('2 chats deleted'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();

    expect(chat.conversations.map((c) => c.title),
        ['Paris trip', 'Tax notes']);
    expect(find.text('UNDO'), findsNothing);
  });

  testWidgets('the undo offer survives closing and reopening the drawer',
      (tester) async {
    final chat = ChatProvider(initialConversations: [
      Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
    ]);
    addTearDown(chat.dispose);
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(wrapSidebarDrawer(chat, scaffoldKey));
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.drag(find.text('Paris trip'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Chat deleted'), findsOneWidget);

    // Closing the drawer disposes the sidebar's state entirely.
    scaffoldKey.currentState!.closeDrawer();
    await tester.pumpAndSettle();
    expect(find.byType(ChatSidebar), findsNothing);

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Chat deleted'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(chat.conversations, hasLength(1));
  });

  testWidgets('the undo bar disappears when the window runs out',
      (tester) async {
    final chat = ChatProvider(initialConversations: [
      Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
    ]);
    addTearDown(chat.dispose);

    await tester.pumpWidget(wrapSidebar(chat));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Paris trip'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('UNDO'), findsOneWidget);

    await tester.pump(ChatProvider.undoWindow);
    await tester.pump();

    expect(find.text('UNDO'), findsNothing);
    expect(chat.conversations, isEmpty);
  });

  testWidgets('backup sheet exposes export, import and delete all',
      (tester) async {
    final storage = MockStorageService();
    when(() => storage.deleteAll()).thenAnswer((_) async {});
    when(() => storage.saveConversations(any())).thenAnswer((_) async {});
    final chat = ChatProvider(
      storageService: storage,
      initialConversations: [
        Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
      ],
    );
    addTearDown(chat.dispose);

    await tester.pumpWidget(wrapSidebar(chat, storage: storage));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Backup & restore'));
    await tester.pumpAndSettle();

    expect(find.text('Export all conversations'), findsOneWidget);
    expect(find.text('Import from file'), findsOneWidget);

    // destructive action must be confirmed before anything is wiped
    await tester.tap(find.text('Delete all conversations'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all conversations?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(chat.conversations, hasLength(1));
    verifyNever(() => storage.deleteAll());

    await tester.tap(find.text('Backup & restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all conversations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();

    expect(chat.conversations, isEmpty);
    verify(() => storage.deleteAll()).called(1);
  });

  testWidgets('footer model selector opens a picker sheet', (tester) async {
    final chat = ChatProvider();
    addTearDown(chat.dispose);
    final models = ModelProvider();
    final service = MockOllamaService();
    when(() => service.fetchModels())
        .thenAnswer((_) async => ['llama3', 'phi3']);
    when(() => service.fetchModelInfo(any()))
        .thenAnswer((_) async => <String, dynamic>{'capabilities': []});
    await models.fetchModels(service);

    await tester.pumpWidget(wrapSidebar(chat, models: models));
    await tester.pumpAndSettle();

    await tester.tap(find.text('llama3'));
    await tester.pumpAndSettle();

    // graphite bottom sheet, not the stock dropdown
    expect(find.text('SELECT MODEL'), findsOneWidget);
    await tester.tap(find.text('phi3'));
    await tester.pumpAndSettle();

    expect(models.selectedModel, 'phi3');
  });

  testWidgets('export failure is reported once the drawer is closed',
      (tester) async {
    final storage = MockStorageService();
    when(() => storage.exportAllConversations(any()))
        .thenAnswer((_) async => throw Exception('disk full'));
    final chat = ChatProvider(initialConversations: [
      Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
    ]);
    addTearDown(chat.dispose);
    final key = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(wrapSidebarDrawer(chat, key, storage: storage));
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(key.currentState!.isDrawerOpen, isTrue);

    await tester.tap(find.text('Backup & restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export all conversations'));
    await tester.pumpAndSettle();

    // The drawer paints above snackbars, so it has to be gone for this to
    // be seen at all.
    expect(key.currentState!.isDrawerOpen, isFalse);
    expect(find.textContaining('Export failed'), findsOneWidget);
    expect(find.text('Paris trip'), findsNothing);
  });

  testWidgets('a failed single-chat export is reported with the drawer closed',
      (tester) async {
    final storage = MockStorageService();
    when(() => storage.exportConversation(any()))
        .thenAnswer((_) async => throw Exception('no space'));
    final chat = ChatProvider(initialConversations: [
      Conversation(id: '1', model: 'llama3', title: 'Paris trip'),
    ]);
    addTearDown(chat.dispose);
    final key = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(wrapSidebarDrawer(chat, key, storage: storage));
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export as JSON'));
    await tester.pumpAndSettle();

    expect(key.currentState!.isDrawerOpen, isFalse);
    expect(find.textContaining('Export failed'), findsOneWidget);
  });

  group('new chat button', () {
    testWidgets('with no installed model creates nothing and says why',
        (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      final key = GlobalKey<ScaffoldState>();

      await tester.pumpWidget(wrapSidebarDrawer(chat, key));
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.text('New chat'));
      await tester.pumpAndSettle();

      expect(chat.conversations, isEmpty);
      expect(key.currentState!.isDrawerOpen, isFalse);
      expect(find.textContaining('Manage models'), findsOneWidget);
    });

    testWidgets('reuses an empty active chat instead of piling up',
        (tester) async {
      final chat = ChatProvider();
      addTearDown(chat.dispose);
      final models = await _modelsWith(['llama3']);
      final key = GlobalKey<ScaffoldState>();
      chat.createConversation('llama3');

      await tester.pumpWidget(wrapSidebarDrawer(chat, key, models: models));
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.text('New chat'));
      await tester.pumpAndSettle();

      expect(chat.conversations, hasLength(1));

      // Once the chat has content, the button does create a new one.
      chat.activeConversation!.messages
          .add(ChatMessage(role: 'user', content: 'hi'));
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('New chat'));
      await tester.pumpAndSettle();

      expect(chat.conversations, hasLength(2));
      expect(chat.activeConversation!.model, 'llama3');
    });
  });

  group('ordered by last activity', () {
    final now = DateTime.now();
    final longAgo = DateTime(now.year, now.month, now.day - 40, 9);
    final threeDaysAgo = DateTime(now.year, now.month, now.day - 3, 9);
    // Fixed times on today's date: the sidebar groups by calendar day, so
    // these stay "Today" whenever the test runs.
    final todayEarly = DateTime(now.year, now.month, now.day, 0, 0, 10);
    final todayLater = DateTime(now.year, now.month, now.day, 0, 0, 20);

    Conversation chatAt(String id, DateTime created, [DateTime? lastMessage]) =>
        Conversation(
          id: id,
          model: 'llama3',
          title: 'Chat $id',
          createdAt: created,
          messages: [
            if (lastMessage != null)
              ChatMessage(
                  role: 'user', content: 'note $id', timestamp: lastMessage),
          ],
        );

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    test('conversationLastActivity is the newest message, else creation', () {
      expect(conversationLastActivity(chatAt('a', longAgo)), longAgo);
      expect(
          conversationLastActivity(chatAt('a', longAgo, todayEarly)), todayEarly);
    });

    testWidgets('an old chat written to today is listed under Today, above a '
        'newer chat that went quiet', (tester) async {
      final chat = ChatProvider(initialConversations: [
        chatAt('quiet', threeDaysAgo), // newer, but untouched since
        chatAt('old', longAgo, todayEarly), // created long ago, used today
      ]);
      addTearDown(chat.dispose);

      await tester.pumpWidget(wrapSidebar(chat));
      await tester.pumpAndSettle();

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('PREVIOUS 7 DAYS'), findsOneWidget);
      expect(find.text('OLDER'), findsNothing);
      expect(top(tester, 'TODAY'), lessThan(top(tester, 'Chat old')));
      expect(top(tester, 'Chat old'),
          lessThan(top(tester, 'PREVIOUS 7 DAYS')));
      expect(top(tester, 'PREVIOUS 7 DAYS'),
          lessThan(top(tester, 'Chat quiet')));
      // Display order only: the provider's list is untouched.
      expect(chat.conversations.map((c) => c.id), ['quiet', 'old']);
    });

    testWidgets('within a group the most recently used chat comes first',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        chatAt('first', todayEarly),
        chatAt('second', todayEarly, todayLater),
        chatAt('third', longAgo, todayLater.add(const Duration(seconds: 5))),
      ]);
      addTearDown(chat.dispose);

      await tester.pumpWidget(wrapSidebar(chat));
      await tester.pumpAndSettle();

      expect(top(tester, 'Chat third'), lessThan(top(tester, 'Chat second')));
      expect(top(tester, 'Chat second'), lessThan(top(tester, 'Chat first')));
    });

    testWidgets('chats with the same activity keep the provider order',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        chatAt('x', todayEarly),
        chatAt('y', todayEarly),
        chatAt('z', todayEarly),
      ]);
      addTearDown(chat.dispose);

      await tester.pumpWidget(wrapSidebar(chat));
      await tester.pumpAndSettle();

      expect(top(tester, 'Chat x'), lessThan(top(tester, 'Chat y')));
      expect(top(tester, 'Chat y'), lessThan(top(tester, 'Chat z')));
    });

    testWidgets('search results keep the same order', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final chat = ChatProvider(initialConversations: [
        chatAt('a', todayEarly),
        chatAt('b', longAgo, todayLater),
        chatAt('c', longAgo),
      ]);
      addTearDown(chat.dispose);

      await tester.pumpWidget(wrapSidebar(chat));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'chat');
      await tester.pumpAndSettle();

      expect(top(tester, 'Chat b'), lessThan(top(tester, 'Chat a')));
      expect(top(tester, 'Chat a'), lessThan(top(tester, 'Chat c')));
    });

    testWidgets('a new message moves its chat up while the drawer is open',
        (tester) async {
      final chat = ChatProvider(initialConversations: [
        chatAt('busy', todayLater),
        chatAt('idle', longAgo),
      ]);
      addTearDown(chat.dispose);

      await tester.pumpWidget(wrapSidebar(chat));
      await tester.pumpAndSettle();
      expect(find.text('OLDER'), findsOneWidget);
      expect(top(tester, 'Chat busy'), lessThan(top(tester, 'Chat idle')));

      chat.conversations.last.messages.add(ChatMessage(
        role: 'user',
        content: 'back again',
        timestamp: todayLater.add(const Duration(minutes: 1)),
      ));
      chat.conversationSettingsChanged();
      await tester.pumpAndSettle();

      expect(find.text('OLDER'), findsNothing);
      expect(top(tester, 'Chat idle'), lessThan(top(tester, 'Chat busy')));
    });
  });

  group('accessibility', () {
    void testSemantics(
        String description, Future<void> Function(WidgetTester) body) {
      testWidgets(description, (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await body(tester);
        } finally {
          semantics.dispose();
        }
      });
    }

    Size touchSize(WidgetTester tester, Finder finder) =>
        tester.getSemantics(finder).rect.size;

    Future<ChatProvider> openSidebar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final chat = ChatProvider(initialConversations: [
        Conversation(id: '1', model: 'llama3', title: 'Paris trip', messages: [
          ChatMessage(role: 'user', content: 'hello'),
        ]),
        Conversation(id: '2', model: 'llama3', title: 'Tax notes'),
        Conversation(
          id: '3',
          model: 'llama3',
          title: 'Old thing',
          createdAt: DateTime.now().subtract(const Duration(days: 60)),
        ),
      ]);
      addTearDown(chat.dispose);
      final models = await _modelsWith(['llama3', 'phi3']);
      final key = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(wrapSidebarDrawer(chat, key, models: models));
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();
      return chat;
    }

    testSemantics('every control is labeled and a 48 dp target', (tester) async {
      await openSidebar(tester);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testSemantics('with a search typed and an undo offer showing',
        (tester) async {
      final chat = await openSidebar(tester);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      final clear = find.byTooltip('Clear search');
      expect(touchSize(tester, clear), const Size(48, 48));

      await tester.drag(find.text('Tax notes'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(chat.undoableDeletes, 1);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(find.text('Old thing'), findsOneWidget);

      await tester.pump(ChatProvider.undoWindow);
    });

    testSemantics('options, new chat and footer rows are labeled 48 dp '
        'targets', (tester) async {
      await openSidebar(tester);

      final options = find.byTooltip('Chat options');
      expect(options, findsNWidgets(3));
      for (final button in options.evaluate()) {
        expect(touchSize(tester, find.byWidget(button.widget)),
            const Size(48, 48));
      }
      for (final text in [
        'New chat',
        'Manage models',
        'Backup & restore',
        'Switch server',
      ]) {
        final size = touchSize(tester, find.text(text));
        expect(size.height, greaterThanOrEqualTo(48), reason: text);
        expect(size.width, greaterThanOrEqualTo(48), reason: text);
      }
      // the footer model selector is a button too
      final selector = tester.getSemantics(find.text('llama3').last);
      final data = selector.getSemanticsData();
      expect(data.label, 'llama3');
      expect(data.hint, 'Select model');
      expect(data.flagsCollection.isButton, isTrue);
      expect(selector.rect.height, greaterThanOrEqualTo(48));
    });

    testSemantics('the options button still opens the options sheet',
        (tester) async {
      await openSidebar(tester);

      await tester.tap(find.byTooltip('Chat options').first);
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
    });
  });
}

Future<ModelProvider> _modelsWith(List<String> names) async {
  final models = ModelProvider();
  final service = MockOllamaService();
  when(() => service.fetchModels()).thenAnswer((_) async => names);
  when(() => service.fetchModelInfo(any()))
      .thenAnswer((_) async => <String, dynamic>{'capabilities': []});
  await models.fetchModels(service);
  return models;
}
