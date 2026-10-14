import 'dart:async';
import 'dart:convert';

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

  /// The exchange (one send plus its tool-loop legs) in flight, or null.
  /// Cancellation is per exchange, not a provider-wide flag, so a stop or
  /// disconnect can only ever end the exchange it was meant for.
  _Exchange? _currentExchange;

  /// What the user has typed and attached but not sent yet, per conversation
  /// (keyed by id; '' while no conversation is active). Session-only — a
  /// half-written message or a staged photo stays with the chat it was meant
  /// for instead of following the user into another one.
  final Map<String, _Composer> _composers = {};
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

  _Composer get _composer =>
      _composers.putIfAbsent(_activeConversation?.id ?? '', _Composer.new);

  String? get pendingFileName => _composer.fileName;
  String? get searxngUrl => _searxngUrl;
  double? get lastTokensPerSec => _activeConversation?.lastTokensPerSec;

  void setService(OllamaService service) {
    _service = service;
  }

  void setSearxngUrl(String? url) {
    _searxngUrl = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
  }

  /// Attachments staged in the active conversation's composer.
  List<String> get pendingImages => List.unmodifiable(_composer.images);

  void addPendingImage(String base64) {
    _composer.images.add(base64);
    notifyListeners();
  }

  void removePendingImageAt(int index) {
    final images = _composer.images;
    if (index < 0 || index >= images.length) return;
    images.removeAt(index);
    notifyListeners();
  }

  void clearPendingImages() {
    _composer.images.clear();
    notifyListeners();
  }

  void setPendingFile(String name, String base64, String mimeType) {
    _composer
      ..fileName = name
      ..fileBase64 = base64
      ..fileMimeType = mimeType;
    notifyListeners();
  }

  void clearPendingFile() {
    _composer.clearFile();
    notifyListeners();
  }

  /// Unsent text in conversation [id]'s composer ('' when there is none).
  String composerTextFor(String id) => _composers[id]?.text ?? '';

  /// Remembers the composer text of conversation [id] so it can be put back
  /// when that chat is shown again. Doesn't notify: the text field already
  /// shows what was typed.
  void setComposerText(String id, String text) {
    _composers.putIfAbsent(id, _Composer.new).text = text;
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
      // add() also dedupes within the batch itself
      if (existingIds.add(conv.id)) {
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

  bool get _canSend =>
      _service != null &&
      _activeConversation != null &&
      // One generation at a time — the service shares a single cancellable
      // client, so a concurrent send would orphan the first stream.
      _streamingConversationId == null;

  Future<void> sendMessage(String content,
      {ModelCapabilities? capabilities}) async {
    if (!_canSend) return;

    final composer = _composer;
    final images = composer.images.isNotEmpty ? List.of(composer.images) : null;
    final files = composer.fileBase64 != null
        ? [
            {
              'name': composer.fileName!,
              'data': composer.fileBase64!,
              'type': composer.fileMimeType!,
            }
          ]
        : null;
    composer
      ..images.clear()
      ..clearFile();

    await _send(content, images, files, capabilities);
  }

  /// Sends with explicitly supplied attachments. Retry and edit go through
  /// here with the old message's own attachments so they never read or
  /// consume what the user has staged in the composer for their next one.
  Future<void> _send(
    String content,
    List<String>? images,
    List<Map<String, String>>? files,
    ModelCapabilities? capabilities,
  ) async {
    // Captured up front: every later step must target this conversation,
    // service and model even if the user browses to another chat, reconnects
    // or switches models mid-stream.
    final service = _service;
    final conv = _activeConversation;
    if (service == null || conv == null || _streamingConversationId != null) {
      return;
    }
    final model = conv.model;

    final userMessage = ChatMessage(
      role: 'user',
      content: content,
      images: images,
      files: files,
    );
    conv.messages.add(userMessage);

    // Auto-title from the first user message — but only while the title is
    // still the untouched default, so retrying or editing an opening
    // message never downgrades a model-generated or manual title.
    if (conv.title == 'New Chat' &&
        conv.messages.where((m) => m.role == 'user').length == 1) {
      conv.title = autoTitleFor(content);
    }

    final exchange = _Exchange(service, userMessage);
    _currentExchange = exchange;
    conv.lastTokensPerSec = null;
    _streamingConversationId = conv.id;
    notifyListeners();

    try {
      await _streamResponse(conv, exchange, model, capabilities);
      // A stopped exchange may be orphaned (disconnect) — leave it be.
      if (!exchange.cancelled) {
        _maybeGenerateTitle(conv, service, model, capabilities);
      }
    } catch (e) {
      _recoverFailedExchange(conv, exchange, e);
    } finally {
      // A detached exchange (disconnect, delete) winds down here too; it
      // must not clear state that belongs to one started after it.
      if (identical(_currentExchange, exchange)) {
        _cancelPersistTimer();
        _currentExchange = null;
        _streamingConversationId = null;
      }
      notifyListeners();
      _persist();
    }
  }

  /// How many request/response legs one send may take: each leg that ends in
  /// tool calls is followed by another with the results.
  static const _maxLegs = 5;

  Future<void> _streamResponse(Conversation conv, _Exchange exchange,
      String model, ModelCapabilities? capabilities) async {
    final service = exchange.service;
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

    // Build tools list if web search is enabled. A chat can keep the toggle
    // on after switching to a model without the tools capability (the chip
    // is hidden there) — Ollama rejects tools for those, so leave them out.
    List<Map<String, dynamic>>? tools;
    if (webSearchEnabled &&
        _searxngUrl != null &&
        capabilities?.supportsTools != false) {
      tools = [_webSearchToolDefinition()];
    }

    _startPersistTimer();

    // Tool-calling loop: may iterate if model requests tool calls
    for (var leg = 0; leg < _maxLegs; leg++) {
      exchange.throwIfCancelled();

      // The last leg goes out without tools so the model has to answer in
      // text instead of ending the exchange on another round of results.
      final isLastLeg = leg == _maxLegs - 1;

      final assistantMessage = ChatMessage(role: 'assistant', content: '');
      conv.messages.add(assistantMessage);
      exchange.appended.add(assistantMessage);
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

      // Ollama may spread parallel calls over several chunks.
      final receivedToolCalls = <Map<String, dynamic>>[];

      await for (final event in service.streamChat(
        model,
        messagesToSend,
        think: think,
        tools: isLastLeg ? null : tools,
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
          receivedToolCalls.addAll(event.toolCalls!);
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

      // No tool calls (or none honoured on the tool-less last leg): the
      // exchange is done.
      if (receivedToolCalls.isEmpty || isLastLeg) {
        // A model that returned nothing at all would otherwise leave a
        // permanent empty bubble. Say so instead: an error bubble offers
        // retry and never goes back to the model as history.
        if (assistantMessage.content.isEmpty &&
            (assistantMessage.thinking?.isEmpty ?? true)) {
          assistantMessage
            ..content = 'The model returned an empty response.'
            ..isError = true;
        }
        break;
      }

      // A stop that landed after the leg finished must not start a search.
      exchange.throwIfCancelled();

      // Store tool calls on the assistant message
      assistantMessage.toolCalls = _withObjectArguments(receivedToolCalls);

      // Execute each tool call — exactly one tool message per call.
      for (final toolCall in receivedToolCalls) {
        final result = await _runToolCall(exchange, toolCall);
        exchange.throwIfCancelled();
        final toolMessage = ChatMessage(role: 'tool', content: result);
        conv.messages.add(toolMessage);
        exchange.appended.add(toolMessage);
      }

      notifyListeners();
      // Loop continues — model will generate a final response using tool results
    }
  }

  /// Runs one tool call and returns the text handed back to the model.
  /// Only throws [_ExchangeCancelled]: anything the model got wrong becomes
  /// the tool result, so it can correct itself instead of the whole
  /// exchange failing.
  Future<String> _runToolCall(
      _Exchange exchange, Map<String, dynamic> toolCall) async {
    exchange.throwIfCancelled();
    final function = toolCall['function'];
    if (function is! Map) return 'Invalid tool call: missing function.';

    final name = function['name']?.toString();
    final searxngUrl = _searxngUrl;
    if (name != 'web_search' || searxngUrl == null) {
      return 'Unknown tool: $name';
    }

    final Map<String, dynamic> args;
    try {
      args = _parseToolArguments(function['arguments']);
    } catch (e) {
      return 'Invalid tool arguments: ${e is FormatException ? e.message : e}';
    }
    final query = args['query']?.toString() ?? '';

    try {
      // Raced against the stop signal: a search can take many seconds, and
      // Stop has no HTTP stream to abort between legs.
      final results = await Future.any([
        exchange.service.searchSearXNG(searxngUrl, query),
        exchange.whenCancelled.then((_) => const <Map<String, dynamic>>[]),
      ]);
      exchange.throwIfCancelled();
      if (results.isEmpty) return 'No results found.';
      final buffer = StringBuffer();
      for (final r in results) {
        buffer.writeln('Title: ${r['title'] ?? ''}');
        buffer.writeln('URL: ${r['url'] ?? ''}');
        buffer.writeln('Snippet: ${r['content'] ?? ''}');
        buffer.writeln();
      }
      return buffer.toString();
    } on _ExchangeCancelled {
      rethrow;
    } catch (e) {
      return 'Search error: $e';
    }
  }

  /// Ollama normally sends arguments as an object, but some models emit a
  /// JSON-encoded string instead.
  static Map<String, dynamic> _parseToolArguments(Object? raw) {
    if (raw == null) return {};
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('expected a JSON object');
    }
    throw FormatException('expected an object, got ${raw.runtimeType}');
  }

  /// Ollama rejects a resent tool call whose arguments aren't an object, so
  /// string-encoded (or unusable) arguments are normalised before the call
  /// is stored in the history.
  static List<Map<String, dynamic>> _withObjectArguments(
      List<Map<String, dynamic>> calls) {
    final result = <Map<String, dynamic>>[];
    for (final call in calls) {
      final function = call['function'];
      if (function is! Map || function['arguments'] is Map) {
        result.add(call);
        continue;
      }
      Map<String, dynamic> args;
      try {
        args = _parseToolArguments(function['arguments']);
      } catch (_) {
        args = {};
      }
      result.add({
        ...call,
        'function': {...Map<String, dynamic>.from(function), 'arguments': args},
      });
    }
    return result;
  }

  /// Rebuilds the conversation tail after a failed or cancelled exchange:
  /// drops every assistant/tool message the exchange appended (including any
  /// tool-loop iterations), then restores what the user should see —
  /// partial output kept as interrupted, a genuine failure as an error
  /// bubble, a user stop quietly removed unless thinking had arrived.
  void _recoverFailedExchange(
      Conversation conv, _Exchange exchange, Object e) {
    // Remember whatever streamed into the newest assistant bubble of this
    // exchange before rolling back.
    ChatMessage? streamed;
    for (final m in exchange.appended.reversed) {
      if (m.role == 'assistant') {
        if (m.content.isNotEmpty || (m.thinking?.isNotEmpty ?? false)) {
          streamed = m;
        }
        break;
      }
    }

    // Roll back by identity rather than by position: an orphaned exchange
    // can wind down after a later one has added messages to the same chat.
    // A preserved partial loses its tool calls on purpose: their results are
    // discarded with the rest of the failed tail.
    final partialThinking = streamed?.thinking;
    streamed?.toolCalls = null;
    final userIndex = conv.messages.indexOf(exchange.userMessage);
    conv.messages.removeWhere(exchange.appended.contains);
    // The user deleted the exchange meanwhile — nothing left to attach to.
    if (userIndex < 0) return;
    final insertAt = userIndex + 1;

    if (streamed != null && streamed.content.isNotEmpty) {
      // Partial output survives a stop or failure either way; label it so
      // it doesn't read as a complete answer.
      streamed.content += '\n\n*[Response interrupted]*';
      conv.messages.insert(insertAt, streamed);
      return;
    }

    if (exchange.cancelled) {
      // Stopped during the thinking phase — keep what arrived; stopped
      // before anything arrived — nothing to show.
      if (partialThinking != null) {
        conv.messages.insert(
            insertAt,
            ChatMessage(
              role: 'assistant',
              content: '*[Stopped]*',
              thinking: partialThinking,
            ));
      }
      return;
    }

    // Genuine failure — an error bubble, carrying any reasoning that had
    // already streamed in so it isn't lost to the collapse.
    final error = ChatMessage(role: 'assistant', content: e.toString());
    error.isError = true;
    if (partialThinking != null) error.thinking = partialThinking;
    conv.messages.insert(insertAt, error);
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
    // Undo can fire twice, or after the same chat was re-imported.
    if (_conversations.any((c) => c.id == conversation.id)) return;
    _conversations.insert(
        index.clamp(0, _conversations.length), conversation);
    notifyListeners();
    _persist();
  }

  /// How long a swipe-deleted conversation stays restorable.
  static const undoWindow = Duration(seconds: 5);

  /// Swipe-deleted conversations still inside their undo window, oldest
  /// first. Held here rather than in the sidebar: the drawer's state is
  /// rebuilt every time it opens, which dropped the undo offer the moment
  /// the drawer closed.
  final List<(Conversation, int)> _pendingUndo = [];
  Timer? _undoTimer;

  /// How many deleted conversations [undoDelete] would bring back.
  int get undoableDeletes => _pendingUndo.length;

  /// Deletes a conversation and keeps it restorable for [undoWindow].
  void deleteConversationWithUndo(String id) {
    final removed = deleteConversationForUndo(id);
    if (removed == null) return;
    _pendingUndo.add(removed);
    // One window for the whole batch — a further delete restarts it rather
    // than making the earlier one unrecoverable.
    _undoTimer?.cancel();
    _undoTimer = Timer(undoWindow, _dropPendingUndo);
    notifyListeners();
  }

  /// Restores everything deleted within the current undo window.
  void undoDelete() {
    _undoTimer?.cancel();
    _undoTimer = null;
    // Newest first, so each chat lands back on the index it was removed from.
    final pending = _pendingUndo.reversed.toList();
    _pendingUndo.clear();
    for (final (conversation, index) in pending) {
      restoreConversation(conversation, index);
    }
    notifyListeners();
  }

  void _dropPendingUndo() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (_pendingUndo.isEmpty) return;
    _pendingUndo.clear();
    notifyListeners();
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
    // Guard BEFORE touching history: a rejected resend (disconnected, or
    // another chat generating) must not truncate the conversation.
    if (_service == null) return;
    if (_streamingConversationId != null) return;
    final index = conv.messages.indexOf(message);
    if (index < 0) return;

    // If the title is the fallback derived from THIS opening message, move
    // it in step with the edit; generated/manual titles are left alone, and
    // a later message that merely repeats the opener's text isn't the opener.
    final opener = conv.messages.where((m) => m.role == 'user').firstOrNull;
    if (identical(opener, message) &&
        conv.title == autoTitleFor(message.content)) {
      conv.title = autoTitleFor(newContent);
    }

    final images = message.images;
    final files = message.files;
    conv.messages.removeRange(index, conv.messages.length);
    notifyListeners();

    await _send(newContent, _copyImages(images), _copyFiles(files),
        capabilities);
  }

  static List<String>? _copyImages(List<String>? images) =>
      images != null && images.isNotEmpty ? List.of(images) : null;

  static List<Map<String, String>>? _copyFiles(
          List<Map<String, String>>? files) =>
      files != null && files.isNotEmpty
          ? [for (final f in files) Map.of(f)]
          : null;

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
  void _maybeGenerateTitle(Conversation conv, OllamaService service,
      String model, ModelCapabilities? capabilities) {
    final userMessages = conv.messages.where((m) => m.role == 'user');
    if (userMessages.length != 1) return;
    final firstUser = userMessages.first.content;
    // Only ever replace the fallback title, never a manual rename.
    if (conv.title != autoTitleFor(firstUser)) return;
    final reply = conv.messages.last;
    if (reply.role != 'assistant' || reply.content.isEmpty || reply.isError) {
      return;
    }

    // Grapheme-aware so a cut can't split an emoji
    String clip(String s) =>
        s.characters.length > 500 ? s.characters.take(500).toString() : s;
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
      service.generateText(model, prompt, think: think).then((raw) {
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
    if (t.characters.length > 60) t = '${t.characters.take(60)}…';
    return t;
  }

  Future<void> retryLastMessage({ModelCapabilities? capabilities}) async {
    if (_activeConversation == null) return;
    // Guard BEFORE touching history: a rejected retry (disconnected, or
    // another chat generating) must not delete the exchange it targets.
    if (_service == null) return;
    if (_streamingConversationId != null) return;
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

    // Re-send with the old message's own images and files
    await _send(content, _copyImages(images), _copyFiles(files), capabilities);
  }

  void stopStreaming() {
    // Marks only the exchange in flight, so the catch in _send can tell a
    // user-initiated stop from a genuine stream error — and a stale stop can
    // never leak into a later exchange. The cancel also wakes a tool call
    // that's waiting on a search, where there's no HTTP stream to abort.
    final exchange = _currentExchange;
    if (exchange == null) return;
    exchange.cancel();
    exchange.service.cancelStream();
  }

  /// Stops the exchange in flight and detaches it from the provider: it
  /// winds down in the background, but its cleanup can no longer touch the
  /// streaming state (or service) of anything started after it.
  void _abandonExchange() {
    stopStreaming();
    _currentExchange = null;
    _streamingConversationId = null;
    _cancelPersistTimer();
  }

  void disconnectService() {
    // Tear down an in-flight generation with the service — otherwise the
    // orphaned stream keeps running against a conversation nobody shows.
    _abandonExchange();
    _activeConversation = null;
    _service = null;
    notifyListeners();
  }

  void clear() {
    _abandonExchange();
    _dropPendingUndo();
    _conversations.clear();
    _composers.clear();
    _activeConversation = null;
    _service = null;
    notifyListeners();
  }

  /// Wipes every conversation and the files behind them (including the
  /// backup, so history can't reappear through the corruption fallback).
  Future<void> deleteAllConversations() async {
    stopStreaming();
    _cancelPersistTimer();
    // "Delete all" is permanent — a pending undo must not bring one back.
    _dropPendingUndo();
    _conversations.clear();
    _composers.clear();
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
    _undoTimer?.cancel();
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
    try {
      await _storageService?.saveConversations(_conversations);
    } catch (e) {
      // Callers fire and forget, so a failed save (disk full, unwritable
      // path) would otherwise be an unhandled async error — once per second
      // while streaming. The next save simply tries again.
      debugPrint('Failed to save conversations: $e');
    }
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

/// One conversation's unsent message: typed text and staged attachments.
class _Composer {
  final List<String> images = [];
  String? fileName;
  String? fileBase64;
  String? fileMimeType;
  String text = '';

  void clearFile() {
    fileName = null;
    fileBase64 = null;
    fileMimeType = null;
  }
}

/// One send and everything it kicks off (the stream legs and tool calls).
class _Exchange {
  _Exchange(this.service, this.userMessage);

  /// Captured once: reconnecting mid-exchange must not swap the service
  /// under a running tool loop.
  final OllamaService service;
  final ChatMessage userMessage;

  /// Assistant and tool messages this exchange added to the chat, in order.
  final List<ChatMessage> appended = [];

  bool cancelled = false;
  final Completer<void> _cancelSignal = Completer<void>();

  /// Completes when the exchange is cancelled.
  Future<void> get whenCancelled => _cancelSignal.future;

  void cancel() {
    cancelled = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete();
  }

  void throwIfCancelled() {
    if (cancelled) throw const _ExchangeCancelled();
  }
}

/// Thrown inside an exchange once it has been stopped; handled by the same
/// recovery path as an aborted stream.
class _ExchangeCancelled implements Exception {
  const _ExchangeCancelled();

  @override
  String toString() => 'Cancelled';
}
