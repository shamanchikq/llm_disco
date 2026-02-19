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

      expect(find.text('Assistant'), findsOneWidget);
      expect(
        find.textContaining('Hi there', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('error message shows retry button', (tester) async {
      bool retried = false;
      final msg = ChatMessage(
        role: 'assistant',
        content: '[Error: Connection failed]',
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
  });
}
