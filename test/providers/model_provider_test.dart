import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:llm_disco_test1/providers/model_provider.dart';
import 'package:llm_disco_test1/services/ollama_service.dart';
import '../helpers/mocks.dart';

void main() {
  group('ModelProvider', () {
    late ModelProvider provider;
    late MockOllamaService mockService;

    setUp(() {
      provider = ModelProvider();
      mockService = MockOllamaService();
    });

    test('initial state', () {
      expect(provider.models, isEmpty);
      expect(provider.selectedModel, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('fetchModels success', () async {
      when(() => mockService.fetchModels())
          .thenAnswer((_) async => ['llama3', 'phi3', 'gemma2']);
      when(() => mockService.fetchModelInfo(any()))
          .thenAnswer((_) async => <String, dynamic>{'capabilities': []});

      await provider.fetchModels(mockService);

      // should auto-select the first model
      expect(provider.models, ['llama3', 'phi3', 'gemma2']);
      expect(provider.selectedModel, 'llama3');
      expect(provider.error, isNull);
    });

    test('fetchModels error', () async {
      when(() => mockService.fetchModels())
          .thenThrow(Exception('network error'));

      await provider.fetchModels(mockService);

      expect(provider.models, isEmpty);
      expect(provider.error, contains('Failed to load models'));
    });

    test('selectModel and capabilities', () async {
      // selectModel should update the selected model
      // and fetch capabilities when service is provided
      when(() => mockService.fetchModelInfo('phi3')).thenAnswer(
        (_) async => <String, dynamic>{
          'capabilities': ['vision', 'tools'],
        },
      );

      provider.selectModel('phi3', service: mockService);
      expect(provider.selectedModel, 'phi3');

      await Future<void>.delayed(Duration.zero);

      final caps = provider.getCapabilities('phi3');
      expect(caps, isNotNull);
      expect(caps!.supportsVision, isTrue);
      expect(caps.supportsTools, isTrue);
    });

    test('fetchModels keeps current selection when still installed', () async {
      when(() => mockService.fetchModels())
          .thenAnswer((_) async => ['llama3', 'phi3', 'gemma2']);
      when(() => mockService.fetchModelInfo(any()))
          .thenAnswer((_) async => <String, dynamic>{'capabilities': []});

      await provider.fetchModels(mockService);
      provider.selectModel('phi3');

      // refetch happens after every model pull — must not reset selection
      await provider.fetchModels(mockService);

      expect(provider.selectedModel, 'phi3');
    });

    test('fetchModels falls back to first when selection was removed',
        () async {
      when(() => mockService.fetchModels())
          .thenAnswer((_) async => ['llama3', 'phi3']);
      when(() => mockService.fetchModelInfo(any()))
          .thenAnswer((_) async => <String, dynamic>{'capabilities': []});

      await provider.fetchModels(mockService);
      provider.selectModel('phi3');

      when(() => mockService.fetchModels())
          .thenAnswer((_) async => ['llama3']);
      await provider.fetchModels(mockService);

      expect(provider.selectedModel, 'llama3');
    });

    test('getCapabilities returns null for unknown model', () {
      expect(provider.getCapabilities('unknown'), isNull);
    });

    test('clear resets state', () async {
      when(() => mockService.fetchModels())
          .thenAnswer((_) async => ['llama3']);
      when(() => mockService.fetchModelInfo(any()))
          .thenAnswer((_) async => <String, dynamic>{'capabilities': []});

      await provider.fetchModels(mockService);
      provider.clear();

      expect(provider.models, isEmpty);
      expect(provider.selectedModel, isNull);
      expect(provider.error, isNull);
    });

    test('cancelling a pull does not surface as a failed download',
        () async {
      when(() => mockService.cancelPull()).thenAnswer((_) {});
      final controller = StreamController<PullProgressEvent>();
      when(() => mockService.pullModel('big-model'))
          .thenAnswer((_) => controller.stream);

      final pulling = provider.pullModel(mockService, 'big-model');
      await Future<void>.delayed(Duration.zero);

      // cancelPull closes the real http client, which makes the in-flight
      // stream throw — that must stay invisible to the UI.
      provider.cancelPull(mockService);
      controller.addError(Exception('Client closed'));
      await controller.close();
      await pulling;

      expect(provider.isPulling, isFalse);
      expect(provider.pullError, isNull);
    });

    group('pulling', () {
      test(
        'a completed pull reports completion and refreshes the list',
        () async {
          when(() => mockService.pullModel('phi3')).thenAnswer(
            (_) => Stream.fromIterable(const [
              PullProgressEvent(status: 'pulling manifest'),
              PullProgressEvent(status: 'success'),
            ]),
          );
          when(
            () => mockService.fetchModels(),
          ).thenAnswer((_) async => ['phi3']);
          when(
            () => mockService.fetchModelInfo(any()),
          ).thenAnswer((_) async => <String, dynamic>{'capabilities': []});

          await provider.pullModel(mockService, 'phi3');

          expect(provider.pullStatus, 'Pull complete');
          expect(provider.pullError, isNull);
          expect(provider.isPulling, isFalse);
          expect(provider.models, ['phi3']);
        },
      );

      test(
        'a pull that errors sets pullError and never reports completion',
        () async {
          // The service throws on an in-stream {"error": …} line; the banner
          // for "Model installed" keys off pullStatus == 'Pull complete'.
          Stream<PullProgressEvent> failing() async* {
            yield const PullProgressEvent(status: 'pulling manifest');
            throw Exception(
              'Ollama error: pull model manifest: file does not exist',
            );
          }

          when(
            () => mockService.pullModel('nope'),
          ).thenAnswer((_) => failing());
          final statuses = <String>[];
          provider.addListener(() => statuses.add(provider.pullStatus));

          await provider.pullModel(mockService, 'nope');

          expect(provider.pullError, contains('file does not exist'));
          expect(provider.isPulling, isFalse);
          expect(statuses, isNot(contains('Pull complete')));
          verifyNever(() => mockService.fetchModels());
        },
      );

      test(
        'a stream that closes cleanly after cancel is not "complete"',
        () async {
          when(() => mockService.cancelPull()).thenAnswer((_) {});
          final controller = StreamController<PullProgressEvent>();
          when(
            () => mockService.pullModel('big'),
          ).thenAnswer((_) => controller.stream);

          final pulling = provider.pullModel(mockService, 'big');
          await Future<void>.delayed(Duration.zero);
          provider.cancelPull(mockService);
          await controller.close();
          await pulling;

          expect(provider.pullStatus, isNot('Pull complete'));
          expect(provider.pullError, isNull);
          verifyNever(() => mockService.fetchModels());
        },
      );

      test('starting a pull while one is running is a no-op', () async {
        final controller = StreamController<PullProgressEvent>();
        when(
          () => mockService.pullModel(any()),
        ).thenAnswer((_) => controller.stream);
        when(() => mockService.fetchModels()).thenAnswer((_) async => []);

        final first = provider.pullModel(mockService, 'a');
        await Future<void>.delayed(Duration.zero);
        await provider.pullModel(mockService, 'b');

        verify(() => mockService.pullModel('a')).called(1);
        verifyNever(() => mockService.pullModel('b'));
        expect(provider.pullingModelName, 'a');

        controller.add(const PullProgressEvent(status: 'success'));
        await controller.close();
        await first;
      });
    });

    group('clear() while work is in flight', () {
      test('aborts the running pull and ignores its late completion', () async {
        when(() => mockService.cancelPull()).thenAnswer((_) {});
        when(() => mockService.fetchModels()).thenAnswer((_) async => ['x']);
        final controller = StreamController<PullProgressEvent>();
        when(
          () => mockService.pullModel('big'),
        ).thenAnswer((_) => controller.stream);

        final pulling = provider.pullModel(mockService, 'big');
        await Future<void>.delayed(Duration.zero);
        expect(provider.isPulling, isTrue);

        provider.clear();

        verify(() => mockService.cancelPull()).called(1);
        expect(provider.isPulling, isFalse);
        expect(provider.pullStatus, isEmpty);
        expect(provider.pullingModelName, isNull);
        expect(provider.pullError, isNull);

        // The old download "finishes" afterwards.
        controller.add(const PullProgressEvent(status: 'success'));
        await controller.close();
        await pulling;

        expect(provider.isPulling, isFalse);
        expect(provider.pullStatus, isEmpty);
        expect(provider.models, isEmpty);
        verifyNever(() => mockService.fetchModels());
      });

      test('does not render the aborted pull stream as a failure', () async {
        when(() => mockService.cancelPull()).thenAnswer((_) {});
        final controller = StreamController<PullProgressEvent>();
        when(
          () => mockService.pullModel('big'),
        ).thenAnswer((_) => controller.stream);

        final pulling = provider.pullModel(mockService, 'big');
        await Future<void>.delayed(Duration.zero);
        provider.clear();
        controller.addError(Exception('Client closed'));
        await controller.close();
        await pulling;

        expect(provider.pullError, isNull);
        expect(provider.isPulling, isFalse);
      });

      test('a new server can pull while the old pull unwinds', () async {
        when(() => mockService.cancelPull()).thenAnswer((_) {});
        final oldPull = StreamController<PullProgressEvent>();
        when(
          () => mockService.pullModel('old'),
        ).thenAnswer((_) => oldPull.stream);
        final other = MockOllamaService();
        final newPull = StreamController<PullProgressEvent>();
        when(() => other.pullModel('new')).thenAnswer((_) => newPull.stream);

        final first = provider.pullModel(mockService, 'old');
        await Future<void>.delayed(Duration.zero);
        provider.clear();
        final second = provider.pullModel(other, 'new');
        await Future<void>.delayed(Duration.zero);

        // The old stream dying late must not touch the new pull's state.
        oldPull.addError(Exception('Client closed'));
        await oldPull.close();
        await first;

        expect(provider.isPulling, isTrue);
        expect(provider.pullingModelName, 'new');
        expect(provider.pullError, isNull);

        newPull.add(const PullProgressEvent(status: 'success'));
        await newPull.close();
        when(() => other.fetchModels()).thenAnswer((_) async => ['new']);
        when(
          () => other.fetchModelInfo(any()),
        ).thenAnswer((_) async => <String, dynamic>{'capabilities': []});
        await second;
      });

      test('discards a capability response that arrives after clear', () async {
        final pending = Completer<Map<String, dynamic>>();
        when(
          () => mockService.fetchModelInfo('llama3'),
        ).thenAnswer((_) => pending.future);

        final fetching = provider.fetchCapabilities(mockService, 'llama3');
        provider.clear();
        pending.complete(<String, dynamic>{
          'capabilities': ['vision'],
        });
        await fetching;

        expect(provider.getCapabilities('llama3'), isNull);
        expect(provider.capabilitiesFailed('llama3'), isFalse);
      });

      test(
        'discards a failed capability response that arrives after clear',
        () async {
          final pending = Completer<Map<String, dynamic>>();
          when(
            () => mockService.fetchModelInfo('llama3'),
          ).thenAnswer((_) => pending.future);

          final fetching = provider.fetchCapabilities(mockService, 'llama3');
          provider.clear();
          pending.completeError(Exception('timeout'));
          await fetching;

          expect(provider.capabilitiesFailed('llama3'), isFalse);
        },
      );

      test('discards a model list that arrives after clear', () async {
        final pending = Completer<List<String>>();
        when(() => mockService.fetchModels()).thenAnswer((_) => pending.future);
        when(
          () => mockService.fetchModelInfo(any()),
        ).thenAnswer((_) async => <String, dynamic>{'capabilities': []});

        final fetching = provider.fetchModels(mockService);
        provider.clear();
        expect(provider.isLoading, isFalse);
        pending.complete(['llama3', 'phi3']);
        await fetching;

        expect(provider.models, isEmpty);
        expect(provider.selectedModel, isNull);
        expect(provider.isLoading, isFalse);
        verifyNever(() => mockService.fetchModelInfo(any()));
      });

      test('discards a model-list failure that arrives after clear', () async {
        final pending = Completer<List<String>>();
        when(() => mockService.fetchModels()).thenAnswer((_) => pending.future);

        final fetching = provider.fetchModels(mockService);
        provider.clear();
        pending.completeError(Exception('timeout'));
        await fetching;

        expect(provider.error, isNull);
        expect(provider.isLoading, isFalse);
      });

      test(
        "a stale fetch doesn't end the next server's loading state",
        () async {
          final oldList = Completer<List<String>>();
          final newList = Completer<List<String>>();
          when(
            () => mockService.fetchModels(),
          ).thenAnswer((_) => oldList.future);
          final other = MockOllamaService();
          when(() => other.fetchModels()).thenAnswer((_) => newList.future);
          when(
            () => other.fetchModelInfo(any()),
          ).thenAnswer((_) async => <String, dynamic>{'capabilities': []});

          final oldFetch = provider.fetchModels(mockService);
          provider.clear();
          final newFetch = provider.fetchModels(other);

          oldList.complete(['from-old-server']);
          await oldFetch;
          expect(provider.isLoading, isTrue);
          expect(provider.models, isEmpty);

          newList.complete(['from-new-server']);
          await newFetch;
          expect(provider.isLoading, isFalse);
          expect(provider.models, ['from-new-server']);
        },
      );
    });

    test('a failing refetch keeps the loaded models and selection', () async {
      when(
        () => mockService.fetchModels(),
      ).thenAnswer((_) async => ['llama3', 'phi3']);
      when(
        () => mockService.fetchModelInfo(any()),
      ).thenAnswer((_) async => <String, dynamic>{'capabilities': []});
      await provider.fetchModels(mockService);
      provider.selectModel('phi3');

      when(() => mockService.fetchModels()).thenThrow(Exception('timed out'));
      await provider.fetchModels(mockService);

      expect(provider.models, ['llama3', 'phi3']);
      expect(provider.selectedModel, 'phi3');
      expect(provider.error, contains('Failed to load models'));
      expect(provider.isLoading, isFalse);
    });

    test('a later successful refetch clears the error', () async {
      when(() => mockService.fetchModels()).thenThrow(Exception('down'));
      await provider.fetchModels(mockService);
      expect(provider.error, isNotNull);

      when(() => mockService.fetchModels()).thenAnswer((_) async => ['a']);
      when(
        () => mockService.fetchModelInfo(any()),
      ).thenAnswer((_) async => <String, dynamic>{'capabilities': []});
      await provider.fetchModels(mockService);

      expect(provider.error, isNull);
      expect(provider.models, ['a']);
    });

    group('capability failures', () {
      test(
        'capabilitiesFailed reports a failed fetch, and clears on success',
        () async {
          when(
            () => mockService.fetchModelInfo('m'),
          ).thenThrow(Exception('boom'));
          expect(provider.capabilitiesFailed('m'), isFalse);

          await provider.fetchCapabilities(mockService, 'm');

          expect(provider.capabilitiesFailed('m'), isTrue);
          expect(provider.getCapabilities('m'), isNull);

          when(() => mockService.fetchModelInfo('m')).thenAnswer(
            (_) async => <String, dynamic>{
              'capabilities': ['tools'],
            },
          );
          await provider.retryCapabilities(mockService, 'm');

          expect(provider.capabilitiesFailed('m'), isFalse);
          expect(provider.getCapabilities('m')!.supportsTools, isTrue);
        },
      );

      test(
        'an automatic refetch waits out the cooldown, a retry does not',
        () async {
          when(
            () => mockService.fetchModelInfo('m'),
          ).thenThrow(Exception('boom'));

          await provider.fetchCapabilities(mockService, 'm');
          await provider.fetchCapabilities(mockService, 'm');
          verify(() => mockService.fetchModelInfo('m')).called(1);

          await provider.retryCapabilities(mockService, 'm');
          verify(() => mockService.fetchModelInfo('m')).called(1);
          // Still failing, so it's back in the failed state.
          expect(provider.capabilitiesFailed('m'), isTrue);
        },
      );

      test('a retry in flight is loading, not failed', () async {
        when(
          () => mockService.fetchModelInfo('m'),
        ).thenThrow(Exception('boom'));
        await provider.fetchCapabilities(mockService, 'm');

        final pending = Completer<Map<String, dynamic>>();
        when(
          () => mockService.fetchModelInfo('m'),
        ).thenAnswer((_) => pending.future);
        var notified = 0;
        provider.addListener(() => notified++);

        final retrying = provider.retryCapabilities(mockService, 'm');
        expect(provider.capabilitiesFailed('m'), isFalse);
        expect(notified, greaterThan(0));

        pending.complete(<String, dynamic>{'capabilities': []});
        await retrying;
        expect(provider.getCapabilities('m'), isNotNull);
      });
    });
  });
}
