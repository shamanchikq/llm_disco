import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/model_provider.dart';

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final modelProvider = context.watch<ModelProvider>();

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
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('No models found'),
      );
    }

    return DropdownButton<String>(
      value: modelProvider.selectedModel,
      items: modelProvider.models
          .map((model) => DropdownMenuItem(
                value: model,
                child: Text(model, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          modelProvider.selectModel(value);
        }
      },
      underline: const SizedBox(),
    );
  }
}
