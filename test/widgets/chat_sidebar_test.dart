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

void main() {
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
}
