import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:llm_disco_test1/providers/model_provider.dart';
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
  });
}
