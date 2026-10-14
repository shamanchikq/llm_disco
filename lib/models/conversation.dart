import 'chat_message.dart';

class Conversation {
  final String id;
  String title;

  /// Mutable so a chat can be moved to a different installed model.
  String model;
  final List<ChatMessage> messages;
  final DateTime createdAt;

  /// null = user never chose — thinking-capable models default to on,
  /// matching Ollama's own default. true/false = explicit user choice.
  bool? thinkingEnabled;
  String? thinkingLevel;
  bool webSearchEnabled;
  String? systemPrompt;
  int? numCtx;
  double? temperature;
  int? topK;
  double? topP;
  double? repeatPenalty;
  int? seed;

  /// Context tokens consumed by the last exchange
  /// (prompt_eval_count + eval_count from the final stream event).
  int? lastContextTokens;

  /// Generation speed of the last response. Session-only (not persisted) —
  /// it describes a run, not the conversation.
  double? lastTokensPerSec;

  Conversation({
    required this.id,
    required this.model,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    this.thinkingEnabled,
    this.thinkingLevel,
    this.webSearchEnabled = false,
    this.systemPrompt,
    this.numCtx,
    this.temperature,
    this.topK,
    this.topP,
    this.repeatPenalty,
    this.seed,
    this.lastContextTokens,
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
      if (thinkingEnabled != null) 'thinkingEnabled': thinkingEnabled,
      'thinkingLevel': thinkingLevel,
      'webSearchEnabled': webSearchEnabled,
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
      if (numCtx != null) 'numCtx': numCtx,
      if (lastContextTokens != null) 'lastContextTokens': lastContextTokens,
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
      thinkingEnabled: json['thinkingEnabled'] as bool?,
      thinkingLevel: json['thinkingLevel'] as String?,
      webSearchEnabled: json['webSearchEnabled'] as bool? ?? false,
      systemPrompt: json['systemPrompt'] as String?,
      // num?-based: an int in stored/imported JSON (e.g. "temperature": 1)
      // must degrade to a double, not throw and fail the whole file.
      numCtx: (json['numCtx'] as num?)?.toInt(),
      lastContextTokens: (json['lastContextTokens'] as num?)?.toInt(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      topK: (json['topK'] as num?)?.toInt(),
      topP: (json['topP'] as num?)?.toDouble(),
      repeatPenalty: (json['repeatPenalty'] as num?)?.toDouble(),
      seed: (json['seed'] as num?)?.toInt(),
    );
  }
}
