import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import '../services/storage_service.dart';
import 'main_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final ipController = TextEditingController();
  final portController = TextEditingController(text: "11434");
  final searxngController = TextEditingController();
  bool useHttp = true;
  bool _settingsLoaded = false;
  List<Map<String, dynamic>> _savedConnections = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_settingsLoaded) {
      _settingsLoaded = true;
      _loadSavedSettings();
    }
  }

  Future<void> _loadSavedSettings() async {
    final storage = context.read<StorageService>();
    final results = await Future.wait([
      storage.loadConnectionSettings(),
      storage.loadSavedConnections(),
    ]);
    if (!mounted) return;
    final settings = results[0] as Map<String, dynamic>?;
    final saved = results[1] as List<Map<String, dynamic>>;
    setState(() {
      _savedConnections = saved;
      if (settings != null) {
        ipController.text = settings['ip'] as String? ?? '';
        portController.text = settings['port'] as String? ?? '11434';
        useHttp = settings['useHttp'] as bool? ?? true;
        searxngController.text = settings['searxngUrl'] as String? ?? '';
      }
    });
  }

  void _fillFromProfile(Map<String, dynamic> profile) {
    setState(() {
      ipController.text = profile['ip'] as String? ?? '';
      portController.text = profile['port'] as String? ?? '11434';
      useHttp = profile['useHttp'] as bool? ?? true;
      searxngController.text = profile['searxngUrl'] as String? ?? '';
    });
  }

  Future<void> _deleteProfile(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text(
          'Remove "${_savedConnections[index]['name']}"?',
        ),
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
    if (confirmed == true && mounted) {
      final storage = context.read<StorageService>();
      setState(() => _savedConnections.removeAt(index));
      await storage.saveSavedConnections(_savedConnections);
    }
  }

  Future<void> _saveProfile() async {
    final ip = ipController.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in connection details first')),
      );
      return;
    }

    final nameController = TextEditingController(text: ip);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Connection'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Profile name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final storage = context.read<StorageService>();
    final searxng = searxngController.text.trim();
    final profile = <String, dynamic>{
      'name': name,
      'ip': ip,
      'port': portController.text.trim(),
      'useHttp': useHttp,
      if (searxng.isNotEmpty) 'searxngUrl': searxng,
    };
    setState(() => _savedConnections.add(profile));
    await storage.saveSavedConnections(_savedConnections);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionProvider = context.watch<ConnectionProvider>();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_savedConnections.isNotEmpty) ...[
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _savedConnections.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final profile = _savedConnections[i];
                      return GestureDetector(
                        onLongPress: () => _deleteProfile(i),
                        child: ActionChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 18),
                          label: Text(profile['name'] as String),
                          onPressed: () => _fillFromProfile(profile),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.hub_outlined,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Connect to Ollama",
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: ipController,
                        decoration: const InputDecoration(
                          labelText: "IP Address",
                          prefixIcon: Icon(Icons.network_wifi),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Port",
                          prefixIcon: Icon(Icons.settings_ethernet),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Use HTTP (instead of HTTPS)"),
                        value: useHttp,
                        onChanged: (value) => setState(() => useHttp = value),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: searxngController,
                        decoration: const InputDecoration(
                          labelText: "SearXNG URL (optional)",
                          hintText: "http://192.168.1.x:8080",
                          prefixIcon: Icon(Icons.travel_explore),
                        ),
                      ),
                      if (connectionProvider.error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          connectionProvider.error!,
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: connectionProvider.isConnecting
                              ? null
                              : () => _connect(context),
                          child: connectionProvider.isConnecting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text("Connect"),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _saveProfile,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text("Save Connection"),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connect(BuildContext context) async {
    final ip = ipController.text.trim();
    final port = portController.text.trim();

    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an IP address')),
      );
      return;
    }

    final connectionProvider = context.read<ConnectionProvider>();
    final chatProvider = context.read<ChatProvider>();
    final modelProvider = context.read<ModelProvider>();
    final storage = context.read<StorageService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final success = await connectionProvider.connect(
      ip: ip,
      port: port,
      useHttp: useHttp,
    );

    if (success && mounted) {
      final searxng = searxngController.text.trim();
      await storage.saveConnectionSettings(
        ip: ip,
        port: port,
        useHttp: useHttp,
        searxngUrl: searxng.isNotEmpty ? searxng : null,
      );
      chatProvider.setService(connectionProvider.service!);
      chatProvider.setSearxngUrl(searxng.isNotEmpty ? searxng : null);
      await modelProvider.fetchModels(connectionProvider.service!);

      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else if (mounted && connectionProvider.error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(connectionProvider.error!)),
      );
    }
  }
}
