## AI Picture (Android-First)

This project delivers a production-ready Android experience for generating AI-enhanced profile photos with Flutter, Firebase, and Google Gemini. The same codebase can be launched on iOS, but **iOS builds are considered experimental** right now. Expect occasional visual glitches (e.g., notch overlaps, transition flicker) because the design has been optimized for Android phones/tablets. Ship Android; treat iOS as “best effort” until additional QA is performed.

---

## 1. Setup Instructions

### 1.1 Prerequisites

| Stack | Requirement |
| --- | --- |
| Flutter | 3.24+ with Dart 3.5+ |
| Android | Android Studio Flamingo+, Android SDK 34, USB debugging enabled |
| iOS (optional) | macOS + Xcode 15+ (expect UI issues) |
| Backend | Node.js 20, npm, Firebase CLI (`npm i -g firebase-tools`) |
| AI | Gemini API key (image generation enabled) |
| Windows-only | Enable **Developer Mode** (`start ms-settings:developers`) so Flutter can create plugin symlinks |

### 1.2 Firebase + Gemini

1. **Login & select project**
   ```bash
   firebase login
   firebase use <your-project-id>
   ```
2. **Generate platform configs**
   ```bash
   flutterfire configure --project=<your-project-id> --platforms=android,ios
   ```
   - Copies `google-services.json` + `GoogleService-Info.plist`
   - Regenerates `lib/firebase_options.dart`
3. **Initialize services (if new project)**
   ```bash
   firebase init firestore storage functions
   ```
4. **Install Function deps + set Gemini secret**
   ```bash
   cd functions
   npm install
   firebase functions:secrets:set GEMINI_API_KEY   # paste your key
   ```
   > **Never commit secrets.** `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, `functions/.runtimeconfig.json`, `serviceAccount.json`, `lib/firebase_options.dart`, `key.properties`, keystores (`*.keystore`, `*.jks`), certificates (`*.pem`, `*.p12`, `*.pfx`, `*.cer`, `*.mobileprovision`), and any `*.keys.json` files are ignored via `.gitignore`. We also ignore generated APKs/AABs so releases are produced per developer.
5. **Deploy backend**
   ```bash
   npm run build
   firebase deploy --only functions,firestore:rules,storage
   cd ..
   ```

### 1.3 Flutter App

1. **Install packages**
   ```bash
   flutter pub get
   ```
2. **Run on Android**
   ```bash
   flutter run -d android
   ```
3. **Build release APK**
   ```bash
   flutter build apk --release
   ```
   > If you ever `flutter clean` and `flutter pub get`, re-apply the `image_gallery_saver` patch by editing `…/image_gallery_saver-2.0.3/android/build.gradle` to set `compileSdkVersion 34`, `namespace`, and `kotlinOptions.jvmTarget = '17'`.
4. **(Optional) Run on iOS**
   ```bash
   cd ios && pod install && cd ..
   flutter run -d ios
   ```
   *Known issues:* tab bars may overlap, launch screen scaling is inconsistent, and some camera/scroll effects flicker. iOS builds are not officially supported yet.

### 1.4 Environment File

Create `.env` in the repo root:
```
GEMINI_API_KEY=AIza...yourKey...
```
The Flutter client reads this via `flutter_dotenv` to fail early when the key is missing (actual calls go through the Cloud Function).

---

## 2. Architecture Overview

```
┌─────────┐     ┌────────────┐     ┌─────────────┐     ┌────────────┐
│ Flutter │ ──▶ │ Cloud Func │ ──▶ │ Gemini API  │ ──▶ │ Firebase    │
└─────────┘     │ (Node/TS)  │     │ (image gen) │     │ Storage+DB │
                └────────────┘     └─────────────┘     └────────────┘
```

### Frontend (Flutter + Riverpod)

The app now follows a **Single Screen Architecture** with a window-like modal system.

| Screen / Component | Responsibilities |
| --- | --- |
| `HomeScreen` | The primary orchestrator. Handles image preview, generation flow, and acts as the container for all "window" overlays. Implements a custom `PopScope` to handle back navigation within the single-screen context. |
| `SceneSelectionModal` | A pop-out "window" for selecting scenes. Uses a `PageView` for horizontal sliding of scene options. Supports multi-selection (1-10 scenes) with visual feedback. |
| `HistoryModal` | A dedicated "window" for browsing all previously generated images. Features a grid layout with edge-to-edge scrolling and full-screen previews. |
| `FullScreenImageOverlay` | A specialized overlay for viewing images in full detail. Supports pinch-to-zoom (constrained to edges), pan, reset zoom animation, and high-quality downloading. |
| `ImageSourceModal` | A compact modal for choosing between Camera and Gallery inputs. |

### Key Features

- **Multi-Image Generation**: Generate 2 to 6 variations at once based on selected scenes.
- **Window-Like Experience**: Scene selection, History, and Upload flows appear as pop-out windows over the main content, preserving context.
- **Smart UI Transitions**: Fade-in/out, slide animations, and smooth zoom resets (`Tween<Matrix4>`).
- **Custom Warnings & Errors**:
  - **Scene Limit**: Fancy animated dialog when selecting 5+ scenes, with a "Don't show again" option.
  - **Regeneration**: Warning when generating new images would archive current ones.
  - **Error Handling**: Stylish error dialogs with copy-to-clipboard functionality for easier debugging.
- **Edge-to-Edge Display**: Intelligent image fitting (Cover/Contain) based on orientation to eliminate gray bars.

### Backend (Firebase)

| Component | Description |
| --- | --- |
| Cloud Function `generateProfilePicture` | Callable HTTPS function (Node 20 + TypeScript). Validates auth, downloads original image, calls `@google/generative-ai` with `gemini-2.5-flash-image`, uploads generated JPEG to Storage, writes metadata to Firestore, returns signed URL. |
| Firestore | `users/{uid}` roots session metadata; `users/{uid}/results/{resultId}` stores prompt, storage paths, signed URL, timestamps. |
| Storage | `users/{uid}/original/*` for uploads, `users/{uid}/generated/*` for AI output. |
| Secret Manager | Stores `GEMINI_API_KEY`. Cloud Function service account has `Secret Manager Secret Accessor`. |

---

## 3. Security Approach

1. **Authentication (Anonymous Firebase Auth)**
   - The app blocks UI until `ensureAuthProvider` resolves.
   - `request.auth.uid` is required by Firestore, Storage, and the callable Function.

2. **Data Isolation via Rules**
   ```txt
   match /users/{uid} {
     allow read, write: if request.auth != null && request.auth.uid == uid;
     match /results/{resultId} {
       allow read, write: if request.auth.uid == uid;
     }
   }
   ```
   - Storage mirrors the same pattern (`match /users/{uid}/{allPaths=**}`).

3. **Backend Enforcement**
   - Cloud Function re-fetches the original file using signed URLs, so clients never touch privileged credentials.
   - Only the Function talks to Gemini; the API key lives in Secret Manager.
   - MIME type normalization protects Gemini from unsupported `image/jpg` inputs.

4. **Transport & Logging**
   - All Firebase traffic is HTTPS.
   - Errors are surfaced in-app via a custom animated `ErrorDialog` with copy-to-clipboard for support.

5. **Platform Caveats**
   - Android is the reference platform (tested on API 26–34, phones + tablets).
   - iOS runs, but due to layout differences you may see navigation bar overlap, misaligned scrollbars, or splash-screen artifacts. Treat iOS as “beta”; file issues before shipping to App Store.

---

## 4. Additional Notes

- **Windows file locks**: If `flutter clean` fails to delete `.dart_tool`/`build`, close Android Studio/VS Code terminals or reboot to release handles.
- **image_gallery_saver patch**: Because the plugin is unmaintained, we manually bump its `compileSdkVersion` and `jvmTarget`. If you purge the pub cache, reapply the patch or migrate to a newer gallery saver package.
- **Logging & debugging**: `firebase functions:log --only generateProfilePicture` is invaluable when Gemini returns 4xx/5xx errors. Client toast messages intentionally avoid leaking API keys.

---

Happy building, and remember: Android is rock-solid today; iOS support will come once we iron out the remaining UI glitches. Let us know what you ship! 🎉
