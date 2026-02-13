import 'chat_message.dart';

class Conversation {
  final String id;
  String title;
  final String model;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  bool thinkingEnabled;
  String? thinkingLevel;
  bool webSearchEnabled;
  int? numCtx;

  Conversation({
    required this.id,
    required this.model,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    this.thinkingEnabled = false,
    this.thinkingLevel,
    this.webSearchEnabled = false,
    this.numCtx,
  })  : title = title ?? 'New Chat',
        messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'thinkingEnabled': thinkingEnabled,
      'thinkingLevel': thinkingLevel,
      'webSearchEnabled': webSearchEnabled,
      if (numCtx != null) 'numCtx': numCtx,
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      model: json['model'],
      title: json['title'],
      messages: (json['messages'] as List)
          .map((m) => ChatMessage.fromJson(m))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
      thinkingEnabled: json['thinkingEnabled'] as bool? ?? false,
      thinkingLevel: json['thinkingLevel'] as String?,
      webSearchEnabled: json['webSearchEnabled'] as bool? ?? false,
      numCtx: json['numCtx'] as int?,
    );
  }
}
