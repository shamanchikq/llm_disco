import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import 'chat_list_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final ipController = TextEditingController();
  final portController = TextEditingController(text: "11434");
  bool useHttp = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionProvider = context.watch<ConnectionProvider>();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Connect to Ollama",
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: ipController,
                  decoration: InputDecoration(
                    labelText: "IP Address",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.network_wifi),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Port",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.settings_ethernet),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Use HTTP (instead of HTTPS)"),
                  value: useHttp,
                  onChanged: (value) => setState(() => useHttp = value),
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
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: connectionProvider.isConnecting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            "Connect",
                            style: TextStyle(fontSize: 16),
                          ),
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
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final success = await connectionProvider.connect(
      ip: ip,
      port: port,
      useHttp: useHttp,
    );

    if (success && mounted) {
      chatProvider.setService(connectionProvider.service!);
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
