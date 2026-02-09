import 'chat_message.dart';

class Conversation {
  final String id;
  String title;
  final String model;
  final List<ChatMessage> messages;
  final DateTime createdAt;

  Conversation({
    required this.id,
    required this.model,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
  })  : title = title ?? 'New Chat',
        messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now();
}
