class ChatMessage {
  final String role; // 'user', 'assistant', or 'tool'
  String content;
  final DateTime timestamp;
  List<String>? images; // base64-encoded
  String? thinking;
  List<Map<String, dynamic>>? toolCalls;
  List<Map<String, String>>? files; // each: {name, data (base64), type (mime)}

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.images,
    this.thinking,
    this.toolCalls,
    this.files,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toApiMap() {
    final map = <String, dynamic>{
      'role': role,
      'content': content,
    };
    if (images != null && images!.isNotEmpty) {
      map['images'] = images;
    }
    if (files != null && files!.isNotEmpty) {
      map['files'] = files;
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
    if (files != null) map['files'] = files;
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
      files: (json['files'] as List<dynamic>?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList(),
    );
  }
}
