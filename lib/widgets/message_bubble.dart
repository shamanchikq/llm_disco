import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'code_block_builder.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;
  final VoidCallback? onRetry;

  /// Offered on long-press of user messages: edit the text and resend.
  final VoidCallback? onEdit;

  /// Offered on long-press of user messages: delete this message together
  /// with its response.
  final VoidCallback? onDelete;

  /// Model name shown in the assistant flag header.
  final String? modelName;

  /// Optional metadata line (e.g. "42.6 tok/s") under the last response.
  final String? metaLabel;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.onRetry,
    this.onEdit,
    this.onDelete,
    this.modelName,
    this.metaLabel,
  });

  /// The only link targets opened from model-controlled text: http(s) URLs
  /// with a host. `tel:`, `sms:`, `file:`, `intent:` and app deep links — and
  /// anything that doesn't even parse — are refused rather than launched.
  static Uri? safeLinkTarget(String? href) {
    if (href == null) return null;
    final uri = Uri.tryParse(href.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isError = message.isError;
    final theme = Theme.of(context);
    final msgColors = theme.extension<MessageColors>()!;
    final tokens = theme.extension<DiscoTokens>()!;

    if (isUser) {
      final bubble = GestureDetector(
          onLongPress: () => onEdit != null
              ? _showUserMessageOptions(context)
              : _copyToClipboard(context),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            margin: const EdgeInsets.only(top: 6, left: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: msgColors.userBubble,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(tokens.radius),
                topRight: Radius.circular(tokens.radius),
                bottomRight: const Radius.circular(7),
                bottomLeft: Radius.circular(tokens.radius),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.images != null && message.images!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final img in message.images!)
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: tokens.lineStrong),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _CachedBase64Image(
                              base64Data: img,
                              width:
                                  message.images!.length == 1 ? 180 : 110,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (message.files != null && message.files!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: message.files!.map((file) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _FileChip(
                            name: file['name'] ?? 'file',
                            tokens: tokens,
                            textColor: msgColors.userText,
                            accent: theme.colorScheme.primary,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                SelectableText(
                  message.content.isEmpty ? '...' : message.content,
                  style: TextStyle(
                    color: msgColors.userText,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        );

      // Visible action row so edit/copy are discoverable without
      // long-pressing (long-press still opens the options sheet).
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            bubble,
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MetaAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy',
                    color: tokens.textFaint,
                    onTap: () => _copyToClipboard(context),
                  ),
                  if (onEdit != null)
                    _MetaAction(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit & resend',
                      color: tokens.textFaint,
                      onTap: onEdit!,
                    ),
                  // The long-press sheet that also offers this loses to the
                  // SelectableText's own gestures, so surface it here.
                  if (onDelete != null)
                    _MetaAction(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete',
                      color: tokens.textFaint,
                      onTap: onDelete!,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Assistant or error message: full-width, flag header + content + meta
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flag header: glyph + model name
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(
                  Icons.view_in_ar_rounded,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  (modelName ?? 'Assistant').toUpperCase(),
                  style: AppTheme.mono(
                    fontSize: 10.5,
                    letterSpacing: 0.5,
                    color: tokens.textFaint,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (message.thinking != null && message.thinking!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ThinkingSection(thinking: message.thinking!),
            ),
          if (message.content.isEmpty)
            isStreaming
                ? const _TypingDots()
                : Text(
                    '...',
                    style: TextStyle(
                      color: msgColors.assistantText,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  )
          else if (isError)
            SelectableText(
              message.content,
              style: TextStyle(
                color: msgColors.errorText,
                fontSize: 15,
                height: 1.5,
              ),
            )
          else if (isStreaming)
            // Markdown re-rendered on a throttle (non-selectable to avoid
            // focus-node churn) with a blinking cursor at the tail.
            _StreamingMarkdown(
              content: message.content,
              styleSheet: _buildMarkdownStyle(theme, msgColors, tokens),
            )
          else
            MarkdownBody(
              data: message.content,
              selectable: true,
              builders: {'pre': CodeBlockBuilder()},
              imageBuilder: _markdownImagePlaceholder,
              onTapLink: (text, href, title) => _openLink(href),
              styleSheet: _buildMarkdownStyle(theme, msgColors, tokens),
            ),
          if (isError && onRetry != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: msgColors.errorRetry.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 14, color: msgColors.errorRetry),
                    const SizedBox(width: 4),
                    Text(
                      'Retry',
                      style: TextStyle(
                        color: msgColors.errorRetry,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // An empty response (e.g. a thinking model that ran out of budget)
          // still needs Retry; Copy only makes sense with text.
          if (!isError &&
              !isStreaming &&
              (message.content.isNotEmpty || onRetry != null)) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (metaLabel != null)
                  Text(
                    metaLabel!,
                    style:
                        AppTheme.mono(fontSize: 10.5, color: tokens.textFaint),
                  ),
                const Spacer(),
                if (message.content.isNotEmpty)
                  _MetaAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy',
                    color: tokens.textFaint,
                    onTap: () => _copyToClipboard(context),
                  ),
                if (onRetry != null)
                  _MetaAction(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Retry',
                    color: tokens.textFaint,
                    onTap: onRetry!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showUserMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(ctx);
                _copyToClipboard(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit & resend'),
              onTap: () {
                Navigator.pop(ctx);
                onEdit!();
              },
            ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete message & response'),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle(
      ThemeData theme, MessageColors msgColors, DiscoTokens tokens) {
    final textColor = msgColors.assistantText;
    return MarkdownStyleSheet(
      p: TextStyle(color: textColor, fontSize: 15, height: 1.62),
      h1: AppTheme.display(
          color: textColor, fontSize: 23, fontWeight: FontWeight.w600),
      h2: AppTheme.display(
          color: textColor, fontSize: 20, fontWeight: FontWeight.w600),
      h3: AppTheme.display(
          color: textColor, fontSize: 17, fontWeight: FontWeight.w600),
      h4: TextStyle(
          color: textColor, fontSize: 15.5, fontWeight: FontWeight.w600),
      h5: TextStyle(
          color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
      h6: TextStyle(
          color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
      code: AppTheme.mono(
        color: textColor,
        fontSize: 12.5,
      ).copyWith(backgroundColor: theme.colorScheme.surfaceContainerHigh),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tokens.line),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      blockquote: TextStyle(
          color: tokens.textMuted, fontSize: 15, fontStyle: FontStyle.italic),
      a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline),
      listBullet: TextStyle(color: theme.colorScheme.primary, fontSize: 15),
      tableHead: TextStyle(
          color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
      tableBody: TextStyle(color: textColor, fontSize: 14),
      tableBorder: TableBorder.all(color: tokens.line, width: 1),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.line, width: 1),
        ),
      ),
    );
  }
}

class _MetaAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _MetaAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 15,
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onTap,
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  final String name;
  final DiscoTokens tokens;
  final Color textColor;
  final Color accent;

  const _FileChip({
    required this.name,
    required this.tokens,
    required this.textColor,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.lineStrong),
        borderRadius: BorderRadius.circular(9),
        color: Colors.black.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.description_outlined, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              style: TextStyle(color: textColor, fontSize: 12.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CachedBase64Image extends StatefulWidget {
  final String base64Data;
  final double width;

  const _CachedBase64Image({required this.base64Data, required this.width});

  @override
  State<_CachedBase64Image> createState() => _CachedBase64ImageState();
}

class _CachedBase64ImageState extends State<_CachedBase64Image> {
  // Null when the stored data isn't valid base64 (imported or hand-edited
  // files) — shown as a broken-image icon instead of throwing in initState.
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.base64Data);
  }

  // List items are reused for different messages, so the decoded bytes must
  // follow the widget's data rather than being fixed at first build.
  @override
  void didUpdateWidget(_CachedBase64Image oldWidget) {
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
    if (bytes == null) return _BrokenImage(width: widget.width);
    return Image.memory(
      bytes,
      width: widget.width,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _BrokenImage(width: widget.width),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  final double width;

  const _BrokenImage({required this.width});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DiscoTokens>()!;
    return SizedBox(
      width: width,
      height: 64,
      child: Icon(Icons.broken_image_outlined, color: tokens.textFaint),
    );
  }
}

/// Stands in for every markdown image in model output. Fetching them would
/// let a reply (or an injected search snippet / attached file) make the
/// phone request an attacker's URL with no tap, leaking the IP and whatever
/// is in the query string — so only a label is shown, and the URL opens
/// through the same http(s)-only path as links.
Widget _markdownImagePlaceholder(Uri uri, String? title, String? alt) =>
    _ImagePlaceholder(uri: uri, alt: alt);

Future<void> _openLink(String? href) async {
  final target = MessageBubble.safeLinkTarget(href);
  if (target == null) return;
  try {
    await launchUrl(target, mode: LaunchMode.externalApplication);
  } on Exception {
    // No handler available / launch refused — nothing useful to surface.
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final Uri uri;
  final String? alt;

  const _ImagePlaceholder({required this.uri, required this.alt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DiscoTokens>()!;
    final altText = alt?.trim() ?? '';
    final label = altText.isNotEmpty
        ? altText
        : (uri.host.isNotEmpty ? uri.host : 'image');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openLink(uri.toString()),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 14, color: tokens.textFaint),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(fontSize: 12, color: tokens.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingSection extends StatefulWidget {
  final String thinking;

  const _ThinkingSection({required this.thinking});

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: tokens.textFaint,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Thinking',
                    style:
                        AppTheme.mono(fontSize: 12, color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 13),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.line)),
              ),
              child: SelectableText(
                widget.thinking,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Renders streaming markdown at most every [_tick] instead of on every
/// token, alternating a tail cursor so the response reads as live.
class _StreamingMarkdown extends StatefulWidget {
  final String content;
  final MarkdownStyleSheet styleSheet;

  const _StreamingMarkdown({
    required this.content,
    required this.styleSheet,
  });

  @override
  State<_StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<_StreamingMarkdown> {
  static const _tick = Duration(milliseconds: 250);
  late String _rendered;
  bool _cursorOn = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _rendered = widget.content;
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      setState(() {
        _rendered = widget.content;
        _cursorOn = !_cursorOn;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _cursorOn ? '$_rendered ▍' : _rendered;
    return MarkdownBody(
      data: data,
      selectable: false,
      builders: {'pre': CodeBlockBuilder()},
      imageBuilder: _markdownImagePlaceholder,
      styleSheet: widget.styleSheet,
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DiscoTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = (_controller.value - i * 0.167) % 1.0;
              final active = t >= 0 && t < 0.4;
              final phase = active ? (1 - (t / 0.4 - 0.5).abs() * 2) : 0.0;
              return Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                transform:
                    Matrix4.translationValues(0, -2.0 * phase, 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.textFaint
                      .withValues(alpha: 0.25 + 0.75 * phase),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
