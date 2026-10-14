import 'dart:convert';

class ChatMessage {
  final String role; // 'user', 'assistant', or 'tool'
  String content;
  final DateTime timestamp;
  List<String>? images; // base64-encoded
  String? thinking;
  List<Map<String, dynamic>>? toolCalls;
  List<Map<String, String>>? files; // each: {name, data (base64), type (mime)}

  /// Marks a failed assistant turn — styled as an error and excluded from
  /// the history sent back to the model.
  bool isError;

  /// The model stopped because it hit its output length limit (Ollama's
  /// `done_reason: "length"`). Shown as a note on the bubble; never part of
  /// the content, so it isn't sent back to the model.
  bool cutOff;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.images,
    this.thinking,
    this.toolCalls,
    this.files,
    this.isError = false,
    this.cutOff = false,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toApiMap() {
    var apiContent = content;
    final apiImages = <String>[...?images];

    if (files != null && files!.isNotEmpty) {
      final textParts = <String>[];
      for (final file in files!) {
        final name = file['name'] ?? '';
        final data = file['data'] ?? '';

        if (_isImageExtension(name)) {
          apiImages.add(data);
        } else {
          try {
            final decoded = utf8.decode(base64Decode(data));
            textParts
                .add('--- File: $name ---\n$decoded\n--- End of file ---');
          } catch (_) {
            textParts.add(
                '[Attached file: $name (binary, cannot be displayed)]');
          }
        }
      }
      if (textParts.isNotEmpty) {
        apiContent = '${textParts.join('\n\n')}\n\n$apiContent';
      }
    }

    final map = <String, dynamic>{
      'role': role,
      'content': apiContent,
    };
    if (apiImages.isNotEmpty) {
      map['images'] = apiImages;
    }
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls;
    }
    return map;
  }

  static bool _isImageExtension(String name) {
    final ext = name.split('.').last.toLowerCase();
    return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext);
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
    if (isError) map['isError'] = true;
    if (cutOff) map['cutOff'] = true;
    return map;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final String role = json['role'];
    final String content = json['content'];
    return ChatMessage(
      role: role,
      content: content,
      timestamp: DateTime.parse(json['timestamp']),
      images: (json['images'] as List<dynamic>?)?.cast<String>(),
      thinking: json['thinking'] as String?,
      toolCalls: (json['toolCalls'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      files: (json['files'] as List<dynamic>?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList(),
      // Before the flag existed, errors were stored as assistant text with
      // this prefix; an explicit value in the JSON always wins.
      isError: json['isError'] as bool? ??
          (role == 'assistant' && content.startsWith('[Error:')),
      cutOff: json['cutOff'] as bool? ?? false,
    );
  }
}
