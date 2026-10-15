import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import '../theme/app_theme.dart';

class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent.trimRight();

    // Extract language from first <code class="language-xxx"> child
    String? language;
    if (element.children != null && element.children!.isNotEmpty) {
      final first = element.children!.first;
      if (first is md.Element &&
          first.tag == 'code' &&
          first.attributes['class'] != null) {
        final cls = first.attributes['class']!;
        if (cls.startsWith('language-')) {
          language = cls.substring(9);
        }
      }
    }

    return _CodeBlockWithCopy(code: code, language: language);
  }
}

class _CodeBlockWithCopy extends StatefulWidget {
  final String code;
  final String? language;

  const _CodeBlockWithCopy({required this.code, this.language});

  @override
  State<_CodeBlockWithCopy> createState() => _CodeBlockWithCopyState();
}

class _CodeBlockWithCopyState extends State<_CodeBlockWithCopy> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<DiscoTokens>()!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            // The copy button supplies the header's height (40 dp touch
            // target, up from 30; the header grows from 38 to 40).
            padding: const EdgeInsets.fromLTRB(11, 0, 4, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.line)),
            ),
            child: Row(
              children: [
                Text(
                  widget.language ?? 'code',
                  style: AppTheme.mono(fontSize: 11, color: tokens.textMuted),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copy,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textFaint,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy_rounded,
                    size: 13,
                    color: _copied ? colors.primary : tokens.textFaint,
                  ),
                  label: Text(
                    _copied ? 'Copied' : 'Copy',
                    style: AppTheme.mono(
                      fontSize: 11,
                      color: _copied ? colors.primary : tokens.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: SelectableText(
              widget.code,
              style: AppTheme.mono(
                fontSize: 12.5,
                height: 1.6,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
