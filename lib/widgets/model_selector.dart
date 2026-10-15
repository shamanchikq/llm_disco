import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/model_capabilities.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/model_provider.dart';
import '../theme/app_theme.dart';
import 'tap_target.dart';

/// Graphite bottom-sheet model picker shared by the sidebar footer and the
/// app bar's mid-chat model switcher. Shows capability badges for models
/// whose capabilities are already cached.
Future<void> showModelPickerSheet(
  BuildContext context, {
  required String? current,
  required ValueChanged<String> onSelected,
  String title = 'SELECT MODEL',
}) {
  final modelProvider = context.read<ModelProvider>();
  final models = modelProvider.models;
  if (models.isEmpty) return Future.value();
  final theme = Theme.of(context);
  final tokens = theme.extension<DiscoTokens>()!;

  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Text(
              title,
              style: AppTheme.mono(
                fontSize: 10.5,
                letterSpacing: 0.6,
                color: tokens.textFaint,
              ),
            ),
          ),
          for (final m in models)
            ListTile(
              dense: true,
              leading: Icon(
                m == current
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: m == current
                    ? theme.colorScheme.primary
                    : tokens.textFaint,
              ),
              title: Text(m, style: AppTheme.mono(fontSize: 13)),
              trailing: _CapabilityBadges(
                capabilities: modelProvider.getCapabilities(m),
                tokens: tokens,
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (m != current) onSelected(m);
              },
            ),
        ],
      ),
    ),
  );
}

/// The one "new chat" action behind the app bar's "+", the sidebar button
/// and the no-conversation empty state. Never invents a model: with none
/// selected it explains instead of creating a chat that can't answer. An
/// untouched active chat is reused rather than stacking up empty ones.
void startNewChat(BuildContext context) {
  final modelProvider = context.read<ModelProvider>();
  final connectionProvider = context.read<ConnectionProvider>();
  final chatProvider = context.read<ChatProvider>();
  final model = modelProvider.selectedModel;
  if (model == null) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text(
            'No model installed yet. Install one from Manage models first.'),
      ));
    return;
  }
  final active = chatProvider.activeConversation;
  if (active != null && active.messages.isEmpty) return;
  chatProvider.createConversation(model);
  final service = connectionProvider.service;
  if (service != null) {
    modelProvider.fetchCapabilities(service, model);
  }
}

class _CapabilityBadges extends StatelessWidget {
  final ModelCapabilities? capabilities;
  final DiscoTokens tokens;

  const _CapabilityBadges({required this.capabilities, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final caps = capabilities;
    if (caps == null) return const SizedBox.shrink();
    final icons = <IconData>[
      if (caps.supportsVision) Icons.visibility_outlined,
      if (caps.supportsThinking) Icons.psychology_outlined,
      if (caps.supportsTools) Icons.build_outlined,
      if (caps.supportsAudio) Icons.graphic_eq_rounded,
    ];
    if (icons.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final icon in icons)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(icon, size: 14, color: tokens.textFaint),
          ),
      ],
    );
  }
}

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key, this.compact = true});

  final bool compact;

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

    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      child: Semantics(
        button: true,
        hint: 'Select model',
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          onTap: () {
            final connectionProvider = context.read<ConnectionProvider>();
            final provider = context.read<ModelProvider>();
            showModelPickerSheet(
              context,
              current: provider.selectedModel,
              onSelected: (m) =>
                  provider.selectModel(m, service: connectionProvider.service),
            );
          },
          child: Container(
            // 48 dp touch height (the row was ~44).
            constraints: const BoxConstraints(minHeight: kTapTargetSize),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    modelProvider.selectedModel ?? '',
                    style: AppTheme.mono(
                      fontSize: compact ? 12 : 13,
                      color: colors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  color: colors.primary,
                  size: compact ? 20 : 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
