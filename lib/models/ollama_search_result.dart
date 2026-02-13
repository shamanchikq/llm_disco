class OllamaSearchResult {
  final String name;
  final String? description;
  final String? pullCount;
  final List<String> tags;

  const OllamaSearchResult({
    required this.name,
    this.description,
    this.pullCount,
    this.tags = const [],
  });
}
