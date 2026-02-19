import 'package:flutter_test/flutter_test.dart';
import 'package:llm_disco_test1/providers/chat_provider.dart';
import 'package:llm_disco_test1/models/conversation.dart';
import '../helpers/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatProvider', () {
    late ChatProvider provider;

    setUp(() {
      provider = ChatProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('initial state', () {
      expect(provider.conversations, isEmpty);
      expect(provider.activeConversation, isNull);
      expect(provider.isStreaming, isFalse);
    });

    test('createConversation', () {
      final conv = provider.createConversation('llama3');

      expect(provider.conversations.length, 1);
      expect(provider.activeConversation, conv);
      expect(conv.model, 'llama3');
      expect(conv.title, 'New Chat');

      // second one should go to the front of the list
      final second = provider.createConversation('phi3');
      expect(provider.conversations.first, second);
    });

    test('delete conversation', () {
      // set up two conversations so we can test different scenarios
      final p = ChatProvider(initialConversations: [
        Conversation(id: 'a', model: 'llama3'),
        Conversation(id: 'b', model: 'phi3'),
      ]);
      addTearDown(p.dispose);

      // deleting the active one should clear activeConversation
      p.setActiveConversation(p.conversations.first);
      p.deleteConversation('a');
      expect(p.activeConversation, isNull);
      expect(p.conversations.length, 1);

      // deleting the last one
      p.deleteConversation('b');
      expect(p.conversations, isEmpty);
    });

    test('rename conversation', () {
      final conv = provider.createConversation('llama3');

      provider.renameConversation(conv.id, 'My Chat');
      expect(provider.conversations.first.title, 'My Chat');

      // whitespace-only should be ignored
      provider.renameConversation(conv.id, '   ');
      expect(provider.conversations.first.title, 'My Chat');

      // should trim whitespace
      provider.renameConversation(conv.id, '  Trimmed  ');
      expect(provider.conversations.first.title, 'Trimmed');
    });

    test('importConversations skips duplicates', () {
      final existing = provider.createConversation('llama3');
      final imported = [
        Conversation(id: existing.id, model: 'llama3', title: 'Duplicate'),
        Conversation(id: 'new-id', model: 'phi3', title: 'New Conv'),
      ];

      final added = provider.importConversations(imported);

      expect(added, 1);
      expect(provider.conversations.length, 2);
    });

    test('setService and disconnectService', () {
      provider.createConversation('llama3');
      provider.createConversation('phi3');

      final mock = MockOllamaService();
      provider.setService(mock);

      // disconnect should clear active but keep conversations
      provider.disconnectService();
      expect(provider.activeConversation, isNull);
      expect(provider.isStreaming, isFalse);
      expect(provider.conversations.length, 2);
    });

    test('searxng and image helpers', () {
      // searxng url should be trimmed, empty becomes null
      provider.setSearxngUrl('  http://example.com  ');
      expect(provider.searxngUrl, 'http://example.com');

      provider.setSearxngUrl('   ');
      expect(provider.searxngUrl, isNull);

      // pending image
      provider.setPendingImage('base64data');
      expect(provider.pendingImageBase64, 'base64data');

      provider.clearPendingImage();
      expect(provider.pendingImageBase64, isNull);
    });

    test('clear wipes everything', () {
      provider.createConversation('llama3');
      provider.createConversation('phi3');
      provider.setService(MockOllamaService());

      provider.clear();

      expect(provider.conversations, isEmpty);
      expect(provider.activeConversation, isNull);
      expect(provider.isStreaming, isFalse);
    });

    test('setActiveConversation', () {
      final conv1 = provider.createConversation('llama3');
      provider.createConversation('phi3');

      provider.setActiveConversation(conv1);
      expect(provider.activeConversation, conv1);
    });
  });
}
