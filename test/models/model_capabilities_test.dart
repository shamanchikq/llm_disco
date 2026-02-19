import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/model_capabilities.dart';

void main() {
  group('ModelCapabilities', () {
    test('default values', () {
      const caps = ModelCapabilities();

      expect(caps.supportsVision, isFalse);
      expect(caps.supportsThinking, isFalse);
      expect(caps.supportsTools, isFalse);
      expect(caps.thinkingMode, isNull);
    });

    test('json round-trip', () {
      const original = ModelCapabilities(
        supportsVision: true,
        supportsThinking: true,
        thinkingMode: 'levels',
        supportsTools: true,
      );

      final restored = ModelCapabilities.fromJson(original.toJson());

      expect(restored.supportsVision, isTrue);
      expect(restored.supportsThinking, isTrue);
      expect(restored.thinkingMode, 'levels');
      expect(restored.supportsTools, isTrue);
    });
  });
}
