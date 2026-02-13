import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'code_block_builder.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;

  const MessageBubble({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isError = message.content.startsWith('[Error:');
    final msgColors = Theme.of(context).extension<MessageColors>()!;
    final theme = Theme.of(context);

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: message.content));
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
              ));
          },
          child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: const EdgeInsets.only(top: 4, bottom: 4, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: msgColors.userBubble,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.images != null && message.images!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(message.images!.first),
                      width: 200,
                      fit: BoxFit.cover,
                    ),
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
        ),
      );
    }

    // Assistant or error message — no visible bubble
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.88,
        ),
        margin: const EdgeInsets.only(top: 4, bottom: 4, right: 32),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 13,
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  'Assistant',
                  style: TextStyle(
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (message.content.isNotEmpty && !isError)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      icon: Icon(
                        Icons.copy_rounded,
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      ),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: message.content));
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(const SnackBar(
                            content: Text('Copied to clipboard'),
                            duration: Duration(seconds: 1),
                          ));
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (message.thinking != null && message.thinking!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ThinkingSection(thinking: message.thinking!),
              ),
            if (message.content.isEmpty)
              Text(
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
            else
              MarkdownBody(
                data: message.content,
                selectable: true,
                builders: {'pre': CodeBlockBuilder()},
                onTapLink: (text, href, title) {
                  if (href != null) {
                    launchUrl(Uri.parse(href));
                  }
                },
                styleSheet: _buildMarkdownStyle(theme, msgColors),
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
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle(
      ThemeData theme, MessageColors msgColors) {
    final textColor = msgColors.assistantText;
    return MarkdownStyleSheet(
      p: TextStyle(color: textColor, fontSize: 15, height: 1.5),
      h1: TextStyle(
          color: textColor, fontSize: 24, fontWeight: FontWeight.bold),
      h2: TextStyle(
          color: textColor, fontSize: 21, fontWeight: FontWeight.bold),
      h3: TextStyle(
          color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
      h4: TextStyle(
          color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
      h5: TextStyle(
          color: textColor, fontSize: 15, fontWeight: FontWeight.bold),
      h6: TextStyle(
          color: textColor, fontSize: 14, fontWeight: FontWeight.bold),
      code: TextStyle(
        color: textColor,
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        fontFamily: 'monospace',
        fontSize: 14,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      blockquote:
          TextStyle(color: textColor, fontSize: 15, fontStyle: FontStyle.italic),
      a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline),
      listBullet: TextStyle(color: textColor, fontSize: 15),
      tableHead: TextStyle(
          color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
      tableBody: TextStyle(color: textColor, fontSize: 14),
      tableBorder: TableBorder.all(
          color: theme.colorScheme.outlineVariant, width: 1),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
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

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: colors.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Thinking',
                    style: TextStyle(
                      color: colors.primary.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: colors.primary.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SelectableText(
                widget.thinking,
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
