import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/ollama_service.dart';

class ChatProvider extends ChangeNotifier {
  OllamaService? _service;
  final List<Conversation> _conversations = [];
  Conversation? _activeConversation;
  bool _isStreaming = false;

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  Conversation? get activeConversation => _activeConversation;
  bool get isStreaming => _isStreaming;

  void setService(OllamaService service) {
    _service = service;
  }

  Conversation createConversation(String model) {
    final conversation = Conversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      model: model,
    );
    _conversations.insert(0, conversation);
    _activeConversation = conversation;
    notifyListeners();
    return conversation;
  }

  void setActiveConversation(Conversation conversation) {
    _activeConversation = conversation;
    notifyListeners();
  }

  void deleteConversation(String id) {
    _conversations.removeWhere((c) => c.id == id);
    if (_activeConversation?.id == id) {
      _activeConversation = null;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (_service == null || _activeConversation == null) return;

    final userMessage = ChatMessage(role: 'user', content: content);
    _activeConversation!.messages.add(userMessage);

    // Auto-title from first user message
    if (_activeConversation!.messages.where((m) => m.role == 'user').length == 1) {
      _activeConversation!.title = content.length > 30
          ? '${content.substring(0, 30)}...'
          : content;
    }

    final assistantMessage = ChatMessage(role: 'assistant', content: '');
    _activeConversation!.messages.add(assistantMessage);
    _isStreaming = true;
    notifyListeners();

    try {
      await for (final token in _service!.streamChat(
        _activeConversation!.model,
        _activeConversation!.messages
            .where((m) => m.content.isNotEmpty)
            .toList(),
      )) {
        assistantMessage.content += token;
        notifyListeners();
      }
    } catch (e) {
      if (assistantMessage.content.isEmpty) {
        assistantMessage.content = '[Error: $e]';
      }
    } finally {
      _isStreaming = false;
      notifyListeners();
    }
  }

  Future<void> retryLastMessage() async {
    if (_activeConversation == null) return;
    final messages = _activeConversation!.messages;
    if (messages.length < 2) return;

    // Remove failed assistant message
    final lastMsg = messages.last;
    if (lastMsg.role == 'assistant' && lastMsg.content.startsWith('[Error:')) {
      messages.removeLast();
      // Get the last user message to resend
      final lastUserMsg = messages.last;
      if (lastUserMsg.role == 'user') {
        final content = lastUserMsg.content;
        messages.removeLast();
        notifyListeners();
        await sendMessage(content);
      }
    }
  }

  void stopStreaming() {
    _service?.cancelStream();
  }

  void clear() {
    _conversations.clear();
    _activeConversation = null;
    _isStreaming = false;
    _service = null;
    notifyListeners();
  }
}
