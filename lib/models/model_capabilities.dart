class ModelCapabilities {
  final bool supportsVision;
  final bool supportsThinking;
  final String? thinkingMode; // 'boolean' or 'levels'
  final bool supportsTools;
  final bool supportsFiles;

  const ModelCapabilities({
    this.supportsVision = false,
    this.supportsThinking = false,
    this.thinkingMode,
    this.supportsTools = false,
    this.supportsFiles = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'supportsVision': supportsVision,
      'supportsThinking': supportsThinking,
      'thinkingMode': thinkingMode,
      'supportsTools': supportsTools,
      'supportsFiles': supportsFiles,
    };
  }

  factory ModelCapabilities.fromJson(Map<String, dynamic> json) {
    return ModelCapabilities(
      supportsVision: json['supportsVision'] as bool? ?? false,
      supportsThinking: json['supportsThinking'] as bool? ?? false,
      thinkingMode: json['thinkingMode'] as String?,
      supportsTools: json['supportsTools'] as bool? ?? false,
      supportsFiles: json['supportsFiles'] as bool? ?? false,
    );
  }
}
