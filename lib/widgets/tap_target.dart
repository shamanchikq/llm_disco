import 'package:flutter/material.dart';

/// Smallest touch region Android's accessibility guidelines accept.
const double kTapTargetSize = 48;

/// Makes a gesture-only control (a pill, a badge, a bare icon) reachable for
/// screen readers and for imprecise fingers without changing how it looks:
/// [child] keeps its own size and sits at [alignment] inside a transparent
/// region of at least [minWidth] x [minHeight] that responds to taps.
///
/// Screen readers get one node announcing [label] (plus [value], e.g. the
/// current chat title) that activates [onTap]; whatever [child] would have
/// announced on its own is replaced by it.
class TapTarget extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final double minWidth;
  final double minHeight;
  final AlignmentGeometry alignment;
  final Widget child;

  const TapTarget({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.value,
    this.minWidth = kTapTargetSize,
    this.minHeight = kTapTargetSize,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      value: value,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, minHeight: minHeight),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onTap,
          child: Align(
            alignment: alignment,
            widthFactor: 1,
            heightFactor: 1,
            child: child,
          ),
        ),
      ),
    );
  }
}
