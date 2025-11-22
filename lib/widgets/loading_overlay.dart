import 'dart:async';

import 'package:flutter/material.dart';

class LoadingOverlay extends StatefulWidget {
  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = 'Processing...',
    this.onCancel,
    this.cancelDelay = const Duration(seconds: 15),
  });

  final bool isLoading;
  final Widget child;
  final String message;
  final VoidCallback? onCancel;
  final Duration cancelDelay;

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay> {
  Timer? _timer;
  bool _showCancelButton = false;

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(covariant LoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading != widget.isLoading ||
        oldWidget.onCancel != widget.onCancel) {
      _maybeStartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _maybeStartTimer() {
    _timer?.cancel();
    if (widget.isLoading && widget.onCancel != null) {
      if (widget.cancelDelay <= Duration.zero) {
        setState(() => _showCancelButton = true);
      } else {
        _timer = Timer(widget.cancelDelay, () {
          if (mounted && widget.isLoading) {
            setState(() => _showCancelButton = true);
          }
        });
      }
    } else {
      setState(() => _showCancelButton = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        widget.child,
        if (widget.isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        widget.message,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      if (_showCancelButton && widget.onCancel != null) ...[
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: widget.onCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
