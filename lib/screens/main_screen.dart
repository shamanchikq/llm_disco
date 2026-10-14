import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/model_selector.dart';

/// A parsed Chat-settings field. [value] is null for an empty field ("use
/// the default"); [error] is set when the text can't be accepted.
class SettingParse<T extends num> {
  final T? value;
  final String? error;

  const SettingParse.value(this.value) : error = null;
  const SettingParse.invalid(String this.error) : value = null;
}

String _fmtLimit(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// Parses a decimal field. Comma decimals ("0,3") are accepted; non-finite
/// values ("NaN", "1e999") are rejected because they would make
/// `jsonEncode` throw and break saving every conversation.
SettingParse<double> parseDecimalSetting(
  String raw, {
  double? min,
  bool minExclusive = false,
  double? max,
}) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return const SettingParse.value(null);
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) {
    return const SettingParse.invalid('Enter a number');
  }
  final tooLow = min != null && (minExclusive ? v <= min : v < min);
  final tooHigh = max != null && v > max;
  if (tooLow || tooHigh) {
    final String message;
    if (min != null && max != null) {
      message = 'Must be between ${_fmtLimit(min)} and ${_fmtLimit(max)}';
    } else if (min != null) {
      message = minExclusive
          ? 'Must be greater than ${_fmtLimit(min)}'
          : 'Must be ${_fmtLimit(min)} or more';
    } else {
      message = 'Must be ${_fmtLimit(max!)} or less';
    }
    return SettingParse.invalid(message);
  }
  return SettingParse.value(v);
}

/// Parses a whole-number field; spaces and `_` are ignored ("8 192").
SettingParse<int> parseIntSetting(String raw, {int? min}) {
  final text = raw.replaceAll(RegExp(r'[\s_]'), '');
  if (text.isEmpty) return const SettingParse.value(null);
  final v = int.tryParse(text);
  if (v == null) return const SettingParse.invalid('Enter a whole number');
  if (min != null && v < min) {
    return SettingParse.invalid('Must be $min or more');
  }
  return SettingParse.value(v);
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _maybeEnsureCapabilities(
    String? conversationId,
    String? conversationModel,
    ModelProvider modelProvider,
    ConnectionProvider connectionProvider,
  ) {
    if (conversationId == null || conversationModel == null) return;
    if (connectionProvider.service == null) return;
    // Retry whenever capabilities are missing — fetchCapabilities dedupes
    // in-flight requests and applies a cooldown after failures.
    if (modelProvider.getCapabilities(conversationModel) == null) {
      modelProvider.fetchCapabilities(
          connectionProvider.service!, conversationModel);
    }
  }

  static String _fmtTokens(int n) {
    if (n < 1024) return '$n';
    final k = n / 1024;
    return k == k.roundToDouble() ? '${k.round()}K' : '${k.toStringAsFixed(1)}K';
  }

  String _ctxLabel(int? numCtx, int? used) {
    if (used != null && numCtx != null) {
      return '${_fmtTokens(used)} / ${_fmtTokens(numCtx)}';
    }
    if (used != null) return '${_fmtTokens(used)} used';
    if (numCtx != null) return '${_fmtTokens(numCtx)} ctx';
    return 'ctx';
  }

  @override
  Widget build(BuildContext context) {
    final modelProvider = context.watch<ModelProvider>();
    final connectionProvider = context.watch<ConnectionProvider>();
    final theme = Theme.of(context);
    final tokens = theme.extension<DiscoTokens>()!;

    final conversationId = context.select<ChatProvider, String?>(
      (p) => p.activeConversation?.id,
    );
    final conversationTitle = context.select<ChatProvider, String?>(
      (p) => p.activeConversation?.title,
    );
    final conversationModel = context.select<ChatProvider, String?>(
      (p) => p.activeConversation?.model,
    );
    final conversationCtx = context.select<ChatProvider, int?>(
      (p) => p.activeConversation?.numCtx,
    );
    final conversationCtxUsed = context.select<ChatProvider, int?>(
      (p) => p.activeConversation?.lastContextTokens,
    );

    _maybeEnsureCapabilities(
      conversationId,
      conversationModel,
      modelProvider,
      connectionProvider,
    );

    final hasConversation = conversationId != null;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const ChatSidebar(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        titleSpacing: 0,
        title: hasConversation
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final conv =
                          context.read<ChatProvider>().activeConversation;
                      if (conv != null) _showRenameDialog(context, conv);
                    },
                    child: Text(
                      conversationTitle!,
                      style: theme.appBarTheme.titleTextStyle
                          ?.copyWith(fontSize: 17),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 1),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final conv =
                          context.read<ChatProvider>().activeConversation;
                      if (conv != null) _showModelPicker(context, conv);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: tokens.good,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            conversationModel!,
                            style: AppTheme.mono(
                              fontSize: 11,
                              color: tokens.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 13,
                          color: tokens.textFaint,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const Text('LLM Disco'),
        actions: [
          if (hasConversation)
            GestureDetector(
              onTap: () {
                final conv =
                    context.read<ChatProvider>().activeConversation;
                if (conv != null) _showChatSettingsSheet(context, conv);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.line),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _ctxLabel(conversationCtx, conversationCtxUsed),
                  style:
                      AppTheme.mono(fontSize: 11, color: tokens.textMuted),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New chat',
            onPressed: () => startNewChat(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: const _ChatBody(),
    );
  }

  void _showRenameDialog(BuildContext context, Conversation conversation) {
    final chatProvider = context.read<ChatProvider>();
    final controller = TextEditingController(text: conversation.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Conversation title'),
          onSubmitted: (_) {
            chatProvider.renameConversation(
                conversation.id, controller.text);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              chatProvider.renameConversation(
                  conversation.id, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showModelPicker(BuildContext context, Conversation conversation) {
    final modelProvider = context.read<ModelProvider>();
    final connectionProvider = context.read<ConnectionProvider>();
    final chatProvider = context.read<ChatProvider>();
    showModelPickerSheet(
      context,
      title: 'SWITCH MODEL',
      current: conversation.model,
      onSelected: (m) {
        chatProvider.changeConversationModel(conversation.id, m);
        final service = connectionProvider.service;
        if (service != null) {
          modelProvider.fetchCapabilities(service, m);
        }
      },
    );
  }

  void _showChatSettingsSheet(BuildContext context, Conversation conversation) {
    final chatProvider = context.read<ChatProvider>();
    final systemController =
        TextEditingController(text: conversation.systemPrompt ?? '');
    final ctxController =
        TextEditingController(text: conversation.numCtx?.toString() ?? '');
    final tempController = TextEditingController(
        text: conversation.temperature?.toString() ?? '');
    final topPController =
        TextEditingController(text: conversation.topP?.toString() ?? '');
    final topKController =
        TextEditingController(text: conversation.topK?.toString() ?? '');
    final repeatController = TextEditingController(
        text: conversation.repeatPenalty?.toString() ?? '');
    final seedController =
        TextEditingController(text: conversation.seed?.toString() ?? '');
    const presets = [2048, 4096, 8192, 16384, 32768, 65536, 131072];
    const presetLabels = ['2K', '4K', '8K', '16K', '32K', '64K', '128K'];

    // Inline error per field id, shown until the field is edited again.
    final errors = <String, String?>{};

    final theme = Theme.of(context);
    final tokens = theme.extension<DiscoTokens>()!;

    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text.toUpperCase(),
            style: AppTheme.mono(
              fontSize: 10.5,
              letterSpacing: 0.6,
              color: tokens.textFaint,
            ),
          ),
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget numField(String id, TextEditingController c, String label,
                    {String hint = 'default'}) =>
                Expanded(
                  child: TextField(
                    controller: c,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (_) {
                      if (errors[id] != null) {
                        setSheetState(() => errors[id] = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: label,
                      hintText: hint,
                      errorText: errors[id],
                      isDense: true,
                    ),
                  ),
                );

            void save() {
              final ctxParse = parseIntSetting(ctxController.text, min: 1);
              final tempParse =
                  parseDecimalSetting(tempController.text, min: 0);
              final topPParse =
                  parseDecimalSetting(topPController.text, min: 0, max: 1);
              final topKParse = parseIntSetting(topKController.text, min: 1);
              final repeatParse = parseDecimalSetting(repeatController.text,
                  min: 0, minExclusive: true);
              final seedParse = parseIntSetting(seedController.text);

              // Nothing is written until every field is valid, so a bad
              // value can't be half-applied or silently reset to default.
              final found = <String, String?>{
                'ctx': ctxParse.error,
                'temp': tempParse.error,
                'topP': topPParse.error,
                'topK': topKParse.error,
                'repeat': repeatParse.error,
                'seed': seedParse.error,
              };
              if (found.values.any((e) => e != null)) {
                setSheetState(() => errors
                  ..clear()
                  ..addAll(found));
                return;
              }

              final system = systemController.text.trim();
              conversation.systemPrompt = system.isEmpty ? null : system;
              conversation.numCtx = ctxParse.value;
              conversation.temperature = tempParse.value;
              conversation.topP = topPParse.value;
              conversation.topK = topKParse.value;
              conversation.repeatPenalty = repeatParse.value;
              conversation.seed = seedParse.value;
              chatProvider.conversationSettingsChanged();
              Navigator.pop(ctx);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chat settings',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 18),
                  sectionLabel('System prompt'),
                  TextField(
                    controller: systemController,
                    minLines: 2,
                    maxLines: 5,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    decoration: const InputDecoration(
                      hintText: 'e.g. You are a concise assistant…',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 18),
                  sectionLabel('Context size'),
                  TextField(
                    controller: ctxController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    onChanged: (_) {
                      if (errors['ctx'] != null) {
                        setSheetState(() => errors['ctx'] = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Tokens',
                      hintText: 'Default (model decides)',
                      errorText: errors['ctx'],
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(presets.length, (i) {
                      return ActionChip(
                        label: Text(presetLabels[i]),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          ctxController.text = presets[i].toString();
                          errors['ctx'] = null;
                          setSheetState(() {});
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  sectionLabel('Sampling'),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    numField('temp', tempController, 'Temperature'),
                    const SizedBox(width: 10),
                    numField('topP', topPController, 'Top P'),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    numField('topK', topKController, 'Top K'),
                    const SizedBox(width: 10),
                    numField('repeat', repeatController, 'Repeat penalty'),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    numField('seed', seedController, 'Seed', hint: 'random'),
                    const SizedBox(width: 10),
                    const Expanded(child: SizedBox()),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Separated body widget that watches ChatProvider for streaming updates.
/// Isolates frequent streaming rebuilds from the parent Scaffold, preventing
/// the drawer's focus tree from being corrupted during generation.
class _ChatBody extends StatefulWidget {
  const _ChatBody();

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  final _scrollController = ScrollController();
  bool _showJumpToLatest = false;

  /// Conversation the list was last built for; the jump pill belongs to a
  /// scroll position, so it must not outlive a switch of conversation.
  String? _shownConversationId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      // Two positions are attached for a frame while the list is replaced
      // on a conversation switch; `offset` is only valid with exactly one.
      if (_scrollController.positions.length != 1) return;
      // With reverse: true, offset 0 is the newest message.
      final show = _scrollController.offset > 400;
      if (show != _showJumpToLatest) {
        setState(() => _showJumpToLatest = show);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static const _starters = [
    ('Explain a concept', 'Explain in simple terms: '),
    ('Summarize text', 'Summarize the following:\n\n'),
    ('Help me code', 'Write code that '),
  ];

  /// Whether [m] gets a bubble. Tool results never do. An assistant message
  /// that only carried a tool call is a leftover once the tool has run (it
  /// would sit above the answer as a permanent "…"), so it shows only while
  /// it is still the newest message — then it is the in-progress indicator.
  static bool _isListed(ChatMessage m, ChatMessage? newest) {
    if (m.role == 'tool') return false;
    final toolCallOnly = m.role == 'assistant' &&
        m.content.isEmpty &&
        (m.thinking == null || m.thinking!.isEmpty) &&
        m.toolCalls != null;
    return !toolCallOnly || identical(m, newest);
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;

    final conversation = chatProvider.activeConversation;
    if (conversation?.id != _shownConversationId) {
      _shownConversationId = conversation?.id;
      _showJumpToLatest = false;
    }
    final allMessages = conversation?.messages ?? const <ChatMessage>[];
    final newest = allMessages.isEmpty ? null : allMessages.last;
    final messages =
        allMessages.where((m) => _isListed(m, newest)).toList();

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.view_in_ar_rounded,
                          size: 24,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Start a conversation',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                      if (conversation == null) ...[
                        // No active chat means no input either — this is the
                        // only way forward besides the app bar's "+".
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: () => startNewChat(context),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('New chat'),
                        ),
                      ],
                      if (conversation != null) ...[
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final (label, template) in _starters)
                              ActionChip(
                                label: Text(label),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => context
                                    .read<ChatProvider>()
                                    .setDraft(template),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                )
              // A fresh subtree per conversation gives each its own scroll
              // position instead of inheriting the previous chat's offset.
              : KeyedSubtree(
                  key: ValueKey(conversation!.id),
                  child: Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        itemCount: messages.length,
                        // Items are keyed by message identity; this lets the
                        // list move their state when indices shift.
                        findChildIndexCallback: (key) {
                          if (key is! ObjectKey) return null;
                          final i = messages.indexWhere(
                              (m) => identical(m, key.value));
                          return i < 0 ? null : messages.length - 1 - i;
                        },
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          final isLastMessage = index == 0;
                          final isError = message.isError;
                          final isAssistant = message.role == 'assistant';
                          // Empty responses qualify too: Retry is the only
                          // way to regenerate one (error bubbles bring their
                          // own retry).
                          final canRetry = isLastMessage &&
                              isAssistant &&
                              !chatProvider.isAnyStreaming &&
                              !isError;
                          final isCurrentlyStreaming = isLastMessage &&
                              chatProvider.isStreaming &&
                              isAssistant;
                          final showMeta = isLastMessage &&
                              isAssistant &&
                              !chatProvider.isStreaming &&
                              chatProvider.lastTokensPerSec != null;
                          void retry() {
                            final caps = context
                                .read<ModelProvider>()
                                .getCapabilities(conversation.model);
                            chatProvider.retryLastMessage(capabilities: caps);
                          }

                          // Editing/deleting re-sends, so gate on any
                          // generation being in flight, not just this
                          // conversation's.
                          final canEdit = message.role == 'user' &&
                              !chatProvider.isAnyStreaming;
                          // The last assistant bubble is always wrapped (swipe
                          // disabled when it can't retry): swapping wrappers
                          // when streaming ends would remount the subtree and
                          // collapse an expanded Thinking section.
                          final wrapped = isLastMessage && isAssistant;
                          final itemKey = ObjectKey(message);
                          final bubble = MessageBubble(
                            key: wrapped ? null : itemKey,
                            message: message,
                            isStreaming: isCurrentlyStreaming,
                            modelName: conversation.model,
                            metaLabel: showMeta
                                ? '${chatProvider.lastTokensPerSec!.toStringAsFixed(1)} tok/s'
                                : null,
                            onRetry: ((isLastMessage && isError) || canRetry)
                                ? retry
                                : null,
                            onEdit: canEdit
                                ? () => _showEditDialog(
                                    context, conversation, message)
                                : null,
                            onDelete: canEdit
                                ? () => _confirmDeletePair(context, message)
                                : null,
                          );
                          if (!wrapped) return bubble;
                          return Dismissible(
                            key: itemKey,
                            direction: canRetry
                                ? DismissDirection.endToStart
                                : DismissDirection.none,
                            confirmDismiss: (_) async {
                              retry();
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh_rounded,
                                      color: colors.primary),
                                  const SizedBox(width: 4),
                                  Text('Retry',
                                      style: TextStyle(color: colors.primary)),
                                ],
                              ),
                            ),
                            child: bubble,
                          );
                        },
                      ),
                      // Jump back to the newest message after scrolling up
                      if (_showJumpToLatest)
                        Positioned(
                          right: 16,
                          bottom: 12,
                          child: Material(
                            color: colors.surfaceContainerHigh,
                            shape: CircleBorder(
                              side: BorderSide(color: tokens.lineStrong),
                            ),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _scrollController.animateTo(
                                0,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(9),
                                child: Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 18,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        if (chatProvider.isStreaming)
          const LinearProgressIndicator(minHeight: 2),
        const ChatInput(),
      ],
    );
  }

  void _confirmDeletePair(BuildContext context, ChatMessage message) {
    final chatProvider = context.read<ChatProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
            'This removes the message and the response it received.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              chatProvider.deleteMessagePair(message);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, Conversation conversation, ChatMessage message) {
    final chatProvider = context.read<ChatProvider>();
    final modelProvider = context.read<ModelProvider>();
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty) return;
              final caps =
                  modelProvider.getCapabilities(conversation.model);
              chatProvider.editAndResend(message, text, capabilities: caps);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
