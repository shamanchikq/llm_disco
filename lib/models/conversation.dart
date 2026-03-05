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
  bool filesEnabled;
  double? temperature;
  int? topK;
  double? topP;
  double? repeatPenalty;
  int? seed;

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
    this.filesEnabled = false,
    this.temperature,
    this.topK,
    this.topP,
    this.repeatPenalty,
    this.seed,
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
      'filesEnabled': filesEnabled,
      if (temperature != null) 'temperature': temperature,
      if (topK != null) 'topK': topK,
      if (topP != null) 'topP': topP,
      if (repeatPenalty != null) 'repeatPenalty': repeatPenalty,
      if (seed != null) 'seed': seed,
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
      filesEnabled: json['filesEnabled'] as bool? ?? false,
      temperature: json['temperature'] as double?,
      topK: json['topK'] as int?,
      topP: json['topP'] as double?,
      repeatPenalty: json['repeatPenalty'] as double?,
      seed: json['seed'] as int?,
    );
  }
}
