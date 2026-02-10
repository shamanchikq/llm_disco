class ChatMessage {
  final String role; // 'user', 'assistant', or 'tool'
  String content;
  final DateTime timestamp;
  List<String>? images; // base64-encoded
  String? thinking;
  List<Map<String, dynamic>>? toolCalls;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.images,
    this.thinking,
    this.toolCalls,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toApiMap() {
    final map = <String, dynamic>{
      'role': role,
      'content': content,
    };
    if (images != null && images!.isNotEmpty) {
      map['images'] = images;
    }
    return map;
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
    if (images != null) map['images'] = images;
    if (thinking != null) map['thinking'] = thinking;
    if (toolCalls != null) map['toolCalls'] = toolCalls;
    return map;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      images: (json['images'] as List<dynamic>?)?.cast<String>(),
      thinking: json['thinking'] as String?,
      toolCalls: (json['toolCalls'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}
