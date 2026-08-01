class ModelCapabilities {
  final bool supportsVision;
  final bool supportsThinking;

  /// 'levels' — effort selector, always on (gpt-oss);
  /// 'toggle' — on/off switch with optional effort level (all other
  /// thinking-capable models).
  final String? thinkingMode;
  final bool supportsTools;
  final bool supportsAudio;

  const ModelCapabilities({
    this.supportsVision = false,
    this.supportsThinking = false,
    this.thinkingMode,
    this.supportsTools = false,
    this.supportsAudio = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'supportsVision': supportsVision,
      'supportsThinking': supportsThinking,
      'thinkingMode': thinkingMode,
      'supportsTools': supportsTools,
      'supportsAudio': supportsAudio,
    };
  }

  factory ModelCapabilities.fromJson(Map<String, dynamic> json) {
    return ModelCapabilities(
      supportsVision: json['supportsVision'] as bool? ?? false,
      supportsThinking: json['supportsThinking'] as bool? ?? false,
      thinkingMode: json['thinkingMode'] as String?,
      supportsTools: json['supportsTools'] as bool? ?? false,
      supportsAudio: json['supportsAudio'] as bool? ?? false,
    );
  }
}
