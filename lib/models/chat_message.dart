class ChatMessage {
  final String role; // 'user' or 'assistant'
  String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, String> toApiMap() {
    return {
      'role': role,
      'content': content,
    };
  }
}
