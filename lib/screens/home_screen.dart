import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;

import '../providers/auth_providers.dart';
import '../providers/generation_provider.dart';
import '../providers/theme_mode_provider.dart';
import '../providers/upload_provider.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/primary_button.dart';
import '../widgets/image_source_modal.dart';
import '../widgets/scene_selection_modal.dart';
import '../widgets/history_modal.dart';
import '../widgets/glass_container.dart';
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
  int _fullScreenImageIndex = 0;
  bool _dontShowSceneWarning = false;
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
    final selectedCount = _selectedSceneIds.length;
    final isProcessing =
        uploadState.isUploading || generationState.isGenerating;
    final processingMessage = generationState.isGenerating
        ? 'Generating $selectedCount look${selectedCount == 1 ? '' : 's'}'
        : 'Uploading photo...';

    ref.listen(uploadControllerProvider, (previous, next) {
      if (next.localFile != null && next.localFile != previous?.localFile) {
        if (_showGeneratedImages) {
          setState(() {
            _showGeneratedImages = false;
          });
        }
      }
    });

    final currentError = uploadState.error ?? generationState.error;
    if (currentError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showErrorDialog(context, currentError);
        ref.read(uploadControllerProvider.notifier).clearError();
        ref.read(generationControllerProvider.notifier).clearError();
      });
    }

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
      child: LoadingOverlay(
        isLoading: isProcessing,
        message: processingMessage,
        onCancel: isProcessing ? _handleCancelLoading : null,
        child: Stack(
          children: [
            const _LiquidAuroraBackground(),
            Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: true,
              appBar: AppBar(
                titleSpacing: 16,
                title: Text(
                  'AI Picture',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                actions: const [
                  Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: _ThemeToggleButton(),
                  ),
                ],
              ),
              body: ensureAuth.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) =>
                    Center(child: Text('Authentication error: $err')),
                data: (user) {
                  return SafeArea(
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 960;
                              final preview = _PreviewPanel(
                                uploadState: uploadState,
                                generationState: generationState,
                                selectedSceneIds: _selectedSceneIds,
                                showGeneratedImages: _showGeneratedImages,
                                onToggleView: () {
                                  setState(() {
                                    _showGeneratedImages =
                                        !_showGeneratedImages;
                                  });
                                },
                                onChangePhoto: () =>
                                    _showImageSourceDialog(context, user.uid),
                                onGenerate: () => _onGeneratePressed(
                                  uid: user.uid,
                                  hasExistingImages: generationState
                                      .generatedImages
                                      .isNotEmpty,
                                ),
                                onImageTap: (imageUrl) {
                                  final generationState = ref.read(
                                    generationControllerProvider,
                                  );
                                  final imageUrls = generationState
                                      .generatedImages
                                      .map((img) => img.imageUrl)
                                      .toList();
                                  final index = imageUrls.indexOf(imageUrl);
                                  setState(() {
                                    _fullScreenImageUrl = imageUrl;
                                    _fullScreenImageIndex =
                                        index >= 0 ? index : 0;
                                  });
                                },
                                onEditScenes: () =>
                                    _showSceneSelectionModal(context, user.uid),
                                transitionController: _transitionController,
                              );

                              return Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: isWide ? 1100 : double.infinity,
                                  ),
                                  child: preview,
                                ),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _BottomOverlay(
                            child: _BottomActionBar(
                              onHistory: () => _openHistoryModal(context),
                              onUpload: () =>
                                  _showImageSourceDialog(context, user.uid),
                              onScenes: () =>
                                  _showSceneSelectionModal(context, user.uid),
                              hasScenesSelected: _selectedSceneIds.isNotEmpty,
                              hasGeneratedImages:
                                  generationState.generatedImages.isNotEmpty,
                              isUploading: uploadState.isUploading,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_fullScreenImageUrl != null)
              Builder(
                builder: (context) {
                  final generationState = ref.watch(generationControllerProvider);
                  final imageUrls = generationState.generatedImages
                      .map((img) => img.imageUrl)
                      .toList();
                  return _FullScreenImageOverlay(
                    imageUrls: imageUrls.isNotEmpty
                        ? imageUrls
                        : [_fullScreenImageUrl!],
                    initialIndex: _fullScreenImageIndex,
                    onClose: () {
                      setState(() {
                        _fullScreenImageUrl = null;
                      });
                    },
                    onIndexChanged: (index) {
                      setState(() {
                        _fullScreenImageIndex = index;
                        if (imageUrls.isNotEmpty && index < imageUrls.length) {
                          _fullScreenImageUrl = imageUrls[index];
                        }
                      });
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showSceneWarningDialog(BuildContext context) async {
    if (_dontShowSceneWarning) return true;

    final dontShowAgain =
        await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          barrierColor: Colors.black.withValues(alpha: 0.7),
          builder: (context) => const _SceneWarningDialog(),
        ) ??
        false;

    setState(() {
      if (dontShowAgain) {
        _dontShowSceneWarning = true;
      }
    });

    return true;
  }

  Future<bool> _showQuickGeneratePrompt(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => const _QuickGeneratePromptDialog(),
    );
    return result ?? false;
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

  Future<void> _showSceneSelectionModal(
    BuildContext context,
    String uid,
  ) async {
    var shouldPromptForGeneration = false;
    var hadExistingImages = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.66,
        minChildSize: 0.45,
        maxChildSize: 0.88,
        builder: (context, scrollController) => SceneSelectionModal(
          scrollController: scrollController,
          initialSelectedSceneIds: _selectedSceneIds,
          onReachedFive: () => _showSceneWarningDialog(context),
          onApply: (selectedIds) async {
            final previousCount = _selectedSceneIds.length;
            final newCount = selectedIds.length;

            final shouldShowWarning =
                previousCount < 5 && newCount >= 5 && !_dontShowSceneWarning;

            if (shouldShowWarning) {
              final acknowledged = await _showSceneWarningDialog(context);
              if (!acknowledged) {
                return false;
              }
            }

            setState(() {
              _selectedSceneIds
                ..clear()
                ..addAll(selectedIds);
            });

            final uploadState = ref.read(uploadControllerProvider);
            final generationState = ref.read(generationControllerProvider);
            final hasPhotoReady =
                uploadState.downloadUrl != null && !uploadState.isUploading;
            final hasScenesSelected = selectedIds.isNotEmpty;
            final generationIdle = !generationState.isGenerating;

            shouldPromptForGeneration =
                hasPhotoReady && hasScenesSelected && generationIdle;
            hadExistingImages = generationState.generatedImages.isNotEmpty;

            return true;
          },
        ),
      ),
    );

    if (!context.mounted) return;
    if (!shouldPromptForGeneration) return;

    final shouldGenerateNow = await _showQuickGeneratePrompt(context);
    if (!context.mounted) return;
    if (!shouldGenerateNow) return;

    await _onGeneratePressed(
      uid: uid,
      hasExistingImages: hadExistingImages,
    );
  }

  void _openHistoryModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => const HistoryModal(),
      ),
    );
  }

  void _showImageSourceDialog(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
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
      return 'Generate a natural-looking portrait that could plausibly come from a recent smartphone photo. Preserve the subject’s unique facial identity, complexion, and natural hair color/texture, but allow expression, pose, wardrobe, accessories, and color palette to adapt organically to the environment so the person blends into the scene (e.g., swap jackets, shirts, or lighting to match the location). '
          'Avoid studio-perfect retouching or repeating the same outfit across scenes—each render should feel candid yet flattering with cohesive lighting, believable shadows, and realistic textures. '
          '${preset.prompt} '
          'Remove any watermark, logo, or system UI from the source image before finalizing.';
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

  void _handleCancelLoading() {
    final uploadState = ref.read(uploadControllerProvider);
    final generationState = ref.read(generationControllerProvider);
    if (uploadState.isUploading) {
      ref.read(uploadControllerProvider.notifier).cancelUpload();
      Fluttertoast.showToast(msg: 'Upload canceled');
    }
    if (generationState.isGenerating) {
      ref.read(generationControllerProvider.notifier).cancelGeneration();
      Fluttertoast.showToast(msg: 'Generation canceled');
    }
  }
}

class _FullScreenImageOverlay extends StatefulWidget {
  const _FullScreenImageOverlay({
    required this.imageUrls,
    required this.initialIndex,
    required this.onClose,
    this.onIndexChanged,
  });

  final List<String> imageUrls;
  final int initialIndex;
  final VoidCallback onClose;
  final ValueChanged<int>? onIndexChanged;

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
    widget.onIndexChanged?.call(index);
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

      final translateToCenter =
          Matrix4.translationValues(centerX, centerY, 0);
      final scaleMatrix = Matrix4.diagonal3Values(scale, scale, 1);
      final translateToFocal =
          Matrix4.translationValues(-focalPoint.dx, -focalPoint.dy, 0);

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

class _PreviewPanel extends ConsumerWidget {
  const _PreviewPanel({
    required this.uploadState,
    required this.generationState,
    required this.selectedSceneIds,
    required this.showGeneratedImages,
    required this.onToggleView,
    required this.onChangePhoto,
    required this.onGenerate,
    required this.onImageTap,
    required this.onEditScenes,
    required this.transitionController,
  });

  final UploadState uploadState;
  final GenerationState generationState;
  final Set<String> selectedSceneIds;
  final bool showGeneratedImages;
  final VoidCallback onToggleView;
  final VoidCallback onChangePhoto;
  final VoidCallback onGenerate;
  final ValueChanged<String> onImageTap;
  final VoidCallback onEditScenes;
  final AnimationController transitionController;

  bool get _hasUploadedPhoto => uploadState.downloadUrl != null;
  bool get _hasSelectedScenes => selectedSceneIds.isNotEmpty;
  bool get _hasGeneratedImages => generationState.generatedImages.isNotEmpty;
  bool get _shouldShowGenerated => _hasGeneratedImages && showGeneratedImages;

  bool get _canGenerate =>
      uploadState.downloadUrl != null &&
      selectedSceneIds.isNotEmpty &&
      !generationState.isGenerating &&
      !uploadState.isUploading;

  String get _primaryActionLabel {
    if (uploadState.isUploading) return 'Uploading photo...';
    if (generationState.isGenerating) return 'Crafting looks...';
    if (!_hasUploadedPhoto) return 'Upload photo first';
    if (!_hasSelectedScenes) return 'Select scenes';
    return 'Generate ${selectedSceneIds.length} look${selectedSceneIds.length > 1 ? 's' : ''}';
  }

  IconData get _primaryActionIcon {
    if (uploadState.isUploading) return Icons.file_upload_outlined;
    if (generationState.isGenerating) return Icons.auto_awesome;
    if (!_hasUploadedPhoto) return Icons.file_upload_outlined;
    if (!_hasSelectedScenes) return Icons.palette_outlined;
    return Icons.auto_awesome;
  }

  VoidCallback? get _primaryAction {
    if (uploadState.isUploading || generationState.isGenerating) {
      return null;
    }
    if (!_hasUploadedPhoto) return onChangePhoto;
    if (!_hasSelectedScenes) return onEditScenes;
    return _canGenerate ? onGenerate : null;
  }

  String? get _helperText {
    if (!_hasUploadedPhoto) {
      return 'Tap the portrait workspace or use the Upload button below to begin.';
    }
    if (!_hasSelectedScenes) {
      return 'Choose up to 10 scenes to style the look.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final helperText = _helperText;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          SizedBox(
            height: _shouldShowGenerated ? 300 : 230,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                );
              },
              child: _shouldShowGenerated
                  ? _GeneratedImagesGrid(
                      key: ValueKey(generationState.generatedImages.length),
                      images: generationState.generatedImages,
                      onImageTap: onImageTap,
                    )
                  : _ImagePreview(
                      key: ValueKey(uploadState.localFile?.path ?? 'empty'),
                      uploadState: uploadState,
                      onTap: onChangePhoto,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          if (_shouldShowGenerated) ...[
            _GeneratedActionsRow(
              onToggleView: onToggleView,
              onRegenerate: onGenerate,
              canRegenerate: _canGenerate,
              onDownloadAll: (context) => _downloadAllImages(context),
            ),
            const SizedBox(height: 12),
            _SelectedScenesSummary(
              selectedSceneIds: selectedSceneIds,
              onTap: onEditScenes,
            ),
          ] else ...[
            PrimaryButton(
              label: _primaryActionLabel,
              icon: _primaryActionIcon,
              onPressed: _primaryAction,
            ),
            const SizedBox(height: 12),
            _SelectedScenesSummary(
              selectedSceneIds: selectedSceneIds,
              onTap: onEditScenes,
            ),
            const SizedBox(height: 12),
            if (helperText != null)
              Text(
                helperText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                    ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _shouldShowGenerated ? 'Generated looks' : 'Portrait workspace',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              _shouldShowGenerated
                  ? 'Swipe to inspect, double-tap to zoom in.'
                  : 'Upload a crisp portrait to begin.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
        if (_hasGeneratedImages)
          _GlassIconButton(
            icon: _shouldShowGenerated
                ? Icons.close_fullscreen
                : Icons.collections_outlined,
            tooltip: _shouldShowGenerated ? 'Back to preview' : 'View results',
            onTap: onToggleView,
          ),
      ],
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

class _GeneratedActionsRow extends StatelessWidget {
  const _GeneratedActionsRow({
    required this.onToggleView,
    required this.onRegenerate,
    required this.canRegenerate,
    required this.onDownloadAll,
  });

  final VoidCallback onToggleView;
  final VoidCallback onRegenerate;
  final bool canRegenerate;
  final Future<void> Function(BuildContext) onDownloadAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: 'Download all',
                icon: Icons.download_outlined,
                onPressed: () => onDownloadAll(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                label: 'Regenerate',
                icon: Icons.auto_awesome,
                onPressed: canRegenerate ? onRegenerate : null,
              ),
            ),
          ],
        ),
      ],
    );
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
      behavior: HitTestBehavior.opaque,
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
    final colorScheme = Theme.of(context).colorScheme;
    final gradientColors = Theme.of(context).brightness == Brightness.dark
        ? const [Color(0xFF1E293B), Color(0xFF020617)]
        : [
            colorScheme.surface,
            colorScheme.surface.withValues(alpha: 0.8),
          ];
    final textColor = colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: gradientColors,
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
                      color: textColor.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Upload a portrait photo to begin',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Front-facing, good lighting, minimal background.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: textColor.withValues(alpha: 0.7),
                            ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SelectedScenesSummary extends StatelessWidget {
  const _SelectedScenesSummary({
    required this.selectedSceneIds,
    required this.onTap,
  });

  final Set<String> selectedSceneIds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedPresetsList = scenePresets
        .where((preset) => selectedSceneIds.contains(preset.id))
        .toList();
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = selectedPresetsList.isEmpty
        ? 'Tap to add up to 10 moods'
        : selectedPresetsList.take(3).map((p) => p.title).join(', ');

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: colorScheme.primary.withValues(alpha: 0.08),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.palette_outlined,
                color: colorScheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${selectedSceneIds.length} scene${selectedSceneIds.length == 1 ? '' : 's'} selected',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: GlassContainer(
        padding: const EdgeInsets.all(12),
        borderRadius: 18,
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );

    if (tooltip == null) {
      return button;
    }
    return Tooltip(
      message: tooltip!,
      child: button,
    );
  }
}

class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final controller = ref.read(themeModeProvider.notifier);
    final entry = switch (mode) {
      ThemeMode.system => (Icons.auto_awesome, 'Auto'),
      ThemeMode.light => (Icons.wb_sunny_outlined, 'Light'),
      ThemeMode.dark => (Icons.nights_stay_outlined, 'Dark'),
    };

    return GestureDetector(
      onTap: controller.cycleMode,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: 999,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Icon(entry.$1,
                  key: ValueKey(entry.$1),
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(width: 6),
            Text(
              entry.$2,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomOverlay extends StatelessWidget {
  const _BottomOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            background.withValues(alpha: 0.95),
            background.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: child,
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.onHistory,
    required this.onUpload,
    required this.onScenes,
    required this.hasScenesSelected,
    required this.hasGeneratedImages,
    required this.isUploading,
  });

  final VoidCallback onHistory;
  final VoidCallback onUpload;
  final VoidCallback onScenes;
  final bool hasScenesSelected;
  final bool hasGeneratedImages;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      borderRadius: 40,
      child: Row(
        children: [
          Expanded(
            child: _BottomNavButton(
              icon: Icons.history,
              label: 'History',
              onTap: onHistory,
              isActive: hasGeneratedImages,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _BottomNavButton(
              icon: Icons.add_a_photo_outlined,
              label: isUploading ? 'Uploading' : 'Upload',
              onTap: isUploading ? null : onUpload,
              isActive: !isUploading,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _BottomNavButton(
              icon: Icons.palette,
              label: 'Scenes',
              onTap: onScenes,
              isActive: hasScenesSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = isActive
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.6);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: textColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
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

class _LiquidAuroraBackground extends StatelessWidget {
  const _LiquidAuroraBackground();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF01030B), Color(0xFF050A16)]
                : const [Color(0xFFF8FBFF), Color(0xFFE2E8FF)],
          ),
        ),
        child: Stack(
          children: [
            _AuroraBlob(
              alignment: const Alignment(-0.8, -0.7),
              diameter: 360,
              colors: isDark
                  ? const [Color(0x566B8BFF), Color(0x334F46E5)]
                  : const [Color(0x446B8BFF), Color(0x2238BDF8)],
            ),
            _AuroraBlob(
              alignment: const Alignment(0.9, -0.2),
              diameter: 280,
              colors: isDark
                  ? const [Color(0x5534D399), Color(0x5138BDF8)]
                  : const [Color(0x4434D399), Color(0x2238BDF8)],
            ),
          ],
        ),
      ),
    );
  }
}

class _AuroraBlob extends StatelessWidget {
  const _AuroraBlob({
    required this.alignment,
    required this.diameter,
    required this.colors,
  });

  final Alignment alignment;
  final double diameter;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

class _QuickGeneratePromptDialog extends StatelessWidget {
  const _QuickGeneratePromptDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    final panelGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xFF1E293B), Color(0xFF0F172A)]
          : [
              Colors.white,
              Colors.white.withValues(alpha: 0.94),
            ],
    );

    void close(bool result) {
      Navigator.of(context, rootNavigator: true).pop(result);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          gradient: panelGradient,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: primary.withValues(alpha: isDark ? 0.3 : 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
              blurRadius: 26,
              offset: const Offset(0, 18),
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
                      primary,
                      primary.withValues(alpha: 0.7),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.4),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Generate with these scenes?',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You\'ve uploaded a portrait and selected scene styles. Generate the looks now or keep adjusting.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withValues(alpha: 0.7),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => close(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: onSurface,
                        side: BorderSide(
                          color: onSurface.withValues(alpha: 0.2),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Not now',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => close(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Generate now',
                        style: TextStyle(
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
    );
  }
}

class _SceneWarningDialog extends StatefulWidget {
  const _SceneWarningDialog();

  @override
  State<_SceneWarningDialog> createState() => _SceneWarningDialogState();
}

class _SceneWarningDialogState extends State<_SceneWarningDialog>
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

  void _handleContinue() {
    Navigator.of(context, rootNavigator: true).pop(_dontShowAgain);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xFF1E293B), Color(0xFF0F172A)]
          : [
              Colors.white,
              Colors.white.withValues(alpha: 0.92),
            ],
    );
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;

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
              gradient: panelGradient,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: primary.withValues(alpha: isDark ? 0.3 : 0.2),
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
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Generation may take longer with 5+ scenes. You can continue, but expect increased processing time.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: onSurface.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
                        activeColor: primary,
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
                          style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    onSurface.withValues(alpha: 0.7),
                                fontSize: 12,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    final panelGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xFF1E293B), Color(0xFF0F172A)]
          : [
              Colors.white,
              Colors.white.withValues(alpha: 0.92),
            ],
    );

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
              gradient: panelGradient,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.indigoAccent.withValues(alpha: isDark ? 0.3 : 0.2),
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
                          color: onSurface,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your recent generated images will be moved to history. Do you want to continue generating new image(s)?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: onSurface.withValues(alpha: 0.7),
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
                                foregroundColor: onSurface,
                                side: BorderSide(
                                  color: onSurface.withValues(alpha: 0.2),
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
                                backgroundColor: primary,
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
                            activeColor: primary,
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
                                    color:
                                        onSurface.withValues(alpha: 0.7),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final panelGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xFF1E293B), Color(0xFF0F172A)]
          : [
              Colors.white,
              Colors.white.withValues(alpha: 0.92),
            ],
    );

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
              gradient: panelGradient,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: isDark ? 0.3 : 0.2),
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
                          color: onSurface,
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
                          color: onSurface.withValues(alpha: 0.8),
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
                            foregroundColor: onSurface,
                            side: BorderSide(
                              color: onSurface.withValues(alpha: 0.2),
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
