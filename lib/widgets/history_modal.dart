import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../models/generation_result.dart';
import '../providers/results_provider.dart';
import '../services/image_service.dart';

class HistoryModal extends ConsumerStatefulWidget {
  const HistoryModal({super.key});

  @override
  ConsumerState<HistoryModal> createState() => _HistoryModalState();
}

class _HistoryModalState extends ConsumerState<HistoryModal> {
  String? _fullScreenImageUrl;

  bool get _canPop => _fullScreenImageUrl == null;

  void _showFullScreenImage(String imageUrl, List<GenerationResult> results) {
    final imageUrls = results.map((r) => r.imageUrl).toList();
    final initialIndex = imageUrls.indexOf(imageUrl);

    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _FullScreenImageOverlay(
              imageUrls: imageUrls,
              initialIndex: initialIndex >= 0 ? initialIndex : 0,
              onClose: () => Navigator.of(context, rootNavigator: true).pop(),
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(resultsProvider);

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_fullScreenImageUrl != null) {
          setState(() {
            _fullScreenImageUrl = null;
          });
          return;
        }
      },
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'History',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: resultsAsync.when(
                      data: (results) {
                        if (results.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(
                              child: Text(
                                'No generated images yet',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          );
                        }
                        return ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            overscroll: false,
                            physics: const ClampingScrollPhysics(),
                          ),
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            shrinkWrap: true,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.8,
                                ),
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final result = results[index];
                              return _HistoryImageCard(
                                result: result,
                                onTap: () {
                                  _showFullScreenImage(
                                    result.imageUrl,
                                    results,
                                  );
                                },
                              );
                            },
                          ),
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'Error loading history: $error',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenImageOverlay extends StatefulWidget {
  const _FullScreenImageOverlay({
    required this.imageUrls,
    required this.initialIndex,
    required this.onClose,
  });

  final List<String> imageUrls;
  final int initialIndex;
  final VoidCallback onClose;

  @override
  State<_FullScreenImageOverlay> createState() =>
      _FullScreenImageOverlayState();
}

class _FullScreenImageOverlayState extends State<_FullScreenImageOverlay>
    with TickerProviderStateMixin {
  late final List<TransformationController> _transformationControllers;
  late final AnimationController _fadeController;
  late final AnimationController _zoomController;
  late final PageController _pageController;
  late final List<bool> _isZoomedStates;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformationControllers = List.generate(
      widget.imageUrls.length,
      (index) => TransformationController(),
    );
    _isZoomedStates = List.generate(widget.imageUrls.length, (index) => false);

    // Add listeners to all controllers
    for (int i = 0; i < _transformationControllers.length; i++) {
      _transformationControllers[i].addListener(() {
        final isZoomed =
            _transformationControllers[i].value.getMaxScaleOnAxis() > 1.0;
        if (isZoomed != _isZoomedStates[i]) {
          setState(() {
            _isZoomedStates[i] = isZoomed;
          });
        }
      });
    }

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    for (final controller in _transformationControllers) {
      controller.dispose();
    }
    _fadeController.dispose();
    _zoomController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  bool get _isZoomed => _isZoomedStates[_currentIndex];

  TransformationController get _currentTransformationController =>
      _transformationControllers[_currentIndex];

  void _resetZoom() {
    // Stop any ongoing animation first
    _zoomController.stop();
    _zoomController.reset();

    // Capture the exact current transformation at this moment
    final controller = _currentTransformationController;
    final currentValue = Matrix4.copy(controller.value);
    final targetValue = Matrix4.identity();

    // Set the current value immediately to ensure we start from the exact position
    controller.value = currentValue;

    final animation = Matrix4Tween(begin: currentValue, end: targetValue)
        .animate(
          CurvedAnimation(parent: _zoomController, curve: Curves.easeInOut),
        );

    animation.addListener(() {
      if (_zoomController.isAnimating) {
        controller.value = animation.value;
      }
    });

    _zoomController.forward().then((_) {
      controller.value = targetValue;
    });
  }

  void _handleDoubleTap(TapDownDetails details, int index) {
    final controller = _transformationControllers[index];
    final currentScale = controller.value.getMaxScaleOnAxis();
    final isZoomed = currentScale > 1.0;

    // Stop any ongoing animation
    _zoomController.stop();
    _zoomController.reset();

    final screenSize = MediaQuery.of(context).size;
    final focalPoint = details.localPosition;

    Matrix4 targetMatrix;
    if (isZoomed) {
      // Zoom out to identity
      targetMatrix = Matrix4.identity();
    } else {
      // Zoom in to 2.5x at the tap location
      final scale = 2.5;
      final centerX = screenSize.width / 2;
      final centerY = screenSize.height / 2;

      final translateToCenter = Matrix4.translationValues(centerX, centerY, 0);
      final scaleMatrix = Matrix4.diagonal3Values(scale, scale, 1);
      final translateToFocal = Matrix4.translationValues(
        -focalPoint.dx,
        -focalPoint.dy,
        0,
      );

      targetMatrix = translateToCenter
        ..multiply(scaleMatrix)
        ..multiply(translateToFocal);
    }

    final currentValue = Matrix4.copy(controller.value);

    final animation = Matrix4Tween(begin: currentValue, end: targetMatrix)
        .animate(
          CurvedAnimation(parent: _zoomController, curve: Curves.easeInOut),
        );

    animation.addListener(() {
      if (_zoomController.isAnimating) {
        controller.value = animation.value;
      }
    });

    _zoomController.forward().then((_) {
      controller.value = targetMatrix;
    });
  }

  void _closeWithAnimation() {
    _fadeController.reverse().then((_) {
      widget.onClose();
    });
  }

  Future<void> _downloadImage() async {
    final imageUrl = widget.imageUrls[_currentIndex];
    final success = await ImageService.saveImageToGallery(imageUrl);
    if (mounted) {
      Fluttertoast.showToast(
        msg: success ? 'Image saved!' : 'Failed to save image.',
        toastLength: Toast.LENGTH_SHORT,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: Material(
        color: Colors.black.withValues(alpha: 0.9),
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: _isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                clipBehavior: Clip.none,
                itemCount: widget.imageUrls.length,
                itemBuilder: (context, index) {
                  final controller = _transformationControllers[index];
                  final isZoomed = _isZoomedStates[index];
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final viewer = GestureDetector(
                        onDoubleTapDown: (details) =>
                            _handleDoubleTap(details, index),
                        child: InteractiveViewer(
                          transformationController: controller,
                          minScale: 1.0,
                          maxScale: 4.0,
                          boundaryMargin: EdgeInsets.zero,
                          clipBehavior: Clip.hardEdge,
                          child: AnimatedBuilder(
                            animation: controller,
                            builder: (context, child) {
                              return Container(
                                decoration: BoxDecoration(
                                  border: isZoomed
                                      ? Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.3,
                                          ),
                                          width: 2,
                                        )
                                      : null,
                                  borderRadius: isZoomed
                                      ? BorderRadius.circular(8)
                                      : null,
                                ),
                                child: ClipRRect(
                                  borderRadius: isZoomed
                                      ? BorderRadius.circular(8)
                                      : BorderRadius.zero,
                                  child: CachedNetworkImage(
                                    imageUrl: widget.imageUrls[index],
                                    fit: BoxFit.contain,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        const Icon(
                                          Icons.error,
                                          size: 40,
                                          color: Colors.white,
                                        ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );

                      return OverflowBox(
                        minWidth: constraints.maxWidth + 24,
                        maxWidth: constraints.maxWidth + 24,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: viewer,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _closeWithAnimation,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              right: 8,
              child: Material(
                color: Colors.indigoAccent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _downloadImage,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.download, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
            if (_isZoomed)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _resetZoom,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.zoom_out_map,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryImageCard extends StatelessWidget {
  const _HistoryImageCard({required this.result, required this.onTap});

  final GenerationResult result;
  final VoidCallback onTap;

  Future<void> _downloadImage(BuildContext context) async {
    final success = await ImageService.saveImageToGallery(result.imageUrl);
    if (context.mounted) {
      Fluttertoast.showToast(
        msg: success ? 'Image saved!' : 'Failed to save image.',
        toastLength: Toast.LENGTH_SHORT,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: result.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey.shade800,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top > 0
                  ? MediaQuery.of(context).padding.top - 20
                  : 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => _downloadImage(context),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.download, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
