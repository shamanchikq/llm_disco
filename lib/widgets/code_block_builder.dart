import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

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

    final theme = Theme.of(context);

    return _CodeBlockWithCopy(
      code: code,
      language: language,
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      textColor: theme.colorScheme.onSurface,
      labelColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
    );
  }
}

class _CodeBlockWithCopy extends StatefulWidget {
  final String code;
  final String? language;
  final Color backgroundColor;
  final Color textColor;
  final Color labelColor;

  const _CodeBlockWithCopy({
    required this.code,
    this.language,
    required this.backgroundColor,
    required this.textColor,
    required this.labelColor,
  });

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
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              widget.code,
              style: TextStyle(
                color: widget.textColor,
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.language != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    widget.language!,
                    style: TextStyle(
                      color: widget.labelColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy_rounded,
                    color: widget.labelColor,
                  ),
                  onPressed: _copy,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
