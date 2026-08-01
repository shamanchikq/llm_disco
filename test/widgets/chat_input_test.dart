import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:llm_disco_test1/providers/chat_provider.dart';
import 'package:llm_disco_test1/providers/model_provider.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';
import 'package:llm_disco_test1/widgets/chat_input.dart';

Widget _wrap(ChatProvider chat) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider(create: (_) => ModelProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: ChatInput()),
    ),
  );
}

void main() {
  testWidgets('a draft set while the input is mounted fills the field',
      (tester) async {
    final chat = ChatProvider();
    addTearDown(chat.dispose);
    chat.createConversation('llama3');

    await tester.pumpWidget(_wrap(chat));
    await tester.pumpAndSettle();

    // Empty-state starter chip fires this after the input is already built.
    chat.setDraft('Summarize this: ');
    await tester.pumpAndSettle();

    // Must not throw "markNeedsBuild during build" and must show the draft.
    expect(tester.takeException(), isNull);
    expect(find.text('Summarize this: '), findsOneWidget);
  });
}
