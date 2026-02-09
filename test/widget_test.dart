import 'package:flutter_test/flutter_test.dart';

import 'package:llm_disco_test1/main.dart';

void main() {
  testWidgets('App shows connection screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LLMChatApp());

    expect(find.text('Connect to Ollama'), findsOneWidget);
  });
}
