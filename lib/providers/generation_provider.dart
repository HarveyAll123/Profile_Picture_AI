import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_functions_service.dart';
import 'service_providers.dart';

class GeneratedImage {
  const GeneratedImage({
    required this.imageUrl,
    required this.prompt,
    required this.resultId,
  });

  final String imageUrl;
  final String prompt;
  final String resultId;
}

class GenerationState {
  const GenerationState({
    this.isGenerating = false,
    this.generatedImages = const [],
    this.error,
  });

  final bool isGenerating;
  final List<GeneratedImage> generatedImages;
  final String? error;

  GenerationState copyWith({
    bool? isGenerating,
    List<GeneratedImage>? generatedImages,
    String? error,
  }) {
    return GenerationState(
      isGenerating: isGenerating ?? this.isGenerating,
      generatedImages: generatedImages ?? this.generatedImages,
      error: error,
    );
  }

  factory GenerationState.initial() => const GenerationState();
}

class GenerationController extends StateNotifier<GenerationState> {
  GenerationController(this._cloudFunctionsService)
    : super(GenerationState.initial());

  final CloudFunctionsService _cloudFunctionsService;
  bool _cancelRequested = false;
  int _activeRequestId = 0;

  Future<List<GeneratedImage>> generateMultipleVariants({
    required String uid,
    required String originalImagePath,
    required String imageUrl,
    required List<String> stylePrompts,
  }) async {
    final requestId = ++_activeRequestId;
    _cancelRequested = false;
    state = state.copyWith(isGenerating: true, error: null);
    final List<GeneratedImage> results = [];

    try {
      for (int i = 0; i < stylePrompts.length; i++) {
        if (_cancelRequested || requestId != _activeRequestId) {
          break;
        }
        final prompt = stylePrompts[i];
        final response = await _cloudFunctionsService.generateProfilePicture(
          imageUrl: imageUrl,
          prompt: prompt,
        );

        results.add(
          GeneratedImage(
            imageUrl: response['imageUrl']!,
            prompt: prompt,
            resultId:
                response['resultId'] ??
                '${DateTime.now().millisecondsSinceEpoch}_$i',
          ),
        );
      }

      state = state.copyWith(isGenerating: false, generatedImages: results);
      return results;
    } catch (error) {
      state = state.copyWith(isGenerating: false, error: error.toString());
      rethrow;
    }
  }

  void cancelGeneration() {
    if (!state.isGenerating) return;
    _cancelRequested = true;
    state = state.copyWith(isGenerating: false);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void clearGeneratedImages() {
    state = state.copyWith(generatedImages: []);
  }
}

final generationControllerProvider =
    StateNotifierProvider<GenerationController, GenerationState>(
      (ref) => GenerationController(ref.watch(cloudFunctionsServiceProvider)),
    );
