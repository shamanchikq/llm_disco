import 'dart:async';

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

  Widget buildScreen({bool autoConnect = true, ConnectionProvider? connection}) {
    chatProvider = ChatProvider();
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: mockStorage),
        ChangeNotifierProvider(
            create: (_) => connection ?? ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => chatProvider),
        ChangeNotifierProvider(create: (_) => ModelProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ConnectionScreen(autoConnect: autoConnect),
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

    testWidgets('auto-connects with saved settings on launch', (tester) async {
      when(() => mockStorage.loadConnectionSettings()).thenAnswer((_) async =>
          {'ip': '10.0.0.5', 'port': '11434', 'useHttp': true});

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // The widget-test HTTP client answers every request with 400, so a
      // triggered auto-connect surfaces as a connection error on screen.
      expect(find.textContaining('HTTP 400'), findsWidgets);
    });

    testWidgets('autoConnect: false only prefills the saved settings',
        (tester) async {
      when(() => mockStorage.loadConnectionSettings()).thenAnswer((_) async =>
          {'ip': '10.0.0.5', 'port': '11434', 'useHttp': true});

      await tester.pumpWidget(buildScreen(autoConnect: false));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach'), findsNothing);
      expect(find.widgetWithText(TextField, '10.0.0.5'), findsOneWidget);
    });

    testWidgets('empty IP shows validation error', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.text('Please enter an IP address'), findsOneWidget);
    });
  });

  group('ConnectionScreen connect flow', () {
    late MockOllamaService mockService;
    late Completer<int> probe;
    late List<String> builtUrls;

    // Connection provider whose probe stays pending until [probe] completes,
    // so tests can act while the connect is in flight. The completer is made
    // here, inside the test body: one created in setUp lives in a different
    // zone and its completion would never be flushed by tester.pump().
    ConnectionProvider pendingConnection() {
      probe = Completer<int>();
      builtUrls = [];
      return ConnectionProvider(serviceFactory: (url, {authHeader}) {
        builtUrls.add(url);
        return mockService;
      });
    }

    Future<void> fill(
      WidgetTester tester, {
      String ip = '10.0.0.5',
      String? searxng,
      String? token,
    }) async {
      await tester.enterText(find.widgetWithText(TextField, 'IP Address'), ip);
      if (searxng != null) {
        await tester.enterText(
            find.widgetWithText(TextField, 'SearXNG URL (optional)'), searxng);
      }
      if (token != null) {
        await tester.enterText(
            find.widgetWithText(TextField, 'API key / Bearer token (optional)'),
            token);
      }
    }

    setUp(() {
      mockService = MockOllamaService();
      when(() => mockService.testConnectionStatus())
          .thenAnswer((_) => probe.future);
      when(() => mockService.fetchModels()).thenAnswer((_) async => <String>[]);
      when(() => mockStorage.saveConnectionSettings(
            ip: any(named: 'ip'),
            port: any(named: 'port'),
            useHttp: any(named: 'useHttp'),
            searxngUrl: any(named: 'searxngUrl'),
            authToken: any(named: 'authToken'),
          )).thenAnswer((_) async {});
    });

    testWidgets('an invalid SearXNG URL blocks the connect', (tester) async {
      final connection = pendingConnection();
      await tester.pumpWidget(
          buildScreen(autoConnect: false, connection: connection));
      await tester.pumpAndSettle();

      await fill(tester, searxng: 'ftp://searx.local');
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.textContaining('valid SearXNG URL'), findsOneWidget);
      expect(builtUrls, isEmpty, reason: 'must not start connecting');
      expect(connection.isConnecting, isFalse);
      verifyNever(() => mockStorage.saveConnectionSettings(
            ip: any(named: 'ip'),
            port: any(named: 'port'),
            useHttp: any(named: 'useHttp'),
            searxngUrl: any(named: 'searxngUrl'),
            authToken: any(named: 'authToken'),
          ));
      // The button is usable again for a corrected attempt.
      expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNotNull);
    });

    testWidgets('a scheme-less SearXNG URL is normalised before saving',
        (tester) async {
      final connection = pendingConnection();
      await tester.pumpWidget(
          buildScreen(autoConnect: false, connection: connection));
      await tester.pumpAndSettle();

      await fill(tester, searxng: '192.168.1.5:8080');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      probe.complete(200);
      await tester.pumpAndSettle();

      verify(() => mockStorage.saveConnectionSettings(
            ip: '10.0.0.5',
            port: '11434',
            useHttp: true,
            searxngUrl: 'http://192.168.1.5:8080',
            authToken: null,
          )).called(1);
      expect(chatProvider.searxngUrl, 'http://192.168.1.5:8080');
    });

    testWidgets('edits made while connecting do not change what is saved',
        (tester) async {
      final connection = pendingConnection();
      await tester.pumpWidget(
          buildScreen(autoConnect: false, connection: connection));
      await tester.pumpAndSettle();

      await fill(tester,
          ip: '10.0.0.5', searxng: 'http://searx-a:8080', token: 'token-a');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(builtUrls, ['http://10.0.0.5:11434']);

      // The user fiddles with the form (or taps a profile chip) mid-probe.
      await fill(tester,
          ip: '10.9.9.9', searxng: 'http://searx-b:9090', token: 'token-b');
      await tester.tap(find.byType(Switch));
      await tester.pump();

      probe.complete(200);
      await tester.pumpAndSettle();

      verify(() => mockStorage.saveConnectionSettings(
            ip: '10.0.0.5',
            port: '11434',
            useHttp: true,
            searxngUrl: 'http://searx-a:8080',
            authToken: 'token-a',
          )).called(1);
      expect(chatProvider.searxngUrl, 'http://searx-a:8080');
    });

    testWidgets('the button stays disabled until the whole connect finishes',
        (tester) async {
      final connection = pendingConnection();
      final saving = Completer<void>();
      when(() => mockStorage.saveConnectionSettings(
            ip: any(named: 'ip'),
            port: any(named: 'port'),
            useHttp: any(named: 'useHttp'),
            searxngUrl: any(named: 'searxngUrl'),
            authToken: any(named: 'authToken'),
          )).thenAnswer((_) => saving.future);
      await tester.pumpWidget(
          buildScreen(autoConnect: false, connection: connection));
      await tester.pumpAndSettle();

      await fill(tester);
      await tester.tap(find.text('Connect'));
      await tester.pump();
      probe.complete(200);
      await tester.pump();

      // The probe is done (isConnecting is false again) but the screen is
      // still saving settings — a second tap must not start another connect.
      expect(connection.isConnecting, isFalse);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(builtUrls, hasLength(1));

      saving.complete();
      await tester.pumpAndSettle();
      expect(builtUrls, hasLength(1));
    });

    testWidgets('a failed connect re-enables the button', (tester) async {
      final connection = pendingConnection();
      await tester.pumpWidget(
          buildScreen(autoConnect: false, connection: connection));
      await tester.pumpAndSettle();

      await fill(tester);
      await tester.tap(find.text('Connect'));
      await tester.pump();
      probe.complete(0);
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach'), findsWidgets);
      expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNotNull);
    });

    testWidgets('saving a profile through the name dialog works',
        (tester) async {
      when(() => mockStorage.saveSavedConnections(any()))
          .thenAnswer((_) async {});
      await tester.pumpWidget(buildScreen(autoConnect: false));
      await tester.pumpAndSettle();

      await fill(tester, ip: '10.0.0.5');
      await tester.tap(find.text('Save Connection'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '10.0.0.5').last,
          'Home PC');
      await tester.tap(find.text('Save'));
      // Settling runs the dialog's exit animation, which is when a
      // prematurely disposed controller would blow up.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final saved = verify(() => mockStorage.saveSavedConnections(captureAny()))
          .captured
          .single as List<Map<String, dynamic>>;
      expect(saved.single['name'], 'Home PC');
      expect(find.text('Home PC'), findsOneWidget); // profile chip
    });
  });
}
