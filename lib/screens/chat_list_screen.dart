import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../services/storage_service.dart';
import '../widgets/model_selector.dart';
import 'chat_screen.dart';
import 'connection_screen.dart';
import 'model_management_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Your Chats"),
        automaticallyImplyLeading: false,
        actions: [
          const ModelSelector(),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) =>
                _onMenuAction(context, value, chatProvider),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'export_all', child: Text('Export All Chats')),
              PopupMenuItem(
                  value: 'import', child: Text('Import Chats')),
              PopupMenuItem(
                  value: 'manage_models', child: Text('Manage Models')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnect',
            onPressed: () {
              context.read<ConnectionProvider>().disconnect();
              chatProvider.disconnectService();
              context.read<ModelProvider>().clear();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ConnectionScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final modelProvider = context.read<ModelProvider>();
          final connectionProvider = context.read<ConnectionProvider>();
          final model = modelProvider.selectedModel ?? 'llama3';
          chatProvider.createConversation(model);
          if (connectionProvider.service != null) {
            modelProvider.fetchCapabilities(
                connectionProvider.service!, model);
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: chatProvider.conversations.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 48,
                    color: colors.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No conversations yet',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap + to start chatting',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: chatProvider.conversations.length,
              itemBuilder: (context, index) {
                final conversation = chatProvider.conversations[index];
                final time = conversation.createdAt;
                final timeStr =
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ChatScreen()),
                        );
                      },
                      onLongPress: () {
                        _showConversationOptions(
                            context, chatProvider, conversation);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    conversation.title,
                                    style: theme.textTheme.bodyMedium?.copyWith(
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
                              style: theme.textTheme.bodySmall?.copyWith(
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
    );
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
          ],
        ),
      ),
    );
  }

  Future<void> _onMenuAction(
    BuildContext context,
    String action,
    ChatProvider chatProvider,
  ) async {
    final storage = StorageService();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    switch (action) {
      case 'export_all':
        if (chatProvider.conversations.isEmpty) {
          messenger.showSnackBar(
              const SnackBar(content: Text('No conversations to export')));
          return;
        }
        try {
          final file = await storage
              .exportAllConversations(chatProvider.conversations);
          await Share.shareXFiles([XFile(file.path)]);
        } catch (e) {
          messenger
              .showSnackBar(SnackBar(content: Text('Export failed: $e')));
        }
        break;
      case 'import':
        try {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['json'],
          );
          if (result == null || result.files.single.path == null) return;
          final imported =
              await storage.importConversations(result.files.single.path!);
          final count = chatProvider.importConversations(imported);
          messenger.showSnackBar(SnackBar(
              content: Text(count > 0
                  ? 'Imported $count conversation${count == 1 ? '' : 's'}'
                  : 'No new conversations to import')));
        } catch (e) {
          messenger
              .showSnackBar(SnackBar(content: Text('Import failed: $e')));
        }
        break;
      case 'manage_models':
        navigator.push(
            MaterialPageRoute(builder: (_) => const ModelManagementScreen()));
        break;
    }
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
