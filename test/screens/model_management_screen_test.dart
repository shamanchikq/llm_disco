import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:llm_disco_test1/models/ollama_search_result.dart';
import 'package:llm_disco_test1/providers/connection_provider.dart';
import 'package:llm_disco_test1/providers/model_provider.dart';
import 'package:llm_disco_test1/screens/model_management_screen.dart';
import 'package:llm_disco_test1/theme/app_theme.dart';
import '../helpers/mocks.dart';

void main() {
  late MockOllamaService service;
  late ConnectionProvider connection;
  late ModelProvider models;

  // What the mocked server currently reports as installed.
  var installed = <String>[];

  setUp(() {
    service = MockOllamaService();
    installed = [];
    when(() => service.testConnectionStatus()).thenAnswer((_) async => 200);
    when(() => service.fetchModels()).thenAnswer((_) async => installed);
    when(() => service.fetchModelInfo(any()))
        .thenAnswer((_) async => <String, dynamic>{'capabilities': []});
    connection = ConnectionProvider(serviceFactory: (_, {authHeader}) => service);
    models = ModelProvider();
  });

  /// Connects, loads [installed] into the provider and shows the screen.
  Future<void> pumpScreen(WidgetTester tester) async {
    await connection.connect(ip: '10.0.0.5', port: '11434', useHttp: true);
    await models.fetchModels(service);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectionProvider>.value(value: connection),
        ChangeNotifierProvider<ModelProvider>.value(value: models),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const ModelManagementScreen(),
      ),
    ));
    await tester.pump();
  }

  Future<void> openDiscover(WidgetTester tester) async {
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
  }

  OllamaSearchResult result(String name) =>
      OllamaSearchResult(name: name, description: 'About $name');

  group('Installed tab', () {
    testWidgets('shows a load error as a banner over the kept list',
        (tester) async {
      installed = ['alpha', 'beta'];
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);

      when(() => service.fetchModels()).thenThrow(Exception('timed out'));
      await models.fetchModels(service);
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load models'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // One transient failure doesn't make the list disappear.
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('No models installed'), findsNothing);
    });

    testWidgets('Retry reloads the list and clears the banner',
        (tester) async {
      installed = ['alpha'];
      await pumpScreen(tester);
      when(() => service.fetchModels()).thenThrow(Exception('timed out'));
      await models.fetchModels(service);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      installed = ['alpha', 'beta'];
      when(() => service.fetchModels()).thenAnswer((_) async => installed);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load models'), findsNothing);
      expect(find.text('beta'), findsOneWidget);
    });

    testWidgets('shows the banner instead of "No models installed" when the '
        'first load failed', (tester) async {
      when(() => service.fetchModels()).thenThrow(Exception('refused'));
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load models'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No models installed'), findsNothing);
    });

    testWidgets('pull-to-refresh works when the list does not overflow',
        (tester) async {
      installed = ['alpha'];
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      clearInteractions(service);

      await tester.fling(find.text('alpha'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      verify(() => service.fetchModels()).called(1);
    });

    testWidgets('pull-to-refresh works from the empty state', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      expect(find.text('No models installed'), findsOneWidget);
      clearInteractions(service);

      installed = ['fresh'];
      await tester.fling(
          find.text('No models installed'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      verify(() => service.fetchModels()).called(1);
      expect(find.text('fresh'), findsOneWidget);
    });

    testWidgets('a model whose capabilities failed shows a static retry '
        'state, not a spinner', (tester) async {
      installed = ['alpha'];
      when(() => service.fetchModelInfo('alpha'))
          .thenThrow(Exception('show failed'));
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining("couldn't load capabilities"), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // The screen doesn't hammer a model that just failed.
      verify(() => service.fetchModelInfo('alpha')).called(1);

      when(() => service.fetchModelInfo('alpha')).thenAnswer(
          (_) async => <String, dynamic>{
                'capabilities': ['vision'],
              });
      await tester.tap(find.textContaining("couldn't load capabilities"));
      await tester.pumpAndSettle();

      verify(() => service.fetchModelInfo('alpha')).called(1);
      expect(find.textContaining("couldn't load capabilities"), findsNothing);
      expect(find.byTooltip('Vision'), findsOneWidget);
    });

    testWidgets('pull-to-refresh retries failed capability loads',
        (tester) async {
      installed = ['alpha'];
      when(() => service.fetchModelInfo('alpha'))
          .thenThrow(Exception('show failed'));
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining("couldn't load capabilities"), findsOneWidget);

      // Well inside the 30 s cooldown — a manual refresh bypasses it.
      when(() => service.fetchModelInfo('alpha')).thenAnswer(
          (_) async => <String, dynamic>{
                'capabilities': ['tools'],
              });
      await tester.fling(find.text('alpha'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(find.textContaining("couldn't load capabilities"), findsNothing);
      expect(find.byTooltip('Tools'), findsOneWidget);
    });

    testWidgets('a model that appears while the screen is open gets its '
        'capabilities fetched', (tester) async {
      installed = ['alpha'];
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // e.g. a pull finishing in the Discover tab, then the list refetch.
      final pending = Completer<Map<String, dynamic>>();
      when(() => service.fetchModelInfo('beta'))
          .thenAnswer((_) => pending.future);
      installed = ['alpha', 'beta'];
      await models.fetchModels(service);
      await tester.pump();
      await tester.pump();

      verify(() => service.fetchModelInfo('beta')).called(1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete(<String, dynamic>{
        'capabilities': ['thinking'],
      });
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Thinking'), findsOneWidget);
    });
  });

  group('Discover search', () {
    testWidgets('leaving the screen mid-search does not throw',
        (tester) async {
      final pending = Completer<List<OllamaSearchResult>>();
      when(() => service.searchOllamaCom(any()))
          .thenAnswer((_) => pending.future);
      await pumpScreen(tester);
      await openDiscover(tester);

      await search(tester, 'llama');
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete([result('llama3')]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a search that fails after leaving does not throw either',
        (tester) async {
      final pending = Completer<List<OllamaSearchResult>>();
      when(() => service.searchOllamaCom(any()))
          .thenAnswer((_) => pending.future);
      await pumpScreen(tester);
      await openDiscover(tester);

      await search(tester, 'llama');
      await tester.pumpWidget(const SizedBox.shrink());
      pending.completeError(Exception('offline'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('the latest search wins when responses arrive out of order',
        (tester) async {
      final first = Completer<List<OllamaSearchResult>>();
      final second = Completer<List<OllamaSearchResult>>();
      when(() => service.searchOllamaCom('first'))
          .thenAnswer((_) => first.future);
      when(() => service.searchOllamaCom('second'))
          .thenAnswer((_) => second.future);
      await pumpScreen(tester);
      await openDiscover(tester);

      await search(tester, 'first');
      await search(tester, 'second');

      // The older request lands first: ignored, spinner stays for 'second'.
      first.complete([result('from-first')]);
      await tester.pump();
      expect(find.text('from-first'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      second.complete([result('from-second')]);
      await tester.pump();
      expect(find.text('from-second'), findsOneWidget);
      expect(find.text('from-first'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('an older response arriving last does not replace newer '
        'results', (tester) async {
      final first = Completer<List<OllamaSearchResult>>();
      final second = Completer<List<OllamaSearchResult>>();
      when(() => service.searchOllamaCom('first'))
          .thenAnswer((_) => first.future);
      when(() => service.searchOllamaCom('second'))
          .thenAnswer((_) => second.future);
      await pumpScreen(tester);
      await openDiscover(tester);

      await search(tester, 'first');
      await search(tester, 'second');
      second.complete([result('from-second')]);
      await tester.pump();
      first.complete([result('from-first')]);
      await tester.pump();

      expect(find.text('from-second'), findsOneWidget);
      expect(find.text('from-first'), findsNothing);
    });

    testWidgets('a search with no results says so', (tester) async {
      when(() => service.searchOllamaCom(any()))
          .thenAnswer((_) async => <OllamaSearchResult>[]);
      await pumpScreen(tester);
      await openDiscover(tester);
      expect(find.text('Search for models on ollama.com'), findsOneWidget);

      await search(tester, 'zzzz');
      await tester.pump();

      expect(find.text('No models found for "zzzz"'), findsOneWidget);
      expect(find.text('Search for models on ollama.com'), findsNothing);
    });

    testWidgets('a failed search shows its error, not "no models found"',
        (tester) async {
      when(() => service.searchOllamaCom(any()))
          .thenThrow(Exception('offline'));
      await pumpScreen(tester);
      await openDiscover(tester);

      await search(tester, 'llama');
      await tester.pump();

      expect(find.textContaining('offline'), findsOneWidget);
      expect(find.textContaining('No models found'), findsNothing);
    });
  });

  group('Discover version tags', () {
    // Two searches that put a different model at the same card index (2).
    Future<void> searchTwice(
      WidgetTester tester, {
      required Completer<List<ModelTag>> slowX,
      required Completer<List<ModelTag>> slowY,
    }) async {
      when(() => service.searchOllamaCom('a')).thenAnswer((_) async =>
          [result('a0'), result('a1'), result('model-x')]);
      when(() => service.searchOllamaCom('b')).thenAnswer((_) async =>
          [result('b0'), result('b1'), result('model-y')]);
      when(() => service.fetchCuratedModelTags('model-x'))
          .thenAnswer((_) => slowX.future);
      when(() => service.fetchCuratedModelTags('model-y'))
          .thenAnswer((_) => slowY.future);
      await pumpScreen(tester);
      await openDiscover(tester);

      await search(tester, 'a');
      await tester.pump();
      await tester.tap(find.text('Versions').at(2)); // model-x
      await tester.pump();

      await search(tester, 'b');
      await tester.pump();
      await tester.tap(find.text('Versions').at(2)); // model-y
      await tester.pump();
    }

    testWidgets("a late response for the previous search's model is dropped",
        (tester) async {
      final x = Completer<List<ModelTag>>();
      final y = Completer<List<ModelTag>>();
      await searchTwice(tester, slowX: x, slowY: y);

      y.complete([const ModelTag(name: 'y-tag')]);
      await tester.pump();
      x.complete([const ModelTag(name: 'x-tag')]); // arrives last
      await tester.pump();

      expect(find.text('y-tag'), findsOneWidget);
      expect(find.text('x-tag'), findsNothing);
    });

    testWidgets("an early response for the previous search's model does not "
        'end the loading state', (tester) async {
      final x = Completer<List<ModelTag>>();
      final y = Completer<List<ModelTag>>();
      await searchTwice(tester, slowX: x, slowY: y);

      x.complete([const ModelTag(name: 'x-tag')]);
      await tester.pump();

      expect(find.text('x-tag'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      y.complete([const ModelTag(name: 'y-tag')]);
      await tester.pump();
      expect(find.text('y-tag'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets("a late error for the previous search's model is dropped",
        (tester) async {
      final x = Completer<List<ModelTag>>();
      final y = Completer<List<ModelTag>>();
      await searchTwice(tester, slowX: x, slowY: y);

      y.complete([const ModelTag(name: 'y-tag')]);
      await tester.pump();
      x.completeError(Exception('x failed'));
      await tester.pump();

      expect(find.textContaining('x failed'), findsNothing);
      expect(find.text('y-tag'), findsOneWidget);
    });
  });

  group('modelPageUri', () {
    test('library models live under /library, without the tag', () {
      expect(modelPageUri('gemma3:4b'),
          Uri.parse('https://ollama.com/library/gemma3'));
      expect(modelPageUri('llama3:latest'),
          Uri.parse('https://ollama.com/library/llama3'));
      expect(modelPageUri('llama3'),
          Uri.parse('https://ollama.com/library/llama3'));
    });

    test('community models live directly under ollama.com', () {
      expect(modelPageUri('someuser/cool-model:7b'),
          Uri.parse('https://ollama.com/someuser/cool-model'));
      expect(modelPageUri('someuser/cool-model'),
          Uri.parse('https://ollama.com/someuser/cool-model'));
    });

    test('Hugging Face pulls open the repo on huggingface.co', () {
      expect(modelPageUri('hf.co/bartowski/Llama-3.2-3B-GGUF:Q4_K_M'),
          Uri.parse('https://huggingface.co/bartowski/Llama-3.2-3B-GGUF'));
      expect(modelPageUri('hf.co/org/repo'),
          Uri.parse('https://huggingface.co/org/repo'));
      expect(modelPageUri('huggingface.co/org/repo:Q8_0'),
          Uri.parse('https://huggingface.co/org/repo'));
    });
  });
}
