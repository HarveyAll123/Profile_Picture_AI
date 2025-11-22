import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'providers/theme_mode_provider.dart';
import 'screens/gallery_screen.dart';
import 'screens/home_screen.dart';
import 'screens/view_result_screen.dart';
import 'services/firebase_initializer.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      // Do not log the key value, only that it's missing.
      // The app can still run, but Gemini-based features will fail fast.
      // You can surface a UI warning elsewhere if desired.
      // ignore: avoid_print
      print(
        'GEMINI_API_KEY is not set in .env; Gemini features will be disabled.',
      );
}
  } catch (error) {
    // ignore: avoid_print
    print('Failed to load .env file: $error');
  }

  await FirebaseInitializer.ensureInitialized();
  runApp(const ProviderScope(child: ProfilePicApp()));
}

class ProfilePicApp extends ConsumerWidget {
  const ProfilePicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'AI Profile Picture Generator',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      initialRoute: HomeScreen.routeName,
      routes: {
        HomeScreen.routeName: (_) => const HomeScreen(),
        GalleryScreen.routeName: (_) => const GalleryScreen(),
        ViewResultScreen.routeName: (_) => const ViewResultScreen(),
      },
    );
  }
}
