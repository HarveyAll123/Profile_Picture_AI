import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../models/generation_result.dart';
import '../services/image_service.dart';

class ViewResultScreen extends StatefulWidget {
  const ViewResultScreen({super.key});
  static const routeName = '/view-result';

  @override
  State<ViewResultScreen> createState() => _ViewResultScreenState();
}

class _ViewResultScreenState extends State<ViewResultScreen> {
  late final ScrollController _promptScrollController;
  final TransformationController _transformationController =
      TransformationController();
  bool _promptScrollable = false;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _promptScrollController = ScrollController();
    _transformationController.addListener(() {
      final isZoomed =
          _transformationController.value.getMaxScaleOnAxis() > 1.0;
      if (isZoomed != _isZoomed) {
        setState(() => _isZoomed = isZoomed);
      }
    });
  }

  @override
  void dispose() {
    _promptScrollController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _copyPrompt(String prompt) async {
    await Clipboard.setData(ClipboardData(text: prompt));
    Fluttertoast.showToast(
      msg: 'Prompt copied to clipboard',
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  Future<void> _downloadImage(String imageUrl) async {
    final success = await ImageService.saveImageToGallery(imageUrl);
    if (mounted) {
      Fluttertoast.showToast(
        msg: success
            ? 'Image saved to gallery'
            : 'Failed to save image. Please check permissions.',
        toastLength: Toast.LENGTH_SHORT,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_promptScrollController.hasClients) return;
      final scrollable = _promptScrollController.position.maxScrollExtent > 0;
      if (scrollable != _promptScrollable && mounted) {
        setState(() => _promptScrollable = scrollable);
      }
    });

    final result =
        ModalRoute.of(context)?.settings.arguments as GenerationResult?;

    if (result == null) {
      return const Scaffold(body: Center(child: Text('Result not found')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: CachedNetworkImage(
                      imageUrl: result.imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error, size: 40),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Material(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _downloadImage(result.imageUrl),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.download,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isZoomed)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Material(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _resetZoom,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          child: const Icon(
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
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Prompt',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _copyPrompt(result.prompt),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: const Icon(
                              Icons.copy,
                              size: 20,
                              color: Colors.indigoAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ScrollConfiguration(
                        behavior: const ScrollBehavior().copyWith(
                          scrollbars: false,
                        ),
                        child: Scrollbar(
                          controller: _promptScrollController,
                          thumbVisibility: _promptScrollable,
                          child: SingleChildScrollView(
                            controller: _promptScrollController,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(
                              right: 12,
                              bottom: 28,
                            ),
                            child: Text(
                              result.prompt,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
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
