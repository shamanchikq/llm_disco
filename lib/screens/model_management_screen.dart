import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

  void _startPull(String name) {
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    context.read<ModelProvider>().pullModel(service, name);
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

  Widget _buildInstalledTab(ThemeData theme, ColorScheme colors) {
    final modelProvider = context.watch<ModelProvider>();
    final models = modelProvider.models;

    if (models.isEmpty) {
      return Center(
        child: Text(
          'No models installed',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: models.length,
      itemBuilder: (context, index) {
        final name = models[index];
        return ListTile(
          title: Text(name),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline, color: colors.error),
            onPressed: () => _deleteModel(name),
          ),
        );
      },
    );
  }

  Widget _buildBrowseTab(ThemeData theme, ColorScheme colors) {
    final modelProvider = context.watch<ModelProvider>();
    final installedSet = modelProvider.models.map((m) => m.split(':').first).toSet();

    return Column(
      children: [
        // Pull progress banner
        if (modelProvider.isPulling)
          Container(
            padding: const EdgeInsets.all(12),
            color: colors.surfaceContainerHigh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        modelProvider.pullStatus,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (modelProvider.pullProgress != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '${(modelProvider.pullProgress! * 100).toStringAsFixed(1)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
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
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: modelProvider.pullProgress,
                  borderRadius: BorderRadius.circular(4),
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                              color: colors.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            final isInstalled = installedSet.contains(result.name);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
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
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (result.pullCount != null)
                                          Text(
                                            '${result.pullCount} Pulls',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colors.onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (result.description != null &&
                                        result.description!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        result.description!,
                                        style: theme.textTheme.bodySmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    if (result.tags.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: result.tags
                                            .take(5)
                                            .map((tag) => Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: colors
                                                        .surfaceContainerHigh,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    tag,
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ))
                                            .toList(),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.tonal(
                                        onPressed: modelProvider.isPulling
                                            ? null
                                            : () =>
                                                _startPull(result.name),
                                        child: Text(
                                            isInstalled ? 'Update' : 'Pull'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
