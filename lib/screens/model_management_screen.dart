import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/model_capabilities.dart';
import '../models/ollama_search_result.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../theme/app_theme.dart';

/// Where a model's page lives on the web. Library models (`gemma3:4b`) are
/// under /library; community models (`user/model:tag`) sit directly under
/// ollama.com; Hugging Face pulls (`hf.co/org/repo:Q4_K_M`) belong on
/// huggingface.co. The tag is never part of the page address.
Uri modelPageUri(String modelName) {
  final base = modelName.split(':').first;
  for (final prefix in const ['hf.co/', 'huggingface.co/']) {
    if (base.startsWith(prefix)) {
      return Uri.https('huggingface.co', '/${base.substring(prefix.length)}');
    }
  }
  return base.contains('/')
      ? Uri.https('ollama.com', '/$base')
      : Uri.https('ollama.com', '/library/$base');
}

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

  /// Bumped per search so a slow earlier response can't overwrite a later one.
  int _searchSeq = 0;

  /// Query of the last search that finished successfully; lets an empty
  /// result say "No models found" instead of the pre-search hint.
  String? _completedQuery;

  bool _capabilityFetchScheduled = false;

  // Expandable card state
  int? _expandedIndex;
  List<ModelTag>? _curatedTags;
  List<ModelTag>? _allTags;
  bool _showAllTags = false;
  bool _isLoadingTags = false;
  bool _isLoadingAllTags = false;
  String? _tagsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  /// Capabilities are loaded lazily elsewhere, so a model that shows up while
  /// this screen is open (a finished pull, a refresh) has none yet. Fetch
  /// whatever is missing — except models that already failed, which wait for
  /// an explicit retry instead of being hammered on every rebuild.
  void _scheduleCapabilityFetch(ModelProvider modelProvider) {
    if (_capabilityFetchScheduled) return;
    bool needsFetch(String model) =>
        modelProvider.getCapabilities(model) == null &&
        !modelProvider.capabilitiesFailed(model);
    if (!modelProvider.models.any(needsFetch)) return;

    _capabilityFetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _capabilityFetchScheduled = false;
      if (!mounted) return;
      final service = context.read<ConnectionProvider>().service;
      if (service == null) return;
      for (final model in modelProvider.models.where(needsFetch)) {
        modelProvider.fetchCapabilities(service, model);
      }
    });
  }

  void _retryCapabilities(String model) {
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    context.read<ModelProvider>().retryCapabilities(service, model);
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

    final id = ++_searchSeq;
    setState(() {
      _isSearching = true;
      _searchError = null;
      _completedQuery = null;
      _expandedIndex = null;
      _curatedTags = null;
      _allTags = null;
      _showAllTags = false;
      _isLoadingAllTags = false;
      _tagsError = null;
    });

    try {
      final results = await service.searchOllamaCom(query);
      if (!mounted || id != _searchSeq) return;
      setState(() {
        _searchResults = results;
        _completedQuery = query;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted || id != _searchSeq) return;
      setState(() {
        _searchError = e.toString();
        _isSearching = false;
      });
    }
  }

  void _startPull(String name) {
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    context.read<ModelProvider>().pullModel(service, name);
    _showPullSheet();
  }

  void _showPullSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => const _PullSheet(),
    );
  }

  Future<void> _openModelPage(String modelName) async {
    try {
      await launchUrl(
        modelPageUri(modelName),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // No browser available / launch refused — nothing useful to show.
    }
  }

  void _toggleExpanded(int index) {
    if (_expandedIndex == index) {
      setState(() {
        _expandedIndex = null;
        _curatedTags = null;
        _allTags = null;
        _showAllTags = false;
        _isLoadingTags = false;
        _isLoadingAllTags = false;
        _tagsError = null;
      });
      return;
    }

    setState(() {
      _expandedIndex = index;
      _curatedTags = null;
      _allTags = null;
      _showAllTags = false;
      _isLoadingTags = true;
      _isLoadingAllTags = false;
      _tagsError = null;
    });

    _loadCuratedTags(index);
  }

  /// Whether card [index] is still expanded *for the model* [name]. The index
  /// alone isn't enough: a new search puts a different model at the same
  /// position, and a late response for the old one must not land on it.
  bool _isExpandedFor(int index, String name) =>
      _expandedIndex == index &&
      index < _searchResults.length &&
      _searchResults[index].name == name;

  Future<void> _loadCuratedTags(int index) async {
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    final name = _searchResults[index].name;

    try {
      final curated = await service.fetchCuratedModelTags(name);
      // If the overview page yields nothing (e.g. layout change), fall back
      // to the full tag list.
      List<ModelTag>? all;
      if (curated.isEmpty) {
        all = await service.fetchModelTagsFromWeb(name);
      }
      if (mounted && _isExpandedFor(index, name)) {
        setState(() {
          _curatedTags = curated.isEmpty ? null : curated;
          _allTags = all;
          _showAllTags = curated.isEmpty;
          _isLoadingTags = false;
        });
      }
    } catch (e) {
      if (mounted && _isExpandedFor(index, name)) {
        setState(() {
          _tagsError = e.toString();
          _isLoadingTags = false;
        });
      }
    }
  }

  Future<void> _toggleShowAllTags() async {
    if (_showAllTags) {
      setState(() => _showAllTags = false);
      return;
    }
    if (_allTags != null) {
      setState(() => _showAllTags = true);
      return;
    }
    final index = _expandedIndex;
    if (index == null) return;
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = _searchResults[index].name;

    setState(() => _isLoadingAllTags = true);
    try {
      final all = await service.fetchModelTagsFromWeb(name);
      if (mounted && _isExpandedFor(index, name)) {
        setState(() {
          _allTags = all;
          _showAllTags = true;
          _isLoadingAllTags = false;
        });
      }
    } catch (e) {
      if (mounted && _isExpandedFor(index, name)) {
        setState(() => _isLoadingAllTags = false);
        messenger
          ..clearSnackBars()
          ..showSnackBar(
              SnackBar(content: Text('Failed to load all versions: $e')));
      }
    }
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
    final tokens = theme.extension<DiscoTokens>()!;
    final modelProvider = context.watch<ModelProvider>();
    final modelCount = modelProvider.models.length;
    _scheduleCapabilityFetch(modelProvider);
    final baseUrl = context.watch<ConnectionProvider>().baseUrl;
    final host = baseUrl.replaceFirst(RegExp(r'^https?://'), '');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Models'),
            if (host.isNotEmpty) ...[
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tokens.good,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    host,
                    style: AppTheme.mono(
                      fontSize: 11,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontSize: 13.5),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Installed'),
                  const SizedBox(width: 5),
                  Text(
                    '$modelCount',
                    style: AppTheme.mono(
                      fontSize: 10.5,
                      color: tokens.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            const Tab(text: 'Discover'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInstalledTab(theme, colors, tokens, host),
          _buildDiscoverTab(theme, colors, tokens),
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
      // A manual refresh also retries failed capability loads, bypassing
      // their cooldown.
      if (modelProvider.capabilitiesFailed(model)) {
        modelProvider.retryCapabilities(service, model);
      } else {
        modelProvider.fetchCapabilities(service, model);
      }
    }
  }

  Widget _buildInstalledTab(
    ThemeData theme,
    ColorScheme colors,
    DiscoTokens tokens,
    String host,
  ) {
    final modelProvider = context.watch<ModelProvider>();
    final models = modelProvider.models;
    final error = modelProvider.error;

    // Same look as the pull-error banner in the Discover tab, plus Retry.
    final errorBanner = error == null
        ? null
        : Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            color: colors.error.withValues(alpha: 0.12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(color: colors.error, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _refreshInstalledModels,
                  style:
                      TextButton.styleFrom(foregroundColor: colors.error),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );

    final Widget list;
    if (models.isEmpty) {
      list = RefreshIndicator(
        onRefresh: _refreshInstalledModels,
        child: CustomScrollView(
          // Without this the pull gesture does nothing when the content
          // doesn't overflow — i.e. exactly in the empty state.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              child: Center(
                child: Text(
                  // With a failed load the list is unknown, not empty.
                  error == null
                      ? 'No models installed'
                      : 'Model list unavailable',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      list = RefreshIndicator(
        onRefresh: _refreshInstalledModels,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: models.length + 1,
          itemBuilder: (context, index) {
            if (index == models.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  host.isEmpty
                      ? '${models.length} models'
                      : '${models.length} models on $host',
                  textAlign: TextAlign.center,
                  style:
                      AppTheme.mono(fontSize: 11, color: tokens.textFaint),
                ),
              );
            }
            final name = models[index];
            final caps = modelProvider.getCapabilities(name);
            return InkWell(
              onTap: () => _openModelPage(name),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 15, vertical: 15),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: tokens.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: AppTheme.mono(
                              fontSize: 14,
                              color: colors.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          if (caps != null)
                            _CapabilityIcons(caps: caps)
                          else if (modelProvider.capabilitiesFailed(name))
                            _CapabilitiesRetry(
                              onTap: () => _retryCapabilities(name),
                            )
                          else
                            SizedBox(
                              height: 12,
                              width: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: tokens.textFaint,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 18, color: tokens.textFaint),
                      tooltip: 'Delete',
                      onPressed: () => _deleteModel(name),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    if (errorBanner == null) return list;
    return Column(
      children: [
        errorBanner,
        Expanded(child: list),
      ],
    );
  }

  Widget _buildDiscoverTab(
    ThemeData theme,
    ColorScheme colors,
    DiscoTokens tokens,
  ) {
    final modelProvider = context.watch<ModelProvider>();

    return Column(
      children: [
        // Pull progress banner (visible when sheet is dismissed)
        if (modelProvider.isPulling)
          InkWell(
            onTap: _showPullSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.line)),
                color: colors.surfaceContainer,
              ),
              child: Row(
                children: [
                  Icon(Icons.download_rounded,
                      size: 15, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pulling ${modelProvider.pullingModelName ?? '…'}',
                      style: AppTheme.mono(
                          fontSize: 12, color: colors.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    modelProvider.pullProgress != null
                        ? '${(modelProvider.pullProgress! * 100).toStringAsFixed(0)}%'
                        : '…',
                    style: AppTheme.mono(
                        fontSize: 11, color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
        if (modelProvider.pullError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: colors.error.withValues(alpha: 0.12),
            child: Text(
              modelProvider.pullError!,
              style: TextStyle(color: colors.error, fontSize: 13),
            ),
          ),
        if (!modelProvider.isPulling &&
            modelProvider.pullError == null &&
            modelProvider.pullStatus == 'Pull complete')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: tokens.good.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 16, color: tokens.good),
                const SizedBox(width: 8),
                Text(
                  'Model installed',
                  style: TextStyle(color: tokens.good, fontSize: 13),
                ),
              ],
            ),
          ),
        // Search + manual pull
        Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.line)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.line),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 17, color: tokens.textFaint),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search ollama.com…',
                          hintStyle: TextStyle(color: tokens.textFaint),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.line),
                      ),
                      child: TextField(
                        controller: _pullController,
                        enabled: !modelProvider.isPulling,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Model name (e.g. llama3)',
                          hintStyle: TextStyle(color: tokens.textFaint),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) {
                          final name = _pullController.text.trim();
                          if (name.isNotEmpty &&
                              !modelProvider.isPulling) {
                            _startPull(name);
                          }
                        },
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
            ],
          ),
        ),
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
                            _completedQuery != null
                                ? 'No models found for "$_completedQuery"'
                                : 'Search for models on ollama.com',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tokens.textFaint,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            return _buildDiscoverCard(
                              result,
                              index,
                              modelProvider.isPulling,
                              theme,
                              colors,
                              tokens,
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildDiscoverCard(
    OllamaSearchResult result,
    int index,
    bool isPulling,
    ThemeData theme,
    ColorScheme colors,
    DiscoTokens tokens,
  ) {
    final isExpanded = _expandedIndex == index;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  result.name,
                  style: AppTheme.mono(
                      fontSize: 14.5, color: colors.onSurface),
                ),
              ),
              GestureDetector(
                onTap: () => _openModelPage(result.name),
                child: Icon(Icons.open_in_new,
                    size: 15, color: tokens.textFaint),
              ),
            ],
          ),
          if (result.description != null &&
              result.description!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              result.description!,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: tokens.textMuted,
              ),
              maxLines: isExpanded ? 10 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (result.pullCount != null) ...[
            const SizedBox(height: 9),
            Text(
              '${result.pullCount} pulls',
              style: AppTheme.mono(fontSize: 10.5, color: tokens.textFaint),
            ),
          ],
          if (!isExpanded && result.tags.isNotEmpty) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result.tags
                  .take(5)
                  .map((tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(color: tokens.line),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tag,
                          style: AppTheme.mono(
                              fontSize: 11, color: tokens.textMuted),
                        ),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _toggleExpanded(index),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.chevron_right_rounded,
                  size: 15,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  isExpanded ? 'Hide' : 'Versions',
                  style: AppTheme.mono(
                      fontSize: 12.5, color: colors.primary),
                ),
              ],
            ),
          ),
          if (isExpanded)
            _buildExpandedTags(result, isPulling, theme, colors, tokens),
        ],
      ),
    );
  }

  Widget _buildExpandedTags(
    OllamaSearchResult result,
    bool isPulling,
    ThemeData theme,
    ColorScheme colors,
    DiscoTokens tokens,
  ) {
    if (_isLoadingTags) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_tagsError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Failed to load tags: $_tagsError',
          style: TextStyle(color: colors.error, fontSize: 13),
        ),
      );
    }

    final displayed = _showAllTags ? _allTags : _curatedTags;

    if (displayed == null || displayed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'No tags found',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.textFaint,
          ),
        ),
      );
    }

    Widget pill(ModelTag tag) => _VersionPill(
          name: tag.name,
          size: tag.size,
          enabled: !isPulling,
          onTap: () => _startPull('${result.name}:${tag.name}'),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_showAllTags) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: displayed.map(pill).toList(),
          ),
        ] else
          for (final entry in _groupTags(displayed).entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 7),
              child: Text(
                entry.key.toUpperCase(),
                style: AppTheme.mono(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  color: tokens.textFaint,
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entry.value.map(pill).toList(),
            ),
          ],
        // Toggle between the curated list and every quantization variant.
        // Hidden when the curated fetch came up empty (nothing to go back to).
        if (_curatedTags != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GestureDetector(
              onTap: _isLoadingAllTags ? null : _toggleShowAllTags,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoadingAllTags)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: colors.primary,
                      ),
                    )
                  else
                    Icon(
                      _showAllTags
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      size: 14,
                      color: colors.primary,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _showAllTags
                        ? 'Show fewer'
                        : 'All versions (incl. quantizations)',
                    style:
                        AppTheme.mono(fontSize: 12.5, color: colors.primary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Static "couldn't load" state for a model whose capability fetch failed —
/// tapping it retries.
class _CapabilitiesRetry extends StatelessWidget {
  final VoidCallback onTap;

  const _CapabilitiesRetry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DiscoTokens>()!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, size: 13, color: tokens.textFaint),
            const SizedBox(width: 5),
            Text(
              "couldn't load capabilities · tap to retry",
              style: AppTheme.mono(fontSize: 11, color: tokens.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityIcons extends StatelessWidget {
  final ModelCapabilities caps;

  const _CapabilityIcons({required this.caps});

  static const _order = [
    ('vision', Icons.remove_red_eye_outlined, 'Vision'),
    ('thinking', Icons.psychology_outlined, 'Thinking'),
    ('tools', Icons.build_outlined, 'Tools'),
    ('audio', Icons.graphic_eq_rounded, 'Audio'),
  ];

  bool _has(String key) {
    switch (key) {
      case 'vision':
        return caps.supportsVision;
      case 'thinking':
        return caps.supportsThinking;
      case 'tools':
        return caps.supportsTools;
      case 'audio':
        return caps.supportsAudio;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;
    final on = _order.where((e) => _has(e.$1)).toList();

    if (on.isEmpty) {
      return Text(
        'no chat capabilities',
        style: AppTheme.mono(fontSize: 11, color: tokens.textFaint),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: on.map((e) {
        return Container(
          width: 25,
          height: 25,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: Color.lerp(tokens.line, colors.primary, 0.4)!,
            ),
          ),
          child: Tooltip(
            message: e.$3,
            child: Icon(e.$2, size: 14, color: colors.primary),
          ),
        );
      }).toList(),
    );
  }
}

class _VersionPill extends StatelessWidget {
  final String name;
  final String? size;
  final bool enabled;
  final VoidCallback onTap;

  const _VersionPill({
    required this.name,
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;
    final fg = enabled ? tokens.textMuted : tokens.textFaint;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_rounded,
                size: 12, color: enabled ? colors.primary : fg),
            const SizedBox(width: 7),
            Text(name, style: AppTheme.mono(fontSize: 11, color: fg)),
            if (size != null) ...[
              const SizedBox(width: 7),
              Text(
                size!,
                style: AppTheme.mono(fontSize: 11, color: tokens.textFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet pull progress, per the redesign mockup. Binds to
/// [ModelProvider]; dismissing it keeps the pull running (the banner in the
/// Discover tab reopens it).
class _PullSheet extends StatelessWidget {
  const _PullSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;

    return Consumer<ModelProvider>(
      builder: (context, modelProvider, _) {
        final pulling = modelProvider.isPulling;
        final progress = modelProvider.pullProgress;
        final pct = progress != null
            ? '${(progress * 100).toStringAsFixed(0)}%'
            : '…';
        final failed = modelProvider.pullError != null;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.lineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  pulling
                      ? 'Pulling ${modelProvider.pullingModelName ?? ''}'
                      : failed
                          ? 'Pull failed'
                          : 'Pull complete',
                  style: AppTheme.mono(fontSize: 13, color: colors.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  failed
                      ? modelProvider.pullError!
                      : modelProvider.pullStatus,
                  style: AppTheme.mono(
                    fontSize: 11,
                    color: failed ? colors.error : tokens.textFaint,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pulling ? progress : (failed ? 0 : 1),
                    minHeight: 8,
                    backgroundColor: colors.surface,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      pulling ? 'downloading' : (failed ? 'error' : 'done'),
                      style: AppTheme.mono(
                          fontSize: 11, color: tokens.textMuted),
                    ),
                    Text(
                      pulling ? pct : (failed ? '—' : '100%'),
                      style: AppTheme.mono(
                          fontSize: 11, color: tokens.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Material(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (pulling) {
                        final service =
                            context.read<ConnectionProvider>().service;
                        if (service != null) {
                          context
                              .read<ModelProvider>()
                              .cancelPull(service);
                        }
                      }
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        border: Border.all(color: tokens.line),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        pulling ? 'Cancel download' : 'Done',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, color: colors.onSurface),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
