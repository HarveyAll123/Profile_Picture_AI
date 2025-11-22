import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.variant = PrimaryButtonVariant.filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final PrimaryButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDisabled = onPressed == null || isLoading;
    final textColor = variant == PrimaryButtonVariant.filled
        ? colorScheme.onPrimary
        : colorScheme.primary;

    final buttonChild = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(textColor),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: textColor),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          );

    final gradient = LinearGradient(
      colors: variant == PrimaryButtonVariant.filled
          ? [
              colorScheme.primary
                  .withValues(alpha: isDisabled ? 0.5 : 1),
              colorScheme.primaryContainer
                  .withValues(alpha: isDisabled ? 0.4 : 0.9),
            ]
          : [
              colorScheme.primary.withValues(alpha: 0.12),
              colorScheme.primary.withValues(alpha: 0.05),
            ],
    );

    final tapHandler = isDisabled ? null : onPressed;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: variant == PrimaryButtonVariant.outlined
              ? colorScheme.primary.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
        boxShadow: variant == PrimaryButtonVariant.filled
            ? [
                BoxShadow(
                  color:
                      colorScheme.primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                )
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: buttonChild,
      ),
    );

    final button = InkWell(
      onTap: tapHandler,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );

    if (!expanded) {
      return button;
    }
    return SizedBox(width: double.infinity, child: button);
  }
}

enum PrimaryButtonVariant { filled, outlined }
