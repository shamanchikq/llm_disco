import 'package:flutter_test/flutter_test.dart';

import 'package:llm_disco_test1/main.dart';
import 'package:llm_disco_test1/services/storage_service.dart';

void main() {
  testWidgets('App shows connection screen', (WidgetTester tester) async {
    await tester.pumpWidget(LLMChatApp(
      storageService: StorageService(),
      savedConversations: [],
    ));

    expect(find.text('Connect to Ollama'), findsOneWidget);
  });
}
