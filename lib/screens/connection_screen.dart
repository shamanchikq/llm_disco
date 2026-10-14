import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import '../services/ollama_service.dart';
import '../services/storage_service.dart';
import 'main_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, this.autoConnect = true});

  /// Attempt the saved connection automatically on first load. The sidebar's
  /// "Connection settings" passes false so an intentional disconnect doesn't
  /// bounce straight back.
  final bool autoConnect;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final ipController = TextEditingController();
  final portController = TextEditingController(text: "11434");
  final searxngController = TextEditingController();
  final authController = TextEditingController();
  bool useHttp = true;
  bool _settingsLoaded = false;

  /// True from the start of [_connect] until it navigates away or fails.
  /// `ConnectionProvider.isConnecting` alone isn't enough: it drops as soon
  /// as the probe returns, while this screen is still saving settings and
  /// loading models.
  bool _busy = false;
  List<Map<String, dynamic>> _savedConnections = [];

  @override
  void dispose() {
    ipController.dispose();
    portController.dispose();
    searxngController.dispose();
    authController.dispose();
    super.dispose();
  }

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
        authController.text = settings['authToken'] as String? ?? '';
      }
    });

    // Resume the last session without a manual tap; falls back to the form
    // (with the error shown) when the server isn't reachable.
    if (widget.autoConnect && ipController.text.trim().isNotEmpty) {
      await _connect(context);
    }
  }

  void _fillFromProfile(Map<String, dynamic> profile) {
    setState(() {
      ipController.text = profile['ip'] as String? ?? '';
      portController.text = profile['port'] as String? ?? '11434';
      useHttp = profile['useHttp'] as bool? ?? true;
      searxngController.text = profile['searxngUrl'] as String? ?? '';
      authController.text = profile['authToken'] as String? ?? '';
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

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _ProfileNameDialog(initialName: ip),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final storage = context.read<StorageService>();
    final searxng = searxngController.text.trim();
    final auth = authController.text.trim();
    final profile = <String, dynamic>{
      'name': name,
      'ip': ip,
      'port': portController.text.trim(),
      'useHttp': useHttp,
      if (searxng.isNotEmpty) 'searxngUrl': searxng,
      if (auth.isNotEmpty) 'authToken': auth,
    };
    setState(() {
      // Saving an existing name updates that profile instead of piling up
      // duplicates.
      _savedConnections.removeWhere((c) => c['name'] == name);
      _savedConnections.add(profile);
    });
    await storage.saveSavedConnections(_savedConnections);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionProvider = context.watch<ConnectionProvider>();
    final busy = connectionProvider.isConnecting || _busy;

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
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                      const SizedBox(height: 16),
                      TextField(
                        controller: authController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: "API key / Bearer token (optional)",
                          hintText: "For Ollama behind an auth proxy",
                          prefixIcon: Icon(Icons.key_outlined),
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
                          onPressed: busy ? null : () => _connect(context),
                          child: busy
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
    if (_busy) return;

    // Read the form once, up front. The probe can take seconds (and runs on
    // launch for auto-connect), during which the user may tap a profile chip
    // or edit a field — everything after the first await must use these
    // captured values, not the live controllers.
    final ip = ipController.text.trim();
    final port = portController.text.trim();
    final useHttp = this.useHttp;
    final searxngInput = searxngController.text.trim();
    final auth = authController.text.trim();

    final connectionProvider = context.read<ConnectionProvider>();
    final chatProvider = context.read<ChatProvider>();
    final modelProvider = context.read<ModelProvider>();
    final storage = context.read<StorageService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (ip.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please enter an IP address')),
      );
      return;
    }

    // A bad SearXNG URL would otherwise only fail later, inside a chat, as a
    // tool result the model paraphrases.
    String? searxng;
    if (searxngInput.isNotEmpty) {
      searxng = OllamaService.normalizeSearxngUrl(searxngInput);
      if (searxng == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
                'Enter a valid SearXNG URL, e.g. http://192.168.1.x:8080'),
          ),
        );
        return;
      }
    }

    setState(() => _busy = true);
    var navigated = false;
    try {
      final success = await connectionProvider.connect(
        ip: ip,
        port: port,
        useHttp: useHttp,
        authToken: auth,
      );
      if (!mounted) return;

      // Grab the service now: a later connect() could null it out.
      final service = connectionProvider.service;
      if (success && service != null) {
        await storage.saveConnectionSettings(
          ip: ip,
          port: port,
          useHttp: useHttp,
          searxngUrl: searxng,
          authToken: auth.isNotEmpty ? auth : null,
        );
        chatProvider.setService(service);
        chatProvider.setSearxngUrl(searxng);
        await modelProvider.fetchModels(service);

        if (!mounted) return;
        navigated = true;
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      } else if (connectionProvider.error != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(connectionProvider.error!)),
        );
      }
    } finally {
      // After navigating, stay busy: the old route lingers through its exit
      // transition and must not accept another tap.
      if (!navigated && mounted) setState(() => _busy = false);
    }
  }
}

/// Asks for a profile name. Owns its controller so it is disposed only once
/// the dialog route is really gone — disposing right after `showDialog`
/// returns races the dialog's exit animation.
class _ProfileNameDialog extends StatefulWidget {
  final String initialName;

  const _ProfileNameDialog({required this.initialName});

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save Connection'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Profile name'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _nameController.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
