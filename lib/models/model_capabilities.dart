class ModelCapabilities {
  final bool supportsVision;
  final bool supportsThinking;
  final String? thinkingMode; // 'boolean' or 'levels'
  final bool supportsTools;

  const ModelCapabilities({
    this.supportsVision = false,
    this.supportsThinking = false,
    this.thinkingMode,
    this.supportsTools = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'supportsVision': supportsVision,
      'supportsThinking': supportsThinking,
      'thinkingMode': thinkingMode,
      'supportsTools': supportsTools,
    };
  }

  factory ModelCapabilities.fromJson(Map<String, dynamic> json) {
    return ModelCapabilities(
      supportsVision: json['supportsVision'] as bool? ?? false,
      supportsThinking: json['supportsThinking'] as bool? ?? false,
      thinkingMode: json['thinkingMode'] as String?,
      supportsTools: json['supportsTools'] as bool? ?? false,
    );
  }
}
