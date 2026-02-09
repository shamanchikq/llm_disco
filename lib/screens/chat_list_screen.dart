import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../widgets/model_selector.dart';
import 'chat_screen.dart';
import 'connection_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Your Chats"),
        automaticallyImplyLeading: false,
        actions: [
          const ModelSelector(),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnect',
            onPressed: () {
              context.read<ConnectionProvider>().disconnect();
              chatProvider.clear();
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
          final model = modelProvider.selectedModel ?? 'llama3';
          chatProvider.createConversation(model);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: chatProvider.conversations.isEmpty
          ? const Center(
              child: Text('No conversations yet.\nTap + to start chatting!',
                  textAlign: TextAlign.center),
            )
          : ListView.builder(
              itemCount: chatProvider.conversations.length,
              itemBuilder: (context, index) {
                final conversation = chatProvider.conversations[index];
                final time = conversation.createdAt;
                final timeStr =
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                return Dismissible(
                  key: Key(conversation.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    chatProvider.deleteConversation(conversation.id);
                  },
                  child: ListTile(
                    title: Text(conversation.title),
                    subtitle: Text('${conversation.model} - $timeStr'),
                    leading: const Icon(Icons.chat),
                    trailing: Text(
                      '${conversation.messages.length} msgs',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () {
                      chatProvider.setActiveConversation(conversation);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ChatScreen()),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
