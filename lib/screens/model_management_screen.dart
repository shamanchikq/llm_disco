import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/model_capabilities.dart';
import '../models/ollama_search_result.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';

class ModelManagementScreen extends StatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  final _pullController = TextEditingController();
  List<OllamaSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  String? _pullingDescription;

  // Expandable card state
  int? _expandedIndex;
  List<ModelTag>? _expandedTags;
  bool _isLoadingTags = false;
  String? _tagsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final modelProvider = context.read<ModelProvider>();
      final service = context.read<ConnectionProvider>().service;
      if (service == null) return;
      for (final model in modelProvider.models) {
        modelProvider.fetchCapabilities(service, model);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _pullController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
      _expandedIndex = null;
      _expandedTags = null;
      _tagsError = null;
    });

    try {
      final results = await service.searchOllamaCom(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchError = e.toString();
        _isSearching = false;
      });
    }
  }

  void _startPull(String name, {String? description}) {
    setState(() => _pullingDescription = description);
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    context.read<ModelProvider>().pullModel(service, name);
  }

  void _openModelPage(String modelName) {
    // Strip the tag part (e.g. "gemma3:4b" -> "gemma3")
    final baseName = modelName.split(':').first;
    launchUrl(
      Uri.https('ollama.com', '/library/$baseName'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _toggleExpanded(int index) {
    if (_expandedIndex == index) {
      setState(() {
        _expandedIndex = null;
        _expandedTags = null;
        _isLoadingTags = false;
        _tagsError = null;
      });
      return;
    }

    setState(() {
      _expandedIndex = index;
      _expandedTags = null;
      _isLoadingTags = true;
      _tagsError = null;
    });

    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;

    service
        .fetchModelTagsFromWeb(_searchResults[index].name)
        .then((tags) {
      if (mounted && _expandedIndex == index) {
        setState(() {
          _expandedTags = tags;
          _isLoadingTags = false;
        });
      }
    }).catchError((e) {
      if (mounted && _expandedIndex == index) {
        setState(() {
          _tagsError = e.toString();
          _isLoadingTags = false;
        });
      }
    });
  }

  Map<String, List<ModelTag>> _groupTags(List<ModelTag> tags) {
    final groups = <String, List<ModelTag>>{};
    final sizePattern = RegExp(r'^(\d+(?:\.\d+)?[bmBM])');

    for (final tag in tags) {
      final match = sizePattern.firstMatch(tag.name);
      final group = match != null ? match.group(1)!.toUpperCase() : 'Other';
      groups.putIfAbsent(group, () => []).add(tag);
    }

    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'Other') return 1;
        if (b == 'Other') return -1;
        return _parseSizeToBytes(a).compareTo(_parseSizeToBytes(b));
      });

    return {for (final k in sortedKeys) k: groups[k]!};
  }

  double _parseSizeToBytes(String s) {
    final match = RegExp(r'([\d.]+)([bmBM])').firstMatch(s);
    if (match == null) return 0;
    final value = double.tryParse(match.group(1)!) ?? 0;
    final unit = match.group(2)!.toUpperCase();
    return unit == 'B' ? value * 1e9 : value * 1e6;
  }

  void _cancelPull() {
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    context.read<ModelProvider>().cancelPull(service);
  }

  Future<void> _deleteModel(String name) async {
    final service = context.read<ConnectionProvider>().service;
    final modelProvider = context.read<ModelProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (service == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await service.deleteModel(name);
      await modelProvider.fetchModels(service);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Deleted $name')));
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Models'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Installed'),
            Tab(text: 'Browse'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInstalledTab(theme, colors),
          _buildBrowseTab(theme, colors),
        ],
      ),
    );
  }

  Future<void> _refreshInstalledModels() async {
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    final modelProvider = context.read<ModelProvider>();
    await modelProvider.fetchModels(service);
    for (final model in modelProvider.models) {
      modelProvider.fetchCapabilities(service, model);
    }
  }

  Widget _buildInstalledTab(ThemeData theme, ColorScheme colors) {
    final modelProvider = context.watch<ModelProvider>();
    final models = modelProvider.models;

    if (models.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshInstalledModels,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No models installed',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshInstalledModels,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: models.length,
        itemBuilder: (context, index) {
          final name = models[index];
          final caps = modelProvider.getCapabilities(name);
          final chips = _buildCapabilityChips(caps, theme, colors);
          return ListTile(
            onTap: () => _openModelPage(name),
            title: Row(
              children: [
                Expanded(child: Text(name)),
                Icon(
                  Icons.open_in_new,
                  size: 16,
                  color: colors.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
            subtitle: caps == null
                ? const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  )
                : chips.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: chips,
                        ),
                      ),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: colors.error),
              onPressed: () => _deleteModel(name),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildCapabilityChips(
      ModelCapabilities? caps, ThemeData theme, ColorScheme colors) {
    if (caps == null) return [];
    final labels = <String>[
      if (caps.supportsVision) 'Vision',
      if (caps.supportsTools) 'Tools',
      if (caps.supportsThinking) 'Thinking',
      if (caps.supportsFiles) 'Files',
    ];
    return labels
        .map((label) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ))
        .toList();
  }

  Widget _buildBrowseTab(ThemeData theme, ColorScheme colors) {
    final modelProvider = context.watch<ModelProvider>();
    final installedSet =
        modelProvider.models.map((m) => m.split(':').first).toSet();

    return Column(
      children: [
        // Pull progress banner
        if (modelProvider.isPulling)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.download_rounded,
                        size: 16, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        modelProvider.pullingModelName ?? 'Downloading...',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (modelProvider.pullProgress != null)
                      Text(
                        '${(modelProvider.pullProgress! * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      child: TextButton(
                        onPressed: _cancelPull,
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
                if (_pullingDescription != null &&
                    _pullingDescription!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _pullingDescription!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: modelProvider.pullProgress,
                  borderRadius: BorderRadius.circular(4),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    modelProvider.pullStatus,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (modelProvider.pullError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: colors.errorContainer,
            child: Text(
              modelProvider.pullError!,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        if (!modelProvider.isPulling &&
            modelProvider.pullError == null &&
            modelProvider.pullStatus == 'Pull complete')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: colors.primaryContainer,
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: colors.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Model pulled successfully!',
                  style: TextStyle(color: colors.onPrimaryContainer),
                ),
              ],
            ),
          ),
        // Search field
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search ollama.com...',
              filled: true,
              fillColor: colors.surfaceContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _search,
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        // Manual pull row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pullController,
                  enabled: !modelProvider.isPulling,
                  decoration: InputDecoration(
                    hintText: 'Model name (e.g. llama3)',
                    filled: true,
                    fillColor: colors.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: modelProvider.isPulling
                    ? null
                    : () {
                        final name = _pullController.text.trim();
                        if (name.isNotEmpty) _startPull(name);
                      },
                child: const Text('Pull'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Search results
        Expanded(
          child: _isSearching
              ? const Center(child: CircularProgressIndicator())
              : _searchError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _searchError!,
                          style: TextStyle(color: colors.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _searchResults.isEmpty
                      ? Center(
                          child: Text(
                            'Search for models on ollama.com',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  colors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            final isInstalled =
                                installedSet.contains(result.name);
                            return _buildSearchResultCard(
                              result,
                              index,
                              isInstalled,
                              modelProvider.isPulling,
                              theme,
                              colors,
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildSearchResultCard(
    OllamaSearchResult result,
    int index,
    bool isInstalled,
    bool isPulling,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final isExpanded = _expandedIndex == index;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _toggleExpanded(index),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          result.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (result.pullCount != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '${result.pullCount} Pulls',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        tooltip: 'View on ollama.com',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _openModelPage(result.name),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  if (result.description != null &&
                      result.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      result.description!,
                      style: theme.textTheme.bodySmall,
                      maxLines: isExpanded ? 10 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (!isExpanded && result.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: result.tags
                          .take(5)
                          .map((tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tag,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(fontSize: 11),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded tag section
          if (isExpanded)
            _buildExpandedTags(result, isPulling, theme, colors),
        ],
      ),
    );
  }

  Widget _buildExpandedTags(
    OllamaSearchResult result,
    bool isPulling,
    ThemeData theme,
    ColorScheme colors,
  ) {
    if (_isLoadingTags) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_tagsError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Text(
          'Failed to load tags: $_tagsError',
          style: TextStyle(color: colors.error),
        ),
      );
    }

    if (_expandedTags == null || _expandedTags!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Text(
          'No tags found',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final grouped = _groupTags(_expandedTags!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(
                entry.key,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.value.map((tag) {
                final label = tag.size != null
                    ? '${tag.name}  (${tag.size})'
                    : tag.name;
                return FilledButton.tonal(
                  onPressed: isPulling
                      ? null
                      : () => _startPull(
                            '${result.name}:${tag.name}',
                            description: result.description,
                          ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  child: Text(label, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

