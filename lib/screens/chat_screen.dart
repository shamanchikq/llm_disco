import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversation = chatProvider.activeConversation;

    if (conversation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Chat")),
        body: const Center(child: Text("No active conversation")),
      );
    }

    final messages = conversation.messages;

    return Scaffold(
      appBar: AppBar(
        title: Text(conversation.title),
        actions: [
          Text(
            conversation.model,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('Send a message to start chatting'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      final isLastMessage = index == 0;
                      return MessageBubble(
                        message: message,
                        onRetry: isLastMessage &&
                                message.content.startsWith('[Error:')
                            ? () => chatProvider.retryLastMessage()
                            : null,
                      );
                    },
                  ),
          ),
          if (chatProvider.isStreaming) const LinearProgressIndicator(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: "Ask your model...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
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
                      ? IconButton(
                          icon: const Icon(Icons.stop_circle,
                              color: Colors.red, size: 28),
                          onPressed: () => chatProvider.stopStreaming(),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () => _send(chatProvider),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _send(ChatProvider chatProvider) {
    final text = _controller.text.trim();
    if (text.isEmpty || chatProvider.isStreaming) return;
    _controller.clear();
    chatProvider.sendMessage(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
