import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/conversation.dart';
import 'package:llm_disco_test1/models/chat_message.dart';

void main() {
  group('Conversation', () {
    test('default values', () {
      final conv = Conversation(id: '1', model: 'llama3');

      expect(conv.title, 'New Chat');
      expect(conv.messages, isEmpty);
      expect(conv.thinkingEnabled, isFalse);
      expect(conv.webSearchEnabled, isFalse);
      expect(conv.thinkingLevel, isNull);
      expect(conv.numCtx, isNull);
    });

    test('json round-trip with messages', () {
      // check that serialization works for a full conversation
      final ts = DateTime(2024, 7, 1, 12, 0);
      final original = Conversation(
        id: 'conv-42',
        model: 'gemma2:9b',
        title: 'Test conversation',
        createdAt: ts,
        thinkingEnabled: true,
        thinkingLevel: 'high',
        webSearchEnabled: true,
        numCtx: 4096,
        messages: [
          ChatMessage(role: 'user', content: 'Hi', timestamp: ts),
          ChatMessage(
            role: 'assistant',
            content: 'Hello!',
            timestamp: ts,
            thinking: 'I should greet back',
          ),
        ],
      );

      final restored = Conversation.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.model, original.model);
      expect(restored.title, original.title);
      expect(restored.createdAt, original.createdAt);
      expect(restored.thinkingEnabled, isTrue);
      expect(restored.thinkingLevel, 'high');
      expect(restored.webSearchEnabled, isTrue);
      expect(restored.numCtx, 4096);
      expect(restored.messages.length, 2);
      expect(restored.messages[0].content, 'Hi');
      expect(restored.messages[1].thinking, 'I should greet back');
    });
  });
}
