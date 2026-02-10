import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import '../services/storage_service.dart';
import 'chat_list_screen.dart';

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
    final settings = await storage.loadConnectionSettings();
    if (settings != null && mounted) {
      setState(() {
        ipController.text = settings['ip'] as String? ?? '';
        portController.text = settings['port'] as String? ?? '11434';
        useHttp = settings['useHttp'] as bool? ?? true;
        searxngController.text = settings['searxngUrl'] as String? ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionProvider = context.watch<ConnectionProvider>();

    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 28),
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
              ],
            ),
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
        MaterialPageRoute(builder: (_) => const ChatListScreen()),
      );
    } else if (mounted && connectionProvider.error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(connectionProvider.error!)),
      );
    }
  }
}
