import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final modelProvider = context.watch<ModelProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (modelProvider.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (modelProvider.models.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text('No models', style: theme.textTheme.bodySmall),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<String>(
        value: modelProvider.selectedModel,
        isDense: true,
        icon: Icon(
          Icons.expand_more_rounded,
          color: colors.primary,
          size: 20,
        ),
        dropdownColor: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        underline: const SizedBox(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurface,
        ),
        items: modelProvider.models
            .map((model) => DropdownMenuItem(
                  value: model,
                  child: Text(model, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (value) {
          if (value != null) {
            final service = context.read<ConnectionProvider>().service;
            modelProvider.selectModel(value, service: service);
          }
        },
      ),
    );
  }
}
