import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system);

  void cycleMode() {
    switch (state) {
      case ThemeMode.system:
        state = ThemeMode.light;
        break;
      case ThemeMode.light:
        state = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        state = ThemeMode.system;
        break;
    }
  }

  void setMode(ThemeMode mode) {
    state = mode;
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(),
);

