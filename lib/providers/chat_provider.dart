import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/ollama_service.dart';
import '../services/storage_service.dart';

class ChatProvider extends ChangeNotifier {
  OllamaService? _service;
  final List<Conversation> _conversations;
  final StorageService? _storageService;
  Conversation? _activeConversation;
  bool _isStreaming = false;
  String? _pendingImageBase64;
  String? _searxngUrl;

  ChatProvider({
    StorageService? storageService,
    List<Conversation>? initialConversations,
  })  : _storageService = storageService,
        _conversations = initialConversations ?? [];

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  Conversation? get activeConversation => _activeConversation;
  bool get isStreaming => _isStreaming;
  String? get pendingImageBase64 => _pendingImageBase64;
  String? get searxngUrl => _searxngUrl;

  void setService(OllamaService service) {
    _service = service;
  }

  void setSearxngUrl(String? url) {
    _searxngUrl = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
  }

  void setPendingImage(String? base64) {
    _pendingImageBase64 = base64;
    notifyListeners();
  }

  void clearPendingImage() {
    _pendingImageBase64 = null;
    notifyListeners();
  }

  Conversation createConversation(String model) {
    final conversation = Conversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      model: model,
    );
    _conversations.insert(0, conversation);
    _activeConversation = conversation;
    notifyListeners();
    _persist();
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
    _persist();
  }

  Future<void> sendMessage(String content) async {
    if (_service == null || _activeConversation == null) return;

    final userMessage = ChatMessage(
      role: 'user',
      content: content,
      images: _pendingImageBase64 != null ? [_pendingImageBase64!] : null,
    );
    _pendingImageBase64 = null;
    _activeConversation!.messages.add(userMessage);

    // Auto-title from first user message
    if (_activeConversation!.messages
            .where((m) => m.role == 'user')
            .length ==
        1) {
      _activeConversation!.title = content.length > 30
          ? '${content.substring(0, 30)}...'
          : content;
    }

    _isStreaming = true;
    notifyListeners();

    try {
      await _streamResponse();
    } catch (e) {
      final messages = _activeConversation!.messages;
      if (messages.isNotEmpty && messages.last.role == 'assistant') {
        if (messages.last.content.isEmpty) {
          messages.last.content = '[Error: $e]';
        }
      }
    } finally {
      _isStreaming = false;
      notifyListeners();
      _persist();
    }
  }

  Future<void> _streamResponse() async {
    final conv = _activeConversation!;

    final bool thinkingEnabled = conv.thinkingEnabled;
    final bool webSearchEnabled = conv.webSearchEnabled;

    // Build tools list if web search is enabled
    List<Map<String, dynamic>>? tools;
    if (webSearchEnabled && _searxngUrl != null) {
      tools = [_webSearchToolDefinition()];
    }

    // Tool-calling loop: may iterate if model requests tool calls
    for (var iteration = 0; iteration < 5; iteration++) {
      final assistantMessage = ChatMessage(role: 'assistant', content: '');
      conv.messages.add(assistantMessage);
      notifyListeners();

      final messagesToSend = conv.messages
          .where((m) => m.role == 'user' ||
              m.role == 'assistant' && m.content.isNotEmpty ||
              m.role == 'tool')
          .toList();
      // Remove the empty assistant message we just added from the send list
      if (messagesToSend.isNotEmpty && messagesToSend.last == assistantMessage) {
        messagesToSend.removeLast();
      }

      List<Map<String, dynamic>>? receivedToolCalls;

      await for (final event in _service!.streamChat(
        conv.model,
        messagesToSend,
        think: thinkingEnabled ? true : null,
        tools: tools,
      )) {
        if (event.contentToken != null) {
          assistantMessage.content += event.contentToken!;
          notifyListeners();
        }
        if (event.thinkingToken != null) {
          assistantMessage.thinking =
              (assistantMessage.thinking ?? '') + event.thinkingToken!;
          notifyListeners();
        }
        if (event.toolCalls != null) {
          receivedToolCalls = event.toolCalls;
        }
      }

      // If no tool calls, we're done
      if (receivedToolCalls == null || receivedToolCalls.isEmpty) {
        break;
      }

      // Store tool calls on the assistant message
      assistantMessage.toolCalls = receivedToolCalls;

      // Execute each tool call
      for (final toolCall in receivedToolCalls) {
        final function = toolCall['function'] as Map<String, dynamic>?;
        if (function == null) continue;

        final name = function['name'] as String?;
        final args = function['arguments'] as Map<String, dynamic>? ?? {};

        String toolResult;
        if (name == 'web_search' && _searxngUrl != null) {
          final query = args['query'] as String? ?? '';
          try {
            final results =
                await _service!.searchSearXNG(_searxngUrl!, query);
            final buffer = StringBuffer();
            for (final r in results) {
              buffer.writeln('Title: ${r['title'] ?? ''}');
              buffer.writeln('URL: ${r['url'] ?? ''}');
              buffer.writeln('Snippet: ${r['content'] ?? ''}');
              buffer.writeln();
            }
            toolResult = buffer.toString();
          } catch (e) {
            toolResult = 'Search error: $e';
          }
        } else {
          toolResult = 'Unknown tool: $name';
        }

        conv.messages.add(ChatMessage(
          role: 'tool',
          content: toolResult,
        ));
      }

      notifyListeners();
      // Loop continues — model will generate a final response using tool results
    }
  }

  Map<String, dynamic> _webSearchToolDefinition() {
    return {
      'type': 'function',
      'function': {
        'name': 'web_search',
        'description':
            'Search the web for current information. Use this when you need up-to-date information or facts you are unsure about.',
        'parameters': {
          'type': 'object',
          'required': ['query'],
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The search query',
            },
          },
        },
      },
    };
  }

  Future<void> retryLastMessage() async {
    if (_activeConversation == null) return;
    final messages = _activeConversation!.messages;
    if (messages.length < 2) return;

    // Remove everything from the last user message onward
    // (includes failed assistant, any tool messages, etc.)
    int lastUserIndex = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') {
        lastUserIndex = i;
        break;
      }
    }
    if (lastUserIndex < 0) return;

    final lastUserMsg = messages[lastUserIndex];
    final content = lastUserMsg.content;
    final images = lastUserMsg.images;

    // Remove from lastUserIndex onward
    messages.removeRange(lastUserIndex, messages.length);
    notifyListeners();

    // Re-send with same images
    if (images != null && images.isNotEmpty) {
      _pendingImageBase64 = images.first;
    }
    await sendMessage(content);
  }

  void stopStreaming() {
    _service?.cancelStream();
  }

  void disconnectService() {
    _activeConversation = null;
    _isStreaming = false;
    _service = null;
    notifyListeners();
  }

  void clear() {
    _conversations.clear();
    _activeConversation = null;
    _isStreaming = false;
    _service = null;
    notifyListeners();
  }

  Future<void> _persist() async {
    await _storageService?.saveConversations(_conversations);
  }
}
