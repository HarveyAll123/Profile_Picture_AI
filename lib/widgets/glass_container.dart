import 'dart:ui';

import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 28,
    this.tintColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final Color? tintColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = tintColor ?? Theme.of(context).colorScheme.surface;
    final strokeColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.08);

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor.withValues(alpha: isDark ? 0.35 : 0.65),
                baseColor.withValues(alpha: isDark ? 0.2 : 0.45),
              ],
            ),
            border: Border.all(color: strokeColor, width: 1),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(borderRadius),
      onTap: onTap,
      child: content,
    );
  }
}

