import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('default values', () {
      final before = DateTime.now();
      final msg = ChatMessage(role: 'user', content: 'hi');
      final after = DateTime.now();

      // timestamp should be roughly "now"
      expect(msg.timestamp.isAfter(before) || msg.timestamp.isAtSameMomentAs(before), isTrue);
      expect(msg.timestamp.isBefore(after) || msg.timestamp.isAtSameMomentAs(after), isTrue);

      // optional stuff should be null
      expect(msg.images, isNull);
      expect(msg.thinking, isNull);
      expect(msg.toolCalls, isNull);
    });

    test('json round-trip preserves all fields', () {
      // make sure we can save and restore messages
      final original = ChatMessage(
        role: 'assistant',
        content: 'Hello there',
        timestamp: DateTime(2024, 6, 15, 10, 30),
        images: ['base64img1', 'base64img2'],
        thinking: 'Let me think about this...',
        toolCalls: [
          {
            'function': {
              'name': 'web_search',
              'arguments': {'query': 'test'},
            },
          },
        ],
      );

      final restored = ChatMessage.fromJson(original.toJson());

      expect(restored.role, original.role);
      expect(restored.content, original.content);
      expect(restored.timestamp, original.timestamp);
      expect(restored.images, original.images);
      expect(restored.thinking, original.thinking);
      expect(restored.toolCalls!.length, original.toolCalls!.length);
      expect(restored.toolCalls!.first['function']['name'], 'web_search');
    });

    test('toApiMap with and without images', () {
      final plain = ChatMessage(
        role: 'user',
        content: 'Hello',
        thinking: 'some thinking',
      );
      final map = plain.toApiMap();

      // should only have role + content, no thinking
      expect(map, {'role': 'user', 'content': 'Hello'});
      expect(map.containsKey('thinking'), isFalse);

      // with images it should include them
      final withImg = ChatMessage(
        role: 'user',
        content: 'Look at this',
        images: ['abc123'],
      );
      expect(withImg.toApiMap()['images'], ['abc123']);

      // empty images list should be omitted
      final emptyImg = ChatMessage(role: 'user', content: 'hi', images: []);
      expect(emptyImg.toApiMap().containsKey('images'), isFalse);
    });
  });
}
