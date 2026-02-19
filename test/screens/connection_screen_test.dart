import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:llm_disco_test1/screens/connection_screen.dart';
import 'package:llm_disco_test1/providers/connection_provider.dart';
import 'package:llm_disco_test1/providers/chat_provider.dart';
import 'package:llm_disco_test1/providers/model_provider.dart';
import 'package:llm_disco_test1/services/storage_service.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';
import '../helpers/mocks.dart';

void main() {
  late MockStorageService mockStorage;
  late ChatProvider chatProvider;

  setUp(() {
    mockStorage = MockStorageService();
    when(() => mockStorage.loadConnectionSettings())
        .thenAnswer((_) async => null);
    when(() => mockStorage.loadSavedConnections())
        .thenAnswer((_) async => <Map<String, dynamic>>[]);
  });

  Widget buildScreen() {
    chatProvider = ChatProvider();
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: mockStorage),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => chatProvider),
        ChangeNotifierProvider(create: (_) => ModelProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const ConnectionScreen(),
      ),
    );
  }

  group('ConnectionScreen', () {
    testWidgets('shows all expected fields and buttons', (tester) async {
      // verify the ui renders the basics
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Connect to Ollama'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Save Connection'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'IP Address'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Port'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'SearXNG URL (optional)'), findsOneWidget);
      expect(find.text('Use HTTP (instead of HTTPS)'), findsOneWidget);

      // port should default to 11434
      final portField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Port'),
      );
      expect(portField.controller!.text, '11434');
    });

    testWidgets('empty IP shows validation error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.text('Please enter an IP address'), findsOneWidget);
    });
  });
}
