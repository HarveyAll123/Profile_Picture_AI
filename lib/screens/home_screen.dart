import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;

import '../providers/auth_providers.dart';
import '../providers/generation_provider.dart';
import '../providers/upload_provider.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/primary_button.dart';
import '../widgets/image_source_modal.dart';
import '../widgets/scene_selection_modal.dart';
import '../widgets/history_modal.dart';
import '../data/scene_presets.dart';
import '../services/image_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  static const routeName = '/';

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final Set<String> _selectedSceneIds = {};
  late final AnimationController _transitionController;
  bool _showGeneratedImages = false;
  String? _fullScreenImageUrl;
  bool _dontShowSceneWarning = false;
  bool _hasShownWarning = false;
  bool _dontShowRegenerateWarning = false;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadControllerProvider);
    final generationState = ref.watch(generationControllerProvider);
    final ensureAuth = ref.watch(ensureAuthProvider);

    ref.listen(uploadControllerProvider, (previous, next) {
      if (next.localFile != null && next.localFile != previous?.localFile) {
        if (_showGeneratedImages) {
          setState(() {
            _showGeneratedImages = false;
          });
        }
      }
    });

    final canPop = _fullScreenImageUrl == null && !_showGeneratedImages;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_fullScreenImageUrl != null) {
          setState(() {
            _fullScreenImageUrl = null;
          });
          return;
        }

        if (_showGeneratedImages) {
          setState(() {
            _showGeneratedImages = false;
          });
          return;
        }
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text(
                'AI Picture',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            body: ensureAuth.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Authentication error: $err')),
              data: (user) {
                final isLoading =
                    uploadState.isUploading || generationState.isGenerating;
                final selectedCount = _selectedSceneIds.length;
                final overlayMessage = generationState.isGenerating
                    ? 'Generating $selectedCount image${selectedCount > 1 ? 's' : ''}...'
                    : 'Uploading photo...';

                return LoadingOverlay(
                  isLoading: isLoading,
                  message: overlayMessage,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 960;
                          final hasGeneratedImages =
                              generationState.generatedImages.isNotEmpty;

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _PreviewPanel(
                                    uploadState: uploadState,
                                    generationState: generationState,
                                    showGeneratedImages: _showGeneratedImages,
                                    onToggleView: () {
                                      setState(() {
                                        _showGeneratedImages =
                                            !_showGeneratedImages;
                                      });
                                    },
                                    onChangePhoto: () => _showImageSourceDialog(
                                      context,
                                      user.uid,
                                    ),
                                    onImageTap: (imageUrl) {
                                      setState(() {
                                        _fullScreenImageUrl = imageUrl;
                                      });
                                    },
                                    transitionController: _transitionController,
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 4,
                                  child: _GeneratePanel(
                                    selectedSceneIds: _selectedSceneIds,
                                    onOpenSceneModal: () =>
                                        _showSceneSelectionModal(context),
                                    onGenerate: () => _onGeneratePressed(
                                      uid: user.uid,
                                      hasExistingImages: generationState
                                          .generatedImages
                                          .isNotEmpty,
                                    ),
                                    uploadState: uploadState,
                                    generationState: generationState,
                                    clearErrors: () {
                                      ref
                                          .read(
                                            uploadControllerProvider.notifier,
                                          )
                                          .clearError();
                                      ref
                                          .read(
                                            generationControllerProvider
                                                .notifier,
                                          )
                                          .clearError();
                                    },
                                    onShowError: (error) =>
                                        _showErrorDialog(context, error),
                                  ),
                                ),
                              ],
                            );
                          }

                          // Mobile: Single column, no scroll on main page
                          return Column(
                            children: [
                              Expanded(
                                flex: hasGeneratedImages ? 6 : 5,
                                child: _PreviewPanel(
                                  uploadState: uploadState,
                                  generationState: generationState,
                                  showGeneratedImages: _showGeneratedImages,
                                  onToggleView: () {
                                    setState(() {
                                      _showGeneratedImages =
                                          !_showGeneratedImages;
                                    });
                                  },
                                  onChangePhoto: () =>
                                      _showImageSourceDialog(context, user.uid),
                                  onImageTap: (imageUrl) {
                                    setState(() {
                                      _fullScreenImageUrl = imageUrl;
                                    });
                                  },
                                  transitionController: _transitionController,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                flex: hasGeneratedImages ? 4 : 5,
                                child: _GeneratePanel(
                                  selectedSceneIds: _selectedSceneIds,
                                  onOpenSceneModal: () =>
                                      _showSceneSelectionModal(context),
                                  onGenerate: () => _onGeneratePressed(
                                    uid: user.uid,
                                    hasExistingImages: generationState
                                        .generatedImages
                                        .isNotEmpty,
                                  ),
                                  uploadState: uploadState,
                                  generationState: generationState,
                                  clearErrors: () {
                                    ref
                                        .read(uploadControllerProvider.notifier)
                                        .clearError();
                                    ref
                                        .read(
                                          generationControllerProvider.notifier,
                                        )
                                        .clearError();
                                  },
                                  onShowError: (error) =>
                                      _showErrorDialog(context, error),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_fullScreenImageUrl != null)
            _FullScreenImageOverlay(
              imageUrl: _fullScreenImageUrl!,
              onClose: () {
                setState(() {
                  _fullScreenImageUrl = null;
                });
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showSceneWarningDialog(BuildContext context) async {
    if (_dontShowSceneWarning || _hasShownWarning) return;

    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => _SceneWarningDialog(
        onDontShowAgain: () {
          setState(() {
            _dontShowSceneWarning = true;
            _hasShownWarning = true;
          });
          Navigator.of(context).pop();
        },
        onOk: () {
          setState(() {
            _hasShownWarning = true;
          });
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _showErrorDialog(BuildContext context, String error) async {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => _ErrorDialog(
        error: error,
        onOk: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _showSceneSelectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) => SceneSelectionModal(
        selectedSceneIds: _selectedSceneIds,
        onReset: () {
          setState(() {
            _selectedSceneIds.clear();
            _hasShownWarning = false;
          });
        },
        onSceneToggled: (sceneId) {
          setState(() {
            final previousCount = _selectedSceneIds.length;
            if (_selectedSceneIds.contains(sceneId)) {
              _selectedSceneIds.remove(sceneId);
            } else {
              _selectedSceneIds.add(sceneId);
            }
            final newCount = _selectedSceneIds.length;

            // Reset warning flag if count drops below 5
            if (newCount < 5) {
              _hasShownWarning = false;
            }

            // Show warning when transitioning from 4 to 5
            if (previousCount == 4 &&
                newCount == 5 &&
                !_dontShowSceneWarning &&
                !_hasShownWarning) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showSceneWarningDialog(context);
              });
            }
          });
        },
      ),
    );
  }

  void _showImageSourceDialog(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ImageSourceModal(uid: uid),
    );
  }

  Future<void> _onGeneratePressed({
    required String uid,
    bool hasExistingImages = false,
  }) async {
    final uploadState = ref.read(uploadControllerProvider);
    final controller = ref.read(generationControllerProvider.notifier);

    if (uploadState.downloadUrl == null ||
        uploadState.storagePath == null ||
        uploadState.storagePath!.isEmpty) {
      Fluttertoast.showToast(msg: 'Please upload an image first.');
      return;
    }

    if (_selectedSceneIds.isEmpty) {
      Fluttertoast.showToast(msg: 'Please select at least one scene.');
      return;
    }

    // Show warning if there are existing images and user hasn't disabled it
    if (hasExistingImages && !_dontShowRegenerateWarning) {
      final shouldContinue = await _showRegenerateWarningDialog(context);
      if (!shouldContinue) {
        return;
      }
    }

    final selectedPresets = scenePresets
        .where((preset) => _selectedSceneIds.contains(preset.id))
        .toList();

    final stylePrompts = selectedPresets.map((preset) {
      return 'Generate a photorealistic portrait variation that keeps the subject\'s facial identity, skin tone, and expression consistent. '
          '${preset.prompt} '
          'Use cohesive lighting, realistic shadows, and natural textures.';
    }).toList();

    try {
      _transitionController.forward();
      await controller.generateMultipleVariants(
        uid: uid,
        originalImagePath: uploadState.storagePath!,
        imageUrl: uploadState.downloadUrl!,
        stylePrompts: stylePrompts,
      );
      setState(() {
        _showGeneratedImages = true;
      });
      Fluttertoast.showToast(
        msg:
            'Generated ${stylePrompts.length} image${stylePrompts.length > 1 ? 's' : ''}!',
      );
    } catch (error) {
      _transitionController.reverse();
      // Error will be shown in the UI via GenerationState
    }
  }

  Future<bool> _showRegenerateWarningDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.7),
          builder: (context) => _RegenerateWarningDialog(
            onDontShowAgain: (shouldDontShow) {
              if (shouldDontShow) {
                setState(() {
                  _dontShowRegenerateWarning = true;
                });
              }
            },
            onCancel: () {
              Navigator.of(context).pop(false);
            },
            onGenerate: () {
              Navigator.of(context).pop(true);
            },
          ),
        ) ??
        false;
  }
}

class _FullScreenImageOverlay extends StatefulWidget {
  const _FullScreenImageOverlay({
    required this.imageUrl,
    required this.onClose,
  });

  final String imageUrl;
  final VoidCallback onClose;

  @override
  State<_FullScreenImageOverlay> createState() =>
      _FullScreenImageOverlayState();
}

class _FullScreenImageOverlayState extends State<_FullScreenImageOverlay>
    with TickerProviderStateMixin {
  late final TransformationController _transformationController;
  late final AnimationController _fadeController;
  late final AnimationController _zoomController;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.addListener(() {
      final isZoomed =
          _transformationController.value.getMaxScaleOnAxis() > 1.0;
      if (isZoomed != _isZoomed) {
        setState(() {
          _isZoomed = isZoomed;
        });
      }
    });
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
    _transformationController.dispose();
    _fadeController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    // Stop any ongoing animation first
    _zoomController.stop();
    _zoomController.reset();

    // Capture the exact current transformation at this moment
    final currentValue = Matrix4.copy(_transformationController.value);
    final targetValue = Matrix4.identity();

    // Set the current value immediately to ensure we start from the exact position
    _transformationController.value = currentValue;

    final animation = Tween<Matrix4>(begin: currentValue, end: targetValue)
        .animate(
          CurvedAnimation(parent: _zoomController, curve: Curves.easeInOut),
        );

    animation.addListener(() {
      if (_zoomController.isAnimating) {
        _transformationController.value = animation.value;
      }
    });

    _zoomController.forward().then((_) {
      _transformationController.value = targetValue;
    });
  }

  void _closeWithAnimation() {
    _fadeController.reverse().then((_) {
      widget.onClose();
    });
  }

  Future<void> _downloadImage() async {
    final success = await ImageService.saveImageToGallery(widget.imageUrl);
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
        color: Colors.black.withValues(alpha: 0.85),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1.0,
                maxScale: 4.0,
                boundaryMargin: EdgeInsets.zero,
                child: AnimatedBuilder(
                  animation: _transformationController,
                  builder: (context, child) {
                    final scale = _transformationController.value
                        .getMaxScaleOnAxis();
                    final isZoomed = scale > 1.0;
                    return Container(
                      decoration: BoxDecoration(
                        border: isZoomed
                            ? Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
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
                          imageUrl: widget.imageUrl,
                          fit: BoxFit.contain,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) => const Icon(
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

class _PreviewPanel extends ConsumerWidget {
  const _PreviewPanel({
    required this.uploadState,
    required this.generationState,
    required this.showGeneratedImages,
    required this.onToggleView,
    required this.onChangePhoto,
    required this.onImageTap,
    required this.transitionController,
  });

  final UploadState uploadState;
  final GenerationState generationState;
  final bool showGeneratedImages;
  final VoidCallback onToggleView;
  final VoidCallback onChangePhoto;
  final ValueChanged<String> onImageTap;
  final AnimationController transitionController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasGeneratedImages = generationState.generatedImages.isNotEmpty;
    final shouldShowGenerated = hasGeneratedImages && showGeneratedImages;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shouldShowGenerated) ...[
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, 0.1),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      ),
                    );
                  },
                  child: _GeneratedImagesGrid(
                    key: ValueKey(generationState.generatedImages.length),
                    images: generationState.generatedImages,
                    onImageTap: onImageTap,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'Download All',
                      icon: Icons.download_outlined,
                      onPressed: () => _downloadAllImages(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.indigoAccent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onToggleView,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Upload New Photo',
                icon: Icons.add_a_photo_outlined,
                onPressed: onChangePhoto,
              ),
            ] else ...[
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: _ImagePreview(
                    key: ValueKey(uploadState.localFile?.path ?? 'empty'),
                    uploadState: uploadState,
                    onTap: onChangePhoto,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: uploadState.localFile == null
                          ? 'Upload Photo'
                          : 'Replace Photo',
                      icon: Icons.add_a_photo_outlined,
                      isLoading: uploadState.isUploading,
                      onPressed: uploadState.isUploading ? null : onChangePhoto,
                    ),
                  ),
                  if (hasGeneratedImages) ...[
                    const SizedBox(width: 12),
                    Material(
                      color: Colors.indigoAccent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: onToggleView,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.collections_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Use one well-lit portrait, then select scenes to generate.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAllImages(BuildContext context) async {
    final images = generationState.generatedImages;
    int successCount = 0;
    for (final image in images) {
      final success = await ImageService.saveImageToGallery(image.imageUrl);
      if (success) successCount++;
    }
    if (context.mounted) {
      Fluttertoast.showToast(
        msg: successCount == images.length
            ? 'All ${images.length} images saved!'
            : 'Saved $successCount of ${images.length} images.',
      );
    }
  }
}

class _GeneratedImagesGrid extends StatelessWidget {
  const _GeneratedImagesGrid({
    super.key,
    required this.images,
    required this.onImageTap,
  });

  final List<GeneratedImage> images;
  final ValueChanged<String> onImageTap;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      itemCount: images.length,
      itemBuilder: (context, index) {
        final image = images[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _GeneratedImageCard(
            image: image,
            onTap: () => onImageTap(image.imageUrl),
          ),
        );
      },
    );
  }
}

class _GeneratedImageCard extends StatelessWidget {
  const _GeneratedImageCard({required this.image, required this.onTap});

  final GeneratedImage image;
  final VoidCallback onTap;

  Future<Size> _getImageSize(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(
          Uint8List.fromList(response.bodyBytes),
        );
        final frame = await codec.getNextFrame();
        return frame.image.width > 0 && frame.image.height > 0
            ? Size(frame.image.width.toDouble(), frame.image.height.toDouble())
            : const Size(1, 1);
      }
    } catch (e) {
      // Return default if error
    }
    return const Size(1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Size>(
              future: _getImageSize(image.imageUrl),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return CachedNetworkImage(
                    imageUrl: image.imageUrl,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    placeholder: (context, url) => Container(
                      color: Colors.grey.shade800,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                  );
                }
                final imageSize = snapshot.data!;
                final isPortrait = imageSize.height > imageSize.width;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final containerAspectRatio =
                        constraints.maxWidth / constraints.maxHeight;

                    // If image is portrait and container is portrait, use cover for edge-to-edge
                    // If image is landscape and container is landscape, use cover for edge-to-edge
                    // Otherwise use contain to show full image
                    BoxFit fit;
                    if ((isPortrait && containerAspectRatio < 1) ||
                        (!isPortrait && containerAspectRatio >= 1)) {
                      fit = BoxFit.cover;
                    } else {
                      fit = BoxFit.contain;
                    }

                    return CachedNetworkImage(
                      imageUrl: image.imageUrl,
                      fit: fit,
                      alignment: Alignment.center,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade800,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error),
                    );
                  },
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () async {
                    final success = await ImageService.saveImageToGallery(
                      image.imageUrl,
                    );
                    if (context.mounted) {
                      Fluttertoast.showToast(
                        msg: success ? 'Image saved!' : 'Failed to save image.',
                        toastLength: Toast.LENGTH_SHORT,
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.download, color: Colors.white, size: 20),
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

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({super.key, required this.uploadState, this.onTap});

  final UploadState uploadState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: Colors.indigo.withValues(alpha: 0.2),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF020617)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: uploadState.localFile != null
                ? Image.file(uploadState.localFile!, fit: BoxFit.cover)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 80,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Upload a portrait photo to begin',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Front-facing, good lighting, minimal background.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.white70, fontSize: 11),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _GeneratePanel extends StatelessWidget {
  const _GeneratePanel({
    required this.selectedSceneIds,
    required this.onOpenSceneModal,
    required this.onGenerate,
    required this.uploadState,
    required this.generationState,
    required this.clearErrors,
    required this.onShowError,
  });

  final Set<String> selectedSceneIds;
  final VoidCallback onOpenSceneModal;
  final VoidCallback onGenerate;
  final UploadState uploadState;
  final GenerationState generationState;
  final VoidCallback clearErrors;
  final ValueChanged<String> onShowError;

  @override
  Widget build(BuildContext context) {
    final errorMessage = uploadState.error ?? generationState.error;
    final selectedCount = selectedSceneIds.length;

    // Show error dialog when error occurs
    if (errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          onShowError(errorMessage);
          clearErrors();
        }
      });
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Scenes',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose your scene(s) to generate',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: Colors.indigoAccent,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    onTap: onOpenSceneModal,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.palette_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                          if (selectedCount > 0)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.indigoAccent,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    selectedCount > 9 ? '9+' : '$selectedCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
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
              ],
            ),
            const SizedBox(height: 20),
            if (selectedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.indigoAccent.withValues(alpha: 0.3),
                  ),
                  color: Colors.indigoAccent.withValues(alpha: 0.1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$selectedCount selected: ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.indigoAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        scenePresets
                                .where((p) => selectedSceneIds.contains(p.id))
                                .take(2)
                                .map((p) => p.title)
                                .join(', ') +
                            (selectedCount > 2 ? ' +${selectedCount - 2}' : ''),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.indigoAccent,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                  color: Colors.white.withValues(alpha: 0.03),
                ),
                child: Text(
                  'Tap the palette button to select scenes',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        isScrollControlled: true,
                        builder: (context) => DraggableScrollableSheet(
                          initialChildSize: 0.85,
                          minChildSize: 0.5,
                          maxChildSize: 0.95,
                          builder: (context, scrollController) =>
                              const HistoryModal(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history, size: 20),
                    label: const Text('History'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: PrimaryButton(
                    label: uploadState.downloadUrl == null
                        ? 'Upload photo'
                        : selectedCount == 0
                        ? 'Select scenes'
                        : 'Generate $selectedCount',
                    icon: Icons.auto_awesome,
                    isLoading: generationState.isGenerating,
                    onPressed:
                        uploadState.downloadUrl == null ||
                            generationState.isGenerating ||
                            selectedCount == 0
                        ? null
                        : onGenerate,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneWarningDialog extends StatefulWidget {
  const _SceneWarningDialog({
    required this.onDontShowAgain,
    required this.onOk,
  });

  final VoidCallback onDontShowAgain;
  final VoidCallback onOk;

  @override
  State<_SceneWarningDialog> createState() => _SceneWarningDialogState();
}

class _SceneWarningDialogState extends State<_SceneWarningDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.indigoAccent.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigoAccent.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.shade400,
                          Colors.orange.shade600,
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.schedule_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '5 Scenes Selected',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Generation may take longer with 5+ scenes. You can continue, but expect increased processing time.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.onOk,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigoAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          child: const Text(
                            'Got it',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: widget.onDontShowAgain,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Don\'t show again',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ],
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

class _RegenerateWarningDialog extends StatefulWidget {
  const _RegenerateWarningDialog({
    required this.onDontShowAgain,
    required this.onCancel,
    required this.onGenerate,
  });

  final ValueChanged<bool> onDontShowAgain;
  final VoidCallback onCancel;
  final VoidCallback onGenerate;

  @override
  State<_RegenerateWarningDialog> createState() =>
      _RegenerateWarningDialogState();
}

class _RegenerateWarningDialogState extends State<_RegenerateWarningDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  bool _dontShowAgain = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.indigoAccent.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigoAccent.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade400, Colors.amber.shade600],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Continue Generating?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your recent generated images will be moved to history. Do you want to continue generating new image(s)?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                widget.onDontShowAgain(_dontShowAgain);
                                widget.onCancel();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                widget.onDontShowAgain(_dontShowAgain);
                                widget.onGenerate();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigoAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 4,
                              ),
                              child: const Text(
                                'Generate New',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: _dontShowAgain,
                            onChanged: (value) {
                              setState(() {
                                _dontShowAgain = value ?? false;
                              });
                            },
                            activeColor: Colors.indigoAccent,
                            checkColor: Colors.white,
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _dontShowAgain = !_dontShowAgain;
                              });
                            },
                            child: Text(
                              'Don\'t show again',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _ErrorDialog extends StatefulWidget {
  const _ErrorDialog({required this.error, required this.onOk});

  final String error;
  final VoidCallback onOk;

  @override
  State<_ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<_ErrorDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.error));
    if (mounted) {
      Fluttertoast.showToast(
        msg: 'Error copied to clipboard',
        toastLength: Toast.LENGTH_SHORT,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade400, Colors.red.shade600],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Error',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        widget.error,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyToClipboard,
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: widget.onOk,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          child: const Text(
                            'OK',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
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
        ),
      ),
    );
  }
}
