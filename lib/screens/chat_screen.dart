import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  File? _pendingImageFile;
  bool _capabilitiesFetched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_capabilitiesFetched) {
      _capabilitiesFetched = true;
      _ensureCapabilities();
    }
  }

  void _ensureCapabilities() {
    final chatProvider = context.read<ChatProvider>();
    final modelProvider = context.read<ModelProvider>();
    final connectionProvider = context.read<ConnectionProvider>();
    final conv = chatProvider.activeConversation;
    if (conv != null &&
        connectionProvider.service != null &&
        modelProvider.getCapabilities(conv.model) == null) {
      modelProvider.fetchCapabilities(connectionProvider.service!, conv.model);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final modelProvider = context.watch<ModelProvider>();
    final conversation = chatProvider.activeConversation;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (conversation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Chat")),
        body: const Center(child: Text("No active conversation")),
      );
    }

    final caps = modelProvider.getCapabilities(conversation.model);
    final hasVision = caps?.supportsVision ?? false;
    final hasThinking = caps?.supportsThinking ?? false;
    final hasTools = caps?.supportsTools ?? false;
    final hasSearxng = chatProvider.searxngUrl != null;
    final showSearchChip = hasTools && hasSearxng;

    // Filter out tool role messages from display
    final messages =
        conversation.messages.where((m) => m.role != 'tool').toList();

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showRenameDialog(context, chatProvider, conversation),
          child: Text(conversation.title),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: 'Context size',
            onPressed: () => _showContextSizeDialog(context, conversation),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              conversation.model,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 40,
                          color: colors.primary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Start a conversation',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      final isLastMessage = index == 0;
                      final canSwipeRetry = isLastMessage &&
                          message.role == 'assistant' &&
                          !chatProvider.isStreaming &&
                          message.content.isNotEmpty &&
                          !message.content.startsWith('[Error:');
                      final bubble = MessageBubble(
                        message: message,
                        onRetry: isLastMessage &&
                                message.content.startsWith('[Error:')
                            ? () => chatProvider.retryLastMessage()
                            : null,
                      );
                      if (canSwipeRetry) {
                        return Dismissible(
                          key: ValueKey('retry-${message.timestamp}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) async {
                            chatProvider.retryLastMessage();
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
                      }
                      return bubble;
                    },
                  ),
          ),
          if (chatProvider.isStreaming) const LinearProgressIndicator(),
          if (!chatProvider.isStreaming && chatProvider.lastTokensPerSec != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${chatProvider.lastTokensPerSec!.toStringAsFixed(1)} tok/s',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: colors.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Image preview
                    if (_pendingImageFile != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _pendingImageFile!,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: _clearImage,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Feature toggles
                    if (hasThinking || showSearchChip)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            if (hasThinking) ...[
                              if (caps?.thinkingMode == 'levels')
                                _buildThinkingDropdown(
                                    conversation, colors, theme)
                              else
                                FilterChip(
                                  label: const Text('Think'),
                                  selected: conversation.thinkingEnabled,
                                  onSelected: (val) {
                                    setState(() {
                                      conversation.thinkingEnabled = val;
                                    });
                                  },
                                  avatar: Icon(
                                    Icons.psychology_outlined,
                                    size: 18,
                                    color: conversation.thinkingEnabled
                                        ? colors.onSecondaryContainer
                                        : colors.onSurface,
                                  ),
                                ),
                              const SizedBox(width: 8),
                            ],
                            if (showSearchChip)
                              FilterChip(
                                label: const Text('Search'),
                                selected: conversation.webSearchEnabled,
                                onSelected: (val) {
                                  setState(() {
                                    conversation.webSearchEnabled = val;
                                  });
                                },
                                avatar: Icon(
                                  Icons.travel_explore,
                                  size: 18,
                                  color: conversation.webSearchEnabled
                                      ? colors.onSecondaryContainer
                                      : colors.onSurface,
                                ),
                              ),
                          ],
                        ),
                      ),
                    // Input row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (hasVision)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Material(
                                color: colors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _pickImage,
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: colors.primary,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            maxLines: 4,
                            minLines: 1,
                            decoration: InputDecoration(
                              hintText: "Ask your model...",
                              filled: true,
                              fillColor: colors.surfaceContainer,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(chatProvider),
                          ),
                        ),
                        const SizedBox(width: 8),
                        chatProvider.isStreaming
                            ? SizedBox(
                                width: 40,
                                height: 40,
                                child: Material(
                                  color: colors.error.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => chatProvider.stopStreaming(),
                                    child: Icon(Icons.stop_rounded,
                                        color: colors.error, size: 22),
                                  ),
                                ),
                              )
                            : SizedBox(
                                width: 40,
                                height: 40,
                                child: Material(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _send(chatProvider),
                                    child: Icon(Icons.arrow_upward_rounded,
                                        color: colors.surface, size: 22),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingDropdown(
    dynamic conversation,
    ColorScheme colors,
    ThemeData theme,
  ) {
    final levels = ['off', 'low', 'medium', 'high'];
    final currentLevel = conversation.thinkingEnabled
        ? (conversation.thinkingLevel ?? 'medium')
        : 'off';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: conversation.thinkingEnabled
            ? colors.secondaryContainer
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 18,
            color: conversation.thinkingEnabled
                ? colors.onSecondaryContainer
                : colors.onSurface,
          ),
          const SizedBox(width: 4),
          DropdownButton<String>(
            value: currentLevel,
            isDense: true,
            underline: const SizedBox(),
            dropdownColor: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface,
            ),
            items: levels
                .map((l) => DropdownMenuItem(
                      value: l,
                      child: Text(l[0].toUpperCase() + l.substring(1)),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                if (value == 'off') {
                  conversation.thinkingEnabled = false;
                  conversation.thinkingLevel = null;
                } else {
                  conversation.thinkingEnabled = true;
                  conversation.thinkingLevel = value;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final chatProvider = context.read<ChatProvider>();
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;

    final bytes = await File(file.path).readAsBytes();
    final base64 = base64Encode(bytes);
    chatProvider.setPendingImage(base64);
    setState(() {
      _pendingImageFile = File(file.path);
    });
  }

  void _clearImage() {
    context.read<ChatProvider>().clearPendingImage();
    setState(() {
      _pendingImageFile = null;
    });
  }

  void _showRenameDialog(
    BuildContext context,
    ChatProvider chatProvider,
    dynamic conversation,
  ) {
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

  void _showContextSizeDialog(BuildContext context, dynamic conversation) {
    final controller = TextEditingController(
      text: conversation.numCtx?.toString() ?? '',
    );
    final presets = [2048, 4096, 8192, 16384, 32768, 65536, 131072];
    final presetLabels = ['2K', '4K', '8K', '16K', '32K', '64K', '128K'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Context Size'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tokens',
                  hintText: 'Default (model decides)',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(presets.length, (i) {
                  return ActionChip(
                    label: Text(presetLabels[i]),
                    onPressed: () {
                      controller.text = presets[i].toString();
                      setDialogState(() {});
                    },
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                setState(() {
                  if (text.isEmpty) {
                    conversation.numCtx = null;
                  } else {
                    final val = int.tryParse(text);
                    if (val != null && val > 0) {
                      conversation.numCtx = val;
                    }
                  }
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _send(ChatProvider chatProvider) {
    final text = _controller.text.trim();
    if (text.isEmpty || chatProvider.isStreaming) return;
    _controller.clear();
    setState(() {
      _pendingImageFile = null;
    });
    chatProvider.sendMessage(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
