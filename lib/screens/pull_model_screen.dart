import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';

class PullModelScreen extends StatefulWidget {
  const PullModelScreen({super.key});

  @override
  State<PullModelScreen> createState() => _PullModelScreenState();
}

class _PullModelScreenState extends State<PullModelScreen> {
  final _controller = TextEditingController();

  void _startPull() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    context.read<ModelProvider>().pullModel(service, name);
  }

  void _cancelPull() {
    final service = context.read<ConnectionProvider>().service;
    if (service == null) return;
    context.read<ModelProvider>().cancelPull(service);
  }

  @override
  Widget build(BuildContext context) {
    final modelProvider = context.watch<ModelProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pull Model')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              enabled: !modelProvider.isPulling,
              decoration: InputDecoration(
                labelText: 'Model name',
                hintText: 'e.g. llama3, mistral, gemma2',
                filled: true,
                fillColor: colors.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _startPull(),
            ),
            const SizedBox(height: 16),
            if (modelProvider.isPulling) ...[
              FilledButton.tonal(
                onPressed: _cancelPull,
                child: const Text('Cancel'),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: modelProvider.pullProgress,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                modelProvider.pullStatus,
                style: theme.textTheme.bodySmall,
              ),
              if (modelProvider.pullProgress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${(modelProvider.pullProgress! * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ] else ...[
              FilledButton(
                onPressed: _startPull,
                child: const Text('Pull Model'),
              ),
            ],
            if (modelProvider.pullError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  modelProvider.pullError!,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
            if (!modelProvider.isPulling &&
                modelProvider.pullError == null &&
                modelProvider.pullStatus == 'Pull complete') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: colors.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      'Model pulled successfully!',
                      style: TextStyle(color: colors.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
