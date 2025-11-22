import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../services/storage_service.dart';
import 'service_providers.dart';

class UploadState {
  const UploadState({
    this.localFile,
    this.downloadUrl,
    this.storagePath,
    this.isUploading = false,
    this.error,
  });

  final File? localFile;
  final String? downloadUrl;
  final String? storagePath;
  final bool isUploading;
  final String? error;

  UploadState copyWith({
    File? localFile,
    String? downloadUrl,
    String? storagePath,
    bool? isUploading,
    String? error,
    bool resetError = false,
  }) {
    return UploadState(
      localFile: localFile ?? this.localFile,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      storagePath: storagePath ?? this.storagePath,
      isUploading: isUploading ?? this.isUploading,
      error: resetError ? null : (error ?? this.error),
    );
  }

  factory UploadState.initial() => const UploadState();
}

class UploadController extends StateNotifier<UploadState> {
  UploadController(this._picker, this._storageService)
    : super(UploadState.initial());

  final ImagePicker _picker;
  final StorageService _storageService;
  bool _cancelRequested = false;

  Future<bool> pickAndUpload(String uid, {ImageSource source = ImageSource.gallery}) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 90,
      );
      if (picked == null) {
        return false;
      }

      final file = File(picked.path);
      _cancelRequested = false;
      state = state.copyWith(
        localFile: file,
        isUploading: true,
        resetError: true,
      );

      final result = await _storageService.uploadOriginalImage(
        uid: uid,
        file: file,
      );

      if (_cancelRequested) {
        return false;
      }

      state = state.copyWith(
        downloadUrl: result.downloadUrl,
        storagePath: result.path,
        isUploading: false,
      );
      return true;
    } catch (error) {
      state = state.copyWith(isUploading: false, error: error.toString());
      rethrow;
    }
  }

  void cancelUpload() {
    if (!state.isUploading) return;
    _cancelRequested = true;
    state = state.copyWith(isUploading: false);
  }

  void clearError() {
    state = state.copyWith(error: null, resetError: true);
  }
}

final uploadControllerProvider =
    StateNotifierProvider<UploadController, UploadState>((ref) {
      final picker = ref.watch(imagePickerProvider);
      final storageService = ref.watch(storageServiceProvider);
      return UploadController(picker, storageService);
    });
