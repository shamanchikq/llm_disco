import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/chat_message.dart';
import 'package:llm_disco_test1/widgets/message_bubble.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

void main() {
  group('MessageBubble', () {
    testWidgets('user message shows content', (tester) async {
      final msg = ChatMessage(role: 'user', content: 'Hello world');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('assistant message shows label and content', (tester) async {
      final msg = ChatMessage(role: 'assistant', content: 'Hi there');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      // Flag header shows the model name (or fallback) in uppercase
      expect(find.text('ASSISTANT'), findsOneWidget);
      expect(
        find.textContaining('Hi there', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('error message shows retry button', (tester) async {
      bool retried = false;
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Connection failed',
        isError: true,
      );

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onRetry: () => retried = true),
      ));
      await tester.pump();

      // verify retry button works
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('thinking section renders and collapses', (tester) async {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'The answer is 42',
        thinking: 'Deep thought process here',
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      // thinking header should be there
      expect(find.text('Thinking'), findsOneWidget);

      // content should be hidden initially
      expect(find.text('Deep thought process here'), findsNothing);

      // tap to expand
      await tester.tap(find.text('Thinking'));
      await tester.pump();
      expect(find.text('Deep thought process here'), findsOneWidget);
    });

    testWidgets('assistant message shows copy button', (tester) async {
      final msg = ChatMessage(role: 'assistant', content: 'Some response');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });

    testWidgets('user message shows visible copy and edit actions',
        (tester) async {
      bool edited = false;
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(
        MessageBubble(message: msg, onEdit: () => edited = true),
      ));
      await tester.pump();

      // discoverable without long-pressing
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(edited, isTrue);
    });

    testWidgets('user message renders every attached image', (tester) async {
      // 1x1 transparent PNG
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
      final msg = ChatMessage(
        role: 'user',
        content: 'two pics',
        images: [png, png],
      );

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('user message without onEdit shows no edit action',
        (tester) async {
      final msg = ChatMessage(role: 'user', content: 'My question');

      await tester.pumpWidget(_wrap(MessageBubble(message: msg)));
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });
}
