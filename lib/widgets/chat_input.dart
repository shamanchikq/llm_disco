import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import '../theme/app_theme.dart';

/// Runs a platform picker call, turning a failure (no camera, permission
/// denied, unreadable file) into a snackbar instead of an unhandled async
/// error. Returns null on failure.
Future<T?> guardPicker<T>(
  ScaffoldMessengerState messenger,
  String failureMessage,
  Future<T> Function() pick,
) async {
  try {
    return await pick();
  } on Exception {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(failureMessage)));
    return null;
  }
}

enum PickedFileStatus { cancelled, unreadable, ok }

/// Reads a picked file's bytes; null when it can't be read (revoked access,
/// vanished file).
Future<Uint8List?> readPickedFile(PlatformFile file) async {
  try {
    return await file.readAsBytes();
  } on Exception {
    return null;
  }
}

/// Tells a cancelled file picker (silent) apart from a chosen file whose
/// bytes could not be read (worth telling the user about).
PickedFileStatus classifyPickedFile(PlatformFile? file, Uint8List? bytes) {
  if (file == null) return PickedFileStatus.cancelled;
  return bytes == null ? PickedFileStatus.unreadable : PickedFileStatus.ok;
}

class ChatInput extends StatefulWidget {
  /// Overrides the image picker (tests); defaults to the platform one.
  final ImagePicker? imagePicker;

  const ChatInput({super.key, this.imagePicker});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final modelProvider = context.watch<ModelProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;

    final conversation = chatProvider.activeConversation;
    if (conversation == null) return const SizedBox.shrink();

    // Starter chips on the empty state pre-fill the input via a draft.
    final draft = chatProvider.takeDraft();
    if (draft != null) {
      _controller.text = draft;
      _controller.selection =
          TextSelection.collapsed(offset: draft.length);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusNode.requestFocus());
    }

    final caps = modelProvider.getCapabilities(conversation.model);
    final hasVision = caps?.supportsVision ?? false;
    final hasThinking = caps?.supportsThinking ?? false;
    // gpt-oss: effort levels only, can't be switched off
    final levelsOnly = caps?.thinkingMode == 'levels';
    final thinkingOn = levelsOnly || (conversation.thinkingEnabled ?? true);
    final hasTools = caps?.supportsTools ?? false;
    final hasSearxng = chatProvider.searxngUrl != null;
    final showSearchChip = hasTools && hasSearxng;
    // Another conversation is mid-generation; this one can't send yet.
    final busyElsewhere =
        chatProvider.isAnyStreaming && !chatProvider.isStreaming;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image previews (multi-attach)
              if (chatProvider.pendingImages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0;
                            i < chatProvider.pendingImages.length;
                            i++)
                          Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: tokens.lineStrong),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _ThumbImage(
                                  base64Data: chatProvider.pendingImages[i],
                                  size: 84,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () =>
                                      chatProvider.removePendingImageAt(i),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              // File preview
              if (chatProvider.pendingFileName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        border: Border.all(color: tokens.lineStrong),
                        borderRadius: BorderRadius.circular(9),
                        color: colors.surfaceContainer,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: tokens.accentSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(Icons.description_outlined,
                                size: 14, color: colors.primary),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              chatProvider.pendingFileName!,
                              style: TextStyle(
                                  color: colors.onSurface, fontSize: 12.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _clearFile,
                            child: Icon(Icons.close,
                                size: 16, color: tokens.textFaint),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Feature chips
              if (hasThinking || showSearchChip)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        if (hasThinking)
                          _FeatureChip(
                            icon: Icons.psychology_outlined,
                            label: 'Think',
                            active: thinkingOn,
                            level: thinkingOn
                                ? (conversation.thinkingLevel ??
                                    (levelsOnly ? 'medium' : 'auto'))
                                : null,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              if (levelsOnly) {
                                _cycleThinkingLevel(conversation, levelsOnly);
                              } else {
                                conversation.thinkingEnabled = !thinkingOn;
                                // Persisted like every other conversation
                                // setting, not just until the next rebuild.
                                context
                                    .read<ChatProvider>()
                                    .conversationSettingsChanged();
                              }
                            },
                            onLevelTap: () => _cycleThinkingLevel(
                                conversation, levelsOnly),
                          ),
                        if (showSearchChip)
                          _FeatureChip(
                            icon: Icons.public,
                            label: 'Search',
                            active: conversation.webSearchEnabled,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              conversation.webSearchEnabled =
                                  !conversation.webSearchEnabled;
                              context
                                  .read<ChatProvider>()
                                  .conversationSettingsChanged();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              // Input bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(tokens.radius),
                  border: Border.all(
                    color: _focusNode.hasFocus ? colors.primary : tokens.line,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(4, 5, 5, 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (hasVision)
                      _BarIconButton(
                        icon: Icons.image_outlined,
                        color: tokens.textMuted,
                        onTap: _pickImage,
                      ),
                    _BarIconButton(
                      icon: Icons.attach_file_rounded,
                      color: tokens.textMuted,
                      onTap: _pickFile,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: 4,
                        minLines: 1,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                        decoration: InputDecoration(
                          hintText: 'Message ${conversation.model}…',
                          // A long model name must not wrap the empty field
                          // to several lines.
                          hintMaxLines: 1,
                          hintStyle: TextStyle(
                            color: tokens.textFaint,
                            overflow: TextOverflow.ellipsis,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 10),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(chatProvider),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: Material(
                        // Dimmed while a different chat is generating —
                        // only one stream can run at a time.
                        color: busyElsewhere
                            ? colors.primary.withValues(alpha: 0.3)
                            : colors.primary,
                        borderRadius:
                            BorderRadius.circular(tokens.radius - 5),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(tokens.radius - 5),
                          onTap: chatProvider.isStreaming
                              ? () {
                                  HapticFeedback.lightImpact();
                                  chatProvider.stopStreaming();
                                }
                              : busyElsewhere
                                  ? null
                                  : () => _send(chatProvider),
                          child: Icon(
                            chatProvider.isStreaming
                                ? Icons.stop_rounded
                                : Icons.arrow_upward_rounded,
                            color: colors.onPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cycleThinkingLevel(Conversation conversation, bool levelsOnly) {
    if (levelsOnly) {
      // gpt-oss effort levels
      const order = ['low', 'medium', 'high'];
      final current = conversation.thinkingLevel ?? 'medium';
      conversation.thinkingLevel =
          order[(order.indexOf(current) + 1) % order.length];
    } else {
      // auto (server default) → explicit effort levels → back to auto
      const order = <String?>[null, 'low', 'medium', 'high', 'max'];
      final idx = order.indexOf(conversation.thinkingLevel);
      conversation.thinkingLevel = order[(idx + 1) % order.length];
    }
    // Persisted like every other conversation setting.
    context.read<ChatProvider>().conversationSettingsChanged();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo library'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final chatProvider = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (source == 'camera') {
      final encoded = await guardPicker<String?>(
        messenger,
        "Couldn't open the camera. Check that this device has one and that "
        'the app is allowed to use it.',
        () async {
          final file = await _picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 85,
          );
          if (file == null) return null; // cancelled
          return base64Encode(await file.readAsBytes());
        },
      );
      if (encoded != null) chatProvider.addPendingImage(encoded);
    } else {
      final encoded = await guardPicker<List<String>>(
        messenger,
        "Couldn't open the photo library. Check the app's photo permission "
        'and try again.',
        () async {
          final files = await _picker.pickMultiImage(
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 85,
          );
          return [
            for (final file in files) base64Encode(await file.readAsBytes()),
          ];
        },
      );
      for (final image in encoded ?? const <String>[]) {
        chatProvider.addPendingImage(image);
      }
    }
  }

  Future<void> _pickFile() async {
    final chatProvider = context.read<ChatProvider>();
    final modelProvider = context.read<ModelProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final conversation = chatProvider.activeConversation;

    final picked = await guardPicker<PlatformFile?>(
      messenger,
      "Couldn't open the file picker.",
      () => FilePicker.pickFile(),
    );
    final pickedBytes = picked == null ? null : await readPickedFile(picked);
    switch (classifyPickedFile(picked, pickedBytes)) {
      case PickedFileStatus.cancelled:
        return;
      case PickedFileStatus.unreadable:
        messenger
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text("Couldn't read that file"),
          ));
        return;
      case PickedFileStatus.ok:
        break;
    }
    final f = picked!;
    final bytes = pickedBytes!;

    if (_isImageExtension(f.extension)) {
      // Images go through Ollama's images field — vision models only.
      final caps = conversation != null
          ? modelProvider.getCapabilities(conversation.model)
          : null;
      if (!(caps?.supportsVision ?? false)) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('This model does not support images'),
          ));
        return;
      }
    } else {
      // Other files are inlined as text — reject binary formats the model
      // can't read (PDF, docx, executables, …).
      try {
        utf8.decode(bytes);
      } on FormatException {
        messenger
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Only plain-text files can be attached'),
          ));
        return;
      }
    }

    final encoded = base64Encode(bytes);
    final mime = _mimeFromExtension(f.extension);
    chatProvider.setPendingFile(f.name, encoded, mime);
  }

  static bool _isImageExtension(String? ext) {
    if (ext == null) return false;
    return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}
        .contains(ext.toLowerCase());
  }

  String _mimeFromExtension(String? ext) {
    if (ext == null) return 'application/octet-stream';
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'md':
        return 'text/markdown';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  void _clearFile() {
    context.read<ChatProvider>().clearPendingFile();
  }

  void _send(ChatProvider chatProvider) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // The keyboard's send action reaches here even while the send button
    // is dimmed for a generation in another chat. Bailing out BEFORE
    // clearing the field keeps the text; sendMessage would silently drop
    // it otherwise (one stream at a time, by design).
    if (chatProvider.isAnyStreaming) return;
    final conversation = chatProvider.activeConversation;
    final caps = conversation != null
        ? context.read<ModelProvider>().getCapabilities(conversation.model)
        : null;
    // Attachments outlive a mid-chat model switch, but the attach button
    // doesn't — don't ship images to a model that can't read them. Unknown
    // capabilities (fetch pending) don't block.
    final pendingFile = chatProvider.pendingFileName;
    final hasPendingImage = chatProvider.pendingImages.isNotEmpty ||
        (pendingFile != null &&
            pendingFile.contains('.') &&
            _isImageExtension(pendingFile.split('.').last));
    if (hasPendingImage && caps != null && !caps.supportsVision) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text("The current model can't read images. Remove the "
              'attached image or switch to a vision model.'),
        ));
      return;
    }
    HapticFeedback.lightImpact();
    _controller.clear();
    chatProvider.sendMessage(text, capabilities: caps);
  }
}

/// Decodes the base64 preview once instead of on every input rebuild.
class _ThumbImage extends StatefulWidget {
  final String base64Data;
  final double size;

  const _ThumbImage({required this.base64Data, required this.size});

  @override
  State<_ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends State<_ThumbImage> {
  // Null when the stored data isn't valid base64 — shown as a broken-image
  // icon rather than throwing from initState.
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.base64Data);
  }

  @override
  void didUpdateWidget(_ThumbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64Data != widget.base64Data) {
      _bytes = _decode(widget.base64Data);
    }
  }

  static Uint8List? _decode(String data) {
    try {
      return base64Decode(data);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return _BrokenThumb(size: widget.size);
    return Image.memory(
      bytes,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _BrokenThumb(size: widget.size),
    );
  }
}

class _BrokenThumb extends StatelessWidget {
  final double size;

  const _BrokenThumb({required this.size});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DiscoTokens>()!;
    return SizedBox(
      width: size,
      height: size,
      child: Icon(Icons.broken_image_outlined, color: tokens.textFaint),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final String? level;
  final VoidCallback onTap;
  final VoidCallback? onLevelTap;

  const _FeatureChip({
    required this.icon,
    required this.label,
    required this.active,
    this.level,
    required this.onTap,
    this.onLevelTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;
    final fg = active ? colors.primary : tokens.textMuted;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? colors.primary : tokens.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12.5, color: fg)),
            if (level != null) ...[
              const SizedBox(width: 7),
              GestureDetector(
                onTap: onLevelTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.only(left: 7),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: fg, width: 1)),
                  ),
                  child: Text(
                    level!.toUpperCase(),
                    style: AppTheme.mono(
                      fontSize: 9.5,
                      letterSpacing: 0.4,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BarIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
