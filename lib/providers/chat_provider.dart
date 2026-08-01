import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/model_capabilities.dart';
import '../services/ollama_service.dart';
import '../services/storage_service.dart';

class ChatProvider extends ChangeNotifier with WidgetsBindingObserver {
  OllamaService? _service;
  final List<Conversation> _conversations;
  final StorageService? _storageService;
  Conversation? _activeConversation;

  /// Id of the conversation currently generating, or null when idle.
  /// Scoped rather than a plain bool so browsing to another chat mid-stream
  /// doesn't make that chat look busy — or, worse, receive the fallout.
  String? _streamingConversationId;
  bool _cancelRequested = false;
  final List<String> _pendingImages = [];
  String? _pendingFileName;
  String? _pendingFileBase64;
  String? _pendingFileMimeType;
  String? _searxngUrl;
  String? _draft;
  Timer? _persistTimer;

  ChatProvider({
    StorageService? storageService,
    List<Conversation>? initialConversations,
  })  : _storageService = storageService,
        _conversations = initialConversations ?? [] {
    WidgetsBinding.instance.addObserver(this);
    _cleanUpInterruptedMessages();
  }

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  Conversation? get activeConversation => _activeConversation;
  /// True when the conversation on screen is the one generating.
  bool get isStreaming =>
      _streamingConversationId != null &&
      _streamingConversationId == _activeConversation?.id;

  /// True while any conversation is generating. `OllamaService` multiplexes
  /// a single cancellable client, so a second send has to wait.
  bool get isAnyStreaming => _streamingConversationId != null;

  String? get pendingFileName => _pendingFileName;
  String? get searxngUrl => _searxngUrl;
  double? get lastTokensPerSec => _activeConversation?.lastTokensPerSec;

  void setService(OllamaService service) {
    _service = service;
  }

  void setSearxngUrl(String? url) {
    _searxngUrl = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
  }

  List<String> get pendingImages => List.unmodifiable(_pendingImages);

  void addPendingImage(String base64) {
    _pendingImages.add(base64);
    notifyListeners();
  }

  void removePendingImageAt(int index) {
    if (index < 0 || index >= _pendingImages.length) return;
    _pendingImages.removeAt(index);
    notifyListeners();
  }

  void clearPendingImages() {
    _pendingImages.clear();
    notifyListeners();
  }

  void setPendingFile(String name, String base64, String mimeType) {
    _pendingFileName = name;
    _pendingFileBase64 = base64;
    _pendingFileMimeType = mimeType;
    notifyListeners();
  }

  void clearPendingFile() {
    _pendingFileName = null;
    _pendingFileBase64 = null;
    _pendingFileMimeType = null;
    notifyListeners();
  }

  int _idCounter = 0;

  /// Timestamp plus a counter: two chats created in the same millisecond
  /// would otherwise share an id, breaking delete-by-id and list keys.
  String _newConversationId() {
    final existing = _conversations.map((c) => c.id).toSet();
    String candidate;
    do {
      candidate = '${DateTime.now().millisecondsSinceEpoch}-${_idCounter++}';
    } while (existing.contains(candidate));
    return candidate;
  }

  Conversation createConversation(String model) {
    final conversation = Conversation(
      id: _newConversationId(),
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

  void renameConversation(String id, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final conv = _conversations.where((c) => c.id == id).firstOrNull;
    if (conv != null) {
      conv.title = trimmed;
      notifyListeners();
      _persist();
    }
  }

  int importConversations(List<Conversation> imported) {
    final existingIds = _conversations.map((c) => c.id).toSet();
    int added = 0;
    for (final conv in imported) {
      if (!existingIds.contains(conv.id)) {
        _conversations.insert(0, conv);
        added++;
      }
    }
    if (added > 0) {
      notifyListeners();
      _persist();
    }
    return added;
  }

  void deleteConversation(String id) {
    deleteConversationForUndo(id);
  }

  Future<void> sendMessage(String content,
      {ModelCapabilities? capabilities}) async {
    if (_service == null || _activeConversation == null) return;
    // One generation at a time — the service shares a single cancellable
    // client, so a concurrent send would orphan the first stream.
    if (_streamingConversationId != null) return;

    // Captured up front: every later step must target this conversation
    // even if the user browses to another one mid-stream.
    final conv = _activeConversation!;

    final userMessage = ChatMessage(
      role: 'user',
      content: content,
      images: _pendingImages.isNotEmpty ? List.of(_pendingImages) : null,
      files: _pendingFileBase64 != null
          ? [{'name': _pendingFileName!, 'data': _pendingFileBase64!, 'type': _pendingFileMimeType!}]
          : null,
    );
    _pendingImages.clear();
    _pendingFileName = null;
    _pendingFileBase64 = null;
    _pendingFileMimeType = null;
    conv.messages.add(userMessage);

    // Auto-title from first user message
    if (conv.messages.where((m) => m.role == 'user').length == 1) {
      conv.title = autoTitleFor(content);
    }

    conv.lastTokensPerSec = null;
    _streamingConversationId = conv.id;
    _cancelRequested = false;
    notifyListeners();

    try {
      await _streamResponse(conv, capabilities);
      _maybeGenerateTitle(conv, capabilities);
    } catch (e) {
      final messages = conv.messages;
      if (messages.isNotEmpty && messages.last.role == 'assistant') {
        final last = messages.last;
        if (last.content.isNotEmpty) {
          // Partial content exists — mark as interrupted, not error
          last.content += '\n\n*[Response interrupted]*';
        } else if (!_cancelRequested) {
          last.content = e.toString();
          last.isError = true;
        } else if (last.thinking != null) {
          // User stopped during the thinking phase — keep what arrived.
          last.content = '*[Stopped]*';
        } else {
          // User stopped before anything arrived — nothing to show.
          messages.removeLast();
        }
      }
    } finally {
      _cancelPersistTimer();
      _streamingConversationId = null;
      notifyListeners();
      _persist();
    }
  }

  Future<void> _streamResponse(
      Conversation conv, ModelCapabilities? capabilities) async {
    final bool webSearchEnabled = conv.webSearchEnabled;

    // Only send the think parameter for models with the thinking
    // capability — Ollama rejects it for others. Unknown capabilities
    // (fetch pending/failed) → omit and let the server use its default.
    Object? think;
    if (capabilities?.supportsThinking == true) {
      if (capabilities!.thinkingMode == 'levels') {
        // gpt-oss: always on, effort level only
        think = conv.thinkingLevel ?? 'medium';
      } else if (conv.thinkingEnabled ?? true) {
        think = conv.thinkingLevel ?? true;
      } else {
        think = false;
      }
    }

    // Build tools list if web search is enabled
    List<Map<String, dynamic>>? tools;
    if (webSearchEnabled && _searxngUrl != null) {
      tools = [_webSearchToolDefinition()];
    }

    _startPersistTimer();

    // Tool-calling loop: may iterate if model requests tool calls
    for (var iteration = 0; iteration < 5; iteration++) {
      final assistantMessage = ChatMessage(role: 'assistant', content: '');
      conv.messages.add(assistantMessage);
      notifyListeners();

      // Assistant messages that only carried tool calls have empty content
      // but must stay in the history — Ollama expects the tool_calls message
      // to precede its tool results. Error bubbles never go back to the model.
      final messagesToSend = conv.messages
          .where((m) => m.role == 'user' ||
              m.role == 'assistant' &&
                  !m.isError &&
                  (m.content.isNotEmpty || m.toolCalls != null) ||
              m.role == 'tool')
          .toList();
      // Remove the empty assistant message we just added from the send list
      if (messagesToSend.isNotEmpty && messagesToSend.last == assistantMessage) {
        messagesToSend.removeLast();
      }

      // System prompt is injected per-request rather than stored in the
      // message history, so editing it applies to the whole conversation.
      final systemPrompt = conv.systemPrompt;
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        messagesToSend.insert(
            0, ChatMessage(role: 'system', content: systemPrompt));
      }

      List<Map<String, dynamic>>? receivedToolCalls;

      await for (final event in _service!.streamChat(
        conv.model,
        messagesToSend,
        think: think,
        tools: tools,
        numCtx: conv.numCtx,
        temperature: conv.temperature,
        topK: conv.topK,
        topP: conv.topP,
        repeatPenalty: conv.repeatPenalty,
        seed: conv.seed,
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
        if (event.evalCount != null && event.evalDuration != null && event.evalDuration! > 0) {
          conv.lastTokensPerSec =
              event.evalCount! / (event.evalDuration! / 1e9);
          notifyListeners();
        }
        if (event.done &&
            (event.promptEvalCount != null || event.evalCount != null)) {
          conv.lastContextTokens =
              (event.promptEvalCount ?? 0) + (event.evalCount ?? 0);
          notifyListeners();
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

  /// Removes a user message together with every response it produced
  /// (assistant + tool messages up to the next user message).
  void deleteMessagePair(ChatMessage userMessage) {
    final conv = _activeConversation;
    if (conv == null || userMessage.role != 'user') return;
    final index = conv.messages.indexOf(userMessage);
    if (index < 0) return;
    var end = index + 1;
    while (end < conv.messages.length && conv.messages[end].role != 'user') {
      end++;
    }
    conv.messages.removeRange(index, end);
    notifyListeners();
    _persist();
  }

  /// Deletes a conversation and returns it with its list position so the
  /// UI can offer undo.
  (Conversation, int)? deleteConversationForUndo(String id) {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index < 0) return null;
    // Don't leave a stream writing into a conversation that's gone.
    if (_streamingConversationId == id) {
      stopStreaming();
    }
    final conv = _conversations.removeAt(index);
    if (_activeConversation?.id == id) {
      _activeConversation = null;
    }
    notifyListeners();
    _persist();
    return (conv, index);
  }

  void restoreConversation(Conversation conversation, int index) {
    _conversations.insert(
        index.clamp(0, _conversations.length), conversation);
    notifyListeners();
    _persist();
  }

  /// Pre-fills the chat input (used by empty-state starter chips).
  void setDraft(String text) {
    _draft = text;
    notifyListeners();
  }

  String? takeDraft() {
    final d = _draft;
    _draft = null;
    return d;
  }

  /// Rewrites history from [message] onward and re-sends with the new text.
  Future<void> editAndResend(ChatMessage message, String newContent,
      {ModelCapabilities? capabilities}) async {
    final conv = _activeConversation;
    if (conv == null || message.role != 'user') return;
    final index = conv.messages.indexOf(message);
    if (index < 0) return;

    final images = message.images;
    final files = message.files;
    conv.messages.removeRange(index, conv.messages.length);
    notifyListeners();

    if (images != null && images.isNotEmpty) {
      _pendingImages
        ..clear()
        ..addAll(images);
    }
    if (files != null && files.isNotEmpty) {
      final f = files.first;
      _pendingFileName = f['name'];
      _pendingFileBase64 = f['data'];
      _pendingFileMimeType = f['type'];
    }
    await sendMessage(newContent, capabilities: capabilities);
  }

  /// Notify + persist after the UI edits conversation settings in place
  /// (system prompt, context size, sampling parameters).
  void conversationSettingsChanged() {
    notifyListeners();
    _persist();
  }

  void changeConversationModel(String id, String model) {
    final conv = _conversations.where((c) => c.id == id).firstOrNull;
    if (conv == null || conv.model == model) return;
    conv.model = model;
    notifyListeners();
    _persist();
  }

  /// Fallback title derived from the first user message. Grapheme-aware so
  /// truncation can't split an emoji, and always single-line.
  static String autoTitleFor(String content) {
    final singleLine = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final chars = singleLine.characters;
    if (chars.length <= 30) return singleLine;
    return '${chars.take(30)}...';
  }

  /// After the first successful exchange, ask the model itself for a short
  /// title. Fire-and-forget: failure or a meanwhile-renamed conversation
  /// just keeps the fallback title.
  void _maybeGenerateTitle(
      Conversation conv, ModelCapabilities? capabilities) {
    final service = _service;
    if (service == null) return;
    final userMessages = conv.messages.where((m) => m.role == 'user');
    if (userMessages.length != 1) return;
    final firstUser = userMessages.first.content;
    // Only ever replace the fallback title, never a manual rename.
    if (conv.title != autoTitleFor(firstUser)) return;
    final reply = conv.messages.last;
    if (reply.role != 'assistant' || reply.content.isEmpty || reply.isError) {
      return;
    }

    String clip(String s) => s.length > 500 ? s.substring(0, 500) : s;
    final prompt = 'Write a short title (3-5 words) for this conversation. '
        'Reply with only the title — no quotes, no trailing punctuation.\n\n'
        'User: ${clip(firstUser)}\n\nAssistant: ${clip(reply.content)}';
    // Don't let thinking models spend seconds reasoning about a title;
    // gpt-oss can't disable thinking, so leave it unset there.
    Object? think;
    if (capabilities?.supportsThinking == true &&
        capabilities!.thinkingMode != 'levels') {
      think = false;
    }

    // Guarded so a title failure can never disturb the send flow.
    try {
      service.generateText(conv.model, prompt, think: think).then((raw) {
        final title = _sanitizeTitle(raw);
        if (title.isEmpty) return;
        if (conv.title != autoTitleFor(firstUser)) return; // renamed meanwhile
        conv.title = title;
        notifyListeners();
        _persist();
      }).catchError((_) {});
    } catch (_) {}
  }

  static String _sanitizeTitle(String raw) {
    final lines =
        raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    if (lines.isEmpty) return '';
    var t = lines.first;
    t = t.replaceAll(RegExp(r"^['\x22#*\s]+"), '');
    t = t.replaceAll(RegExp(r"['\x22*.\s]+$"), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > 60) t = '${t.substring(0, 60)}…';
    return t;
  }

  Future<void> retryLastMessage({ModelCapabilities? capabilities}) async {
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
    final files = lastUserMsg.files;

    // Remove from lastUserIndex onward
    messages.removeRange(lastUserIndex, messages.length);
    notifyListeners();

    // Re-send with same images and files
    if (images != null && images.isNotEmpty) {
      _pendingImages
        ..clear()
        ..addAll(images);
    }
    if (files != null && files.isNotEmpty) {
      final f = files.first;
      _pendingFileName = f['name'];
      _pendingFileBase64 = f['data'];
      _pendingFileMimeType = f['type'];
    }
    await sendMessage(content, capabilities: capabilities);
  }

  void stopStreaming() {
    // Distinguishes a user-initiated stop from a genuine stream error so
    // the catch in sendMessage doesn't render the cancel as an error.
    _cancelRequested = true;
    _service?.cancelStream();
  }

  void disconnectService() {
    _activeConversation = null;
    _streamingConversationId = null;
    _service = null;
    notifyListeners();
  }

  void clear() {
    _conversations.clear();
    _activeConversation = null;
    _streamingConversationId = null;
    _service = null;
    notifyListeners();
  }

  /// Wipes every conversation and the files behind them (including the
  /// backup, so history can't reappear through the corruption fallback).
  Future<void> deleteAllConversations() async {
    if (_streamingConversationId != null) stopStreaming();
    _cancelPersistTimer();
    _conversations.clear();
    _activeConversation = null;
    notifyListeners();
    await _storageService?.deleteAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _persist();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelPersistTimer();
    super.dispose();
  }

  void _startPersistTimer() {
    if (_persistTimer != null) return;
    _persistTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _persist();
    });
  }

  void _cancelPersistTimer() {
    _persistTimer?.cancel();
    _persistTimer = null;
  }

  Future<void> _persist() async {
    await _storageService?.saveConversations(_conversations);
  }

  void _cleanUpInterruptedMessages() {
    for (final conv in _conversations) {
      if (conv.messages.isNotEmpty &&
          conv.messages.last.role == 'assistant' &&
          conv.messages.last.content.isEmpty &&
          conv.messages.last.thinking == null) {
        // Empty assistant message from a killed stream — remove it
        conv.messages.removeLast();
      }
    }
  }
}
