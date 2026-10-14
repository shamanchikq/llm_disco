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

    test('isError round-trips through json and defaults to false', () {
      final err = ChatMessage(
          role: 'assistant', content: 'Connection refused', isError: true);
      expect(ChatMessage.fromJson(err.toJson()).isError, isTrue);

      final ok = ChatMessage(role: 'assistant', content: 'hi');
      expect(ok.isError, isFalse);
      expect(ChatMessage.fromJson(ok.toJson()).isError, isFalse);
      expect(ok.toJson().containsKey('isError'), isFalse);
    });

    group('legacy error bubbles', () {
      Map<String, dynamic> json(String role, String content,
              {Object? isError}) =>
          {
            'role': role,
            'content': content,
            'timestamp': '2024-06-15T10:30:00.000',
            'isError': ?isError,
          };

      test('an assistant message starting with [Error: loads as an error', () {
        // stored before the isError flag existed
        final msg = ChatMessage.fromJson(
            json('assistant', '[Error: Connection refused]'));

        expect(msg.isError, isTrue);
      });

      test('an explicit isError value always wins', () {
        expect(
            ChatMessage.fromJson(
                    json('assistant', '[Error: x]', isError: false))
                .isError,
            isFalse);
        expect(
            ChatMessage.fromJson(json('assistant', 'plain', isError: true))
                .isError,
            isTrue);
      });

      test('ordinary messages are not mistaken for errors', () {
        expect(ChatMessage.fromJson(json('assistant', 'Hello')).isError,
            isFalse);
        // a user typing the same text is just text
        expect(ChatMessage.fromJson(json('user', '[Error: x]')).isError,
            isFalse);
        // only a prefix counts
        expect(
            ChatMessage.fromJson(json('assistant', 'see [Error: x]')).isError,
            isFalse);
      });
    });

    test('toApiMap includes tool_calls so history round-trips to Ollama', () {
      // Ollama's chat API expects the assistant message that requested a
      // tool to be echoed back with its tool_calls before the tool result.
      final toolCalls = [
        {
          'function': {
            'name': 'web_search',
            'arguments': {'query': 'dart'},
          },
        },
      ];
      final msg = ChatMessage(
        role: 'assistant',
        content: '',
        toolCalls: toolCalls,
      );

      expect(msg.toApiMap()['tool_calls'], toolCalls);

      // messages without tool calls must not gain the key
      final plain = ChatMessage(role: 'assistant', content: 'hi');
      expect(plain.toApiMap().containsKey('tool_calls'), isFalse);
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

  group('cutOff', () {
    test('round-trips through storage and defaults to false', () {
      final cut = ChatMessage(role: 'assistant', content: 'partial', cutOff: true);
      expect(ChatMessage.fromJson(cut.toJson()).cutOff, isTrue);

      final whole = ChatMessage(role: 'assistant', content: 'done');
      expect(whole.toJson().containsKey('cutOff'), isFalse);
      expect(ChatMessage.fromJson(whole.toJson()).cutOff, isFalse);
    });

    test('is never sent to the model', () {
      final cut = ChatMessage(role: 'assistant', content: 'partial', cutOff: true);
      expect(cut.toApiMap().keys, unorderedEquals(['role', 'content']));
    });
  });
}
