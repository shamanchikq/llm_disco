import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/message_bubble.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _lastCapabilityConvId;

  void _maybeEnsureCapabilities(
    ChatProvider chatProvider,
    ModelProvider modelProvider,
    ConnectionProvider connectionProvider,
  ) {
    final conv = chatProvider.activeConversation;
    if (conv == null) return;
    if (_lastCapabilityConvId == conv.id) return;
    if (connectionProvider.service == null) return;
    _lastCapabilityConvId = conv.id;
    if (modelProvider.getCapabilities(conv.model) == null) {
      modelProvider.fetchCapabilities(connectionProvider.service!, conv.model);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final modelProvider = context.watch<ModelProvider>();
    final connectionProvider = context.watch<ConnectionProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    _maybeEnsureCapabilities(chatProvider, modelProvider, connectionProvider);

    final conversation = chatProvider.activeConversation;
    final messages = conversation == null
        ? []
        : conversation.messages.where((m) => m.role != 'tool').toList();

    return Scaffold(
      key: _scaffoldKey,
      drawer: const ChatSidebar(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: conversation != null
            ? GestureDetector(
                onTap: () =>
                    _showRenameDialog(context, chatProvider, conversation),
                child: Text(conversation.title),
              )
            : const Text('LLM Disco'),
        actions: [
          if (conversation != null) ...[
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
          ],
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
          if (!chatProvider.isStreaming &&
              chatProvider.lastTokensPerSec != null)
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
          const ChatInput(),
        ],
      ),
    );
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
}
