import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/conversation.dart';
import 'package:llm_disco_test1/models/chat_message.dart';

void main() {
  group('Conversation', () {
    test('default values', () {
      final conv = Conversation(id: '1', model: 'llama3');

      expect(conv.title, 'New Chat');
      expect(conv.messages, isEmpty);
      // null = unset: thinking-capable models default to on (Ollama default)
      expect(conv.thinkingEnabled, isNull);
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
        systemPrompt: 'Be concise.',
        numCtx: 4096,
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        repeatPenalty: 1.1,
        seed: 42,
        lastContextTokens: 1234,
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
      expect(restored.systemPrompt, 'Be concise.');
      expect(restored.numCtx, 4096);
      expect(restored.temperature, 0.7);
      expect(restored.topK, 40);
      expect(restored.topP, 0.9);
      expect(restored.repeatPenalty, 1.1);
      expect(restored.seed, 42);
      expect(restored.lastContextTokens, 1234);
      expect(restored.messages.length, 2);
      expect(restored.messages[0].content, 'Hi');
      expect(restored.messages[1].thinking, 'I should greet back');
    });

    test('fromJson tolerates ints stored in double fields', () {
      // jsonDecode yields int for "1" but double for "1.0"; a strict
      // `as double?` would throw and fail the whole file load.
      final restored = Conversation.fromJson({
        'id': 'int-coerce',
        'model': 'llama3',
        'title': 't',
        'createdAt': '2024-07-01T12:00:00.000',
        'messages': [],
        'numCtx': 2048,
        'lastContextTokens': 120,
        'temperature': 1,
        'topP': 1,
        'topK': 40,
        'repeatPenalty': 1,
        'seed': 7,
      });

      expect(restored.numCtx, 2048);
      expect(restored.lastContextTokens, 120);
      expect(restored.temperature, 1.0);
      expect(restored.topP, 1.0);
      expect(restored.topK, 40);
      expect(restored.repeatPenalty, 1.0);
      expect(restored.seed, 7);
    });
  });
}
