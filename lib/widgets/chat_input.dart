import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import '../theme/app_theme.dart';
import 'tap_target.dart';

/// Largest text file that can be attached from the file picker. Its contents
/// are inlined into the prompt, so a bigger one would overrun any context
/// window and bloat the saved history.
const int maxTextAttachmentBytes = 1024 * 1024;

/// Largest image file that can be attached from the file picker.
const int maxImageAttachmentBytes = 10 * 1024 * 1024;

/// Camera and gallery photos are scaled down to fit this box (and
/// re-encoded at [pickedImageQuality]) when picked: vision models shrink
/// images far below it anyway, and full-resolution photos would otherwise
/// ride along in every request and in the saved history.
const double maxPickedImageDimension = 1024;
const int pickedImageQuality = 85;

/// Snackbar text for a file over its limit.
String attachmentTooLargeMessage({required bool image}) {
  final limit = image ? maxImageAttachmentBytes : maxTextAttachmentBytes;
  return 'That file is too large — ${image ? 'image' : 'text'} attachments '
      'are limited to ${limit ~/ (1024 * 1024)} MB';
}

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

/// A picked file's size without reading its contents; null when the picker
/// can't tell.
Future<int?> pickedFileSize(PlatformFile file) async {
  final known = file.lengthSync();
  if (known != null) return known;
  try {
    return await file.length();
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

  /// Overrides the file picker (tests); defaults to the platform one.
  final Future<PlatformFile?> Function()? filePicker;

  const ChatInput({super.key, this.imagePicker, this.filePicker});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();

  /// Conversation whose remembered composer text the field is showing. The
  /// one controller serves every chat, so switching chats swaps its text.
  String? _fieldConversationId;

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

  /// Puts the text remembered for [id] into the field when the active
  /// conversation changed since the last build (half-typed text stays with
  /// its chat instead of following the user into another one).
  void _showComposerOf(ChatProvider chat, String? id) {
    if (id == _fieldConversationId) return;
    _fieldConversationId = id;
    final text = id == null ? '' : chat.composerTextFor(id);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final modelProvider = context.watch<ModelProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;

    final conversation = chatProvider.activeConversation;
    _showComposerOf(chatProvider, conversation?.id);
    if (conversation == null) return const SizedBox.shrink();

    // Starter chips on the empty state pre-fill the input via a draft.
    final draft = chatProvider.takeDraft();
    if (draft != null) {
      _controller.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
      chatProvider.setComposerText(conversation.id, draft);
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

    final hasChips = hasThinking || showSearchChip;
    final hasFile = chatProvider.pendingFileName != null;
    final hasPreviews = chatProvider.pendingImages.isNotEmpty || hasFile;
    // The chips' touch rows are 48 dp tall around a ~30 dp pill, so they bring
    // their own 9 dp of air; the usual gap is dropped on whichever side they
    // touch to keep the composer as tall as it was.
    final previewGap = hasChips ? 0.0 : 9.0;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              12, hasChips && !hasPreviews ? 0 : 9, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image previews (multi-attach)
              if (chatProvider.pendingImages.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: hasFile ? 9 : previewGap),
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
                              // The badge is 22 dp in the corner; its touch
                              // region reaches 48 dp into the thumbnail.
                              Positioned(
                                top: 0,
                                right: 0,
                                child: TapTarget(
                                  label: 'Remove image ${i + 1}',
                                  alignment: Alignment.topRight,
                                  onTap: () =>
                                      chatProvider.removePendingImageAt(i),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
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
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              // File preview
              if (hasFile)
                Padding(
                  padding: EdgeInsets.only(bottom: previewGap),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      // The remove button supplies the chip's height (48 dp
                      // touch target, up from a 40 dp chip) and right edge.
                      padding: const EdgeInsets.only(left: 10),
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
                          TapTarget(
                            label: 'Remove file',
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
              if (hasChips)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 7,
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
                          onLevelTap: () =>
                              _cycleThinkingLevel(conversation, levelsOnly),
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
              // Input bar. Its buttons are 48 dp touch targets with the
              // 38 dp visuals centered in them, so the old 5 dp padding now
              // lives inside their hit areas.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(tokens.radius),
                  border: Border.all(
                    color: _focusNode.hasFocus ? colors.primary : tokens.line,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (hasVision)
                      _BarIconButton(
                        icon: Icons.image_outlined,
                        tooltip: 'Attach image',
                        color: tokens.textMuted,
                        onTap: _pickImage,
                      ),
                    _BarIconButton(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'Attach file',
                      color: tokens.textMuted,
                      onTap: _pickFile,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
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
                            // 48 dp tall with one line, like the touch
                            // targets beside it.
                            constraints:
                                const BoxConstraints(minHeight: 48),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 1, vertical: 13.5),
                          ),
                          textAlignVertical: TextAlignVertical.center,
                          textInputAction: TextInputAction.send,
                          onChanged: (text) {
                            final id = _fieldConversationId;
                            if (id != null) {
                              chatProvider.setComposerText(id, text);
                            }
                          },
                          onSubmitted: (_) => _send(chatProvider),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: chatProvider.isStreaming
                          ? 'Stop generating'
                          : 'Send message',
                      iconSize: 20,
                      // Dimmed while a different chat is generating — only
                      // one stream can run at a time.
                      onPressed: chatProvider.isStreaming
                          ? () {
                              HapticFeedback.lightImpact();
                              chatProvider.stopStreaming();
                            }
                          : busyElsewhere
                              ? null
                              : () => _send(chatProvider),
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(38),
                        minimumSize: const Size.square(38),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.padded,
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        disabledBackgroundColor:
                            colors.primary.withValues(alpha: 0.3),
                        disabledForegroundColor: colors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(tokens.radius - 5),
                        ),
                      ),
                      icon: Icon(
                        chatProvider.isStreaming
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
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
            maxWidth: maxPickedImageDimension,
            maxHeight: maxPickedImageDimension,
            imageQuality: pickedImageQuality,
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
            maxWidth: maxPickedImageDimension,
            maxHeight: maxPickedImageDimension,
            imageQuality: pickedImageQuality,
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
      widget.filePicker ?? () => FilePicker.pickFile(),
    );
    if (picked == null) return; // cancelled, or already reported
    final isImage = _isImageExtension(picked.extension);
    final limit = isImage ? maxImageAttachmentBytes : maxTextAttachmentBytes;

    // Ask for the size before reading: loading a huge file into memory just
    // to refuse it would be the very problem the limit is there to avoid.
    final knownSize = await pickedFileSize(picked);
    if (knownSize != null && knownSize > limit) {
      _showTooLarge(messenger, image: isImage);
      return;
    }

    final pickedBytes = await readPickedFile(picked);
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
    final f = picked;
    final bytes = pickedBytes!;
    // The picker couldn't say how big it was; now we know.
    if (bytes.length > limit) {
      _showTooLarge(messenger, image: isImage);
      return;
    }

    if (isImage) {
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

  void _showTooLarge(ScaffoldMessengerState messenger,
      {required bool image}) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
          SnackBar(content: Text(attachmentTooLargeMessage(image: image))));
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
    if (conversation != null) chatProvider.setComposerText(conversation.id, '');
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

    // The pill stays ~30 dp tall; the 48 dp touch region around it is
    // transparent. The effort badge is a second, smaller touch target inside
    // the pill, so screen readers reach it as an action of the chip instead
    // of as a node too small to hit.
    return Semantics(
      button: true,
      selected: active,
      label: label,
      value: level,
      onTap: onTap,
      customSemanticsActions: {
        if (level != null && onLevelTap != null)
          const CustomSemanticsAction(label: 'Change thinking effort'):
              onLevelTap!,
      },
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            minWidth: kTapTargetSize, minHeight: kTapTargetSize),
        child: GestureDetector(
          onTap: onTap,
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.only(left: 11, right: level != null ? 0 : 11),
              decoration: BoxDecoration(
                color: active
                    ? colors.primary.withValues(alpha: 0.13)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: active ? colors.primary : tokens.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: fg),
                        const SizedBox(width: 6),
                        Text(label,
                            style: TextStyle(fontSize: 12.5, color: fg)),
                      ],
                    ),
                  ),
                  if (level != null)
                    GestureDetector(
                      onTap: onLevelTap,
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      // The padding is the badge's touch region: it runs to
                      // the pill's full height and right edge.
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 6, 11, 6),
                        child: Container(
                          padding: const EdgeInsets.only(left: 7),
                          decoration: BoxDecoration(
                            border:
                                Border(left: BorderSide(color: fg, width: 1)),
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
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 38 dp icon button inside a 48 dp touch target ([IconButton]'s padded
/// tap target keeps the visual and the layout separate).
class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      icon: Icon(icon, color: color),
      onPressed: onTap,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(38),
        minimumSize: const Size.square(38),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );
  }
}
