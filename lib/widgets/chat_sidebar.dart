import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../screens/connection_screen.dart';
import '../screens/model_management_screen.dart';
import '../services/storage_service.dart';
import 'model_selector.dart';

class ChatSidebar extends StatelessWidget {
  const ChatSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: colors.primary),
                  const SizedBox(width: 10),
                  Text('LLM Disco', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.create_outlined),
                    tooltip: 'New chat',
                    onPressed: () => _createNewConversation(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Conversation list
            Expanded(
              child: chatProvider.conversations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: colors.primary.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No conversations yet',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      itemCount: chatProvider.conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = chatProvider.conversations[index];
                        final time = conversation.createdAt;
                        final timeStr =
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                        final isActive =
                            chatProvider.activeConversation?.id ==
                                conversation.id;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Dismissible(
                            key: Key(conversation.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              decoration: BoxDecoration(
                                color: colors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: Icon(Icons.delete_outline_rounded,
                                  color: colors.error),
                            ),
                            onDismissed: (_) {
                              chatProvider.deleteConversation(conversation.id);
                            },
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                chatProvider.setActiveConversation(conversation);
                                Navigator.pop(context);
                              },
                              onLongPress: () {
                                _showConversationOptions(
                                    context, chatProvider, conversation);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? colors.primaryContainer
                                          .withValues(alpha: 0.3)
                                      : colors.surfaceContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: colors.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.chat_rounded,
                                        size: 20,
                                        color: colors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            conversation.title,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${conversation.model} · $timeStr',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${conversation.messages.length}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Footer
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ModelSelector(compact: false),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _footerButton(
                    context: context,
                    icon: Icons.memory_rounded,
                    label: 'Models',
                    onPressed: () => _manageModels(context),
                  ),
                  _footerButton(
                    context: context,
                    icon: Icons.logout,
                    label: 'Disconnect',
                    onPressed: () => _disconnect(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _footerButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  void _createNewConversation(BuildContext context) {
    final modelProvider = context.read<ModelProvider>();
    final connectionProvider = context.read<ConnectionProvider>();
    final chatProvider = context.read<ChatProvider>();
    final model = modelProvider.selectedModel ?? 'llama3';
    chatProvider.createConversation(model);
    if (connectionProvider.service != null) {
      modelProvider.fetchCapabilities(connectionProvider.service!, model);
    }
    Navigator.pop(context);
  }

  void _manageModels(BuildContext context) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ModelManagementScreen()));
  }

  void _disconnect(BuildContext context) {
    final connectionProvider = context.read<ConnectionProvider>();
    final chatProvider = context.read<ChatProvider>();
    final modelProvider = context.read<ModelProvider>();
    connectionProvider.disconnect();
    chatProvider.disconnectService();
    modelProvider.clear();
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConnectionScreen()));
  }

  void _showConversationOptions(
    BuildContext context,
    ChatProvider chatProvider,
    dynamic conversation,
  ) {
    final storage = StorageService();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, chatProvider, conversation);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('Export'),
              onTap: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final file =
                      await storage.exportConversation(conversation);
                  await Share.shareXFiles([XFile(file.path)]);
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text('Export failed: $e')));
                }
              },
            ),
            ListTile(
              leading: Icon(conversation.filesEnabled
                  ? Icons.block_rounded
                  : Icons.attach_file_rounded),
              title: Text(conversation.filesEnabled
                  ? 'Disable File Upload'
                  : 'Enable File Upload'),
              onTap: () {
                Navigator.pop(ctx);
                chatProvider.toggleFilesEnabled(conversation.id);
              },
            ),
          ],
        ),
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
}
