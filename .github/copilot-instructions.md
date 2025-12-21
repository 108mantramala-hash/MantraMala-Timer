jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
# MantraMala Timer – AI Agent Instructions

## Project Overview
MantraMala Timer is a single-file Flutter app for timer-based mantra counting. All app logic is in [lib/main.dart](lib/main.dart). The app uses a timer (not manual taps) to increment counts, with a premium dark UI and persistent state.

## Architecture & Patterns
- **Single-file design:** All UI, state, and logic in [lib/main.dart](lib/main.dart). Do not split files unless explicitly requested.
- **State:** Managed in `_MantraMalaHomeState` using `StatefulWidget` and `SharedPreferences` for persistence.
- **Timer-based counting:** Uses `Timer.periodic` to increment the mantra count at user-configurable intervals (1–60s). Manual tap counting is disabled.
- **Audio:**
  - Audio session is always configured as `.ambient` (see `AudioSessionConfiguration`) to suppress Android Live Caption notifications.
  - Tap sounds are globally disabled (`_tapClickSoundEnabled = false`).
  - Bell sound plays once on completion.
- **Persistence:** All state changes are saved via `_saveData()` after every update.
- **Review prompt:** In-app review is triggered only after 3+ days and 10+ mantras, and only once.

## UI/UX Conventions
- **Color palette:** Deep navy backgrounds, gold gradients for progress, and light text. See `GradientCircleProgressPainter` for arc rendering.
- **Custom painters:** Use `SweepGradient` for progress arcs. Return early if progress is zero.
- **Haptics:** Light impact on count, heavy impact (3x) on completion if enabled.
- **Settings:** Full-page navigation, not modal. Completion sheet offers reset/increase target.

## Build, Release & Testing
- **Versioning:** Update both name and code in `pubspec.yaml` for every release. Android auto-syncs from this file.
- **Build:** Use [build_release.ps1](build_release.ps1) to automate builds and organize outputs. Outputs are in `releases/YYYY-MM-DD/vX.X.X/`.
- **Signing:** Never commit `android/app/upload-keystore.jks` or `android/key.properties`. Credentials are in `RELEASE_SIGNING.md`.
- **Build commands:**
  - `flutter build appbundle --release` (AAB)
  - `flutter build apk --release` (APK)
  - Use provided PowerShell scripts for verification and packaging.
- **Testing:** Use `flutter run` for hot reload. If audio assets fail, run `flutter clean ; flutter pub get`.

## Project-Specific Conventions
- **Presets:** Update `final List<int> presets = [...]` in [lib/main.dart](lib/main.dart) to change preset counts.
- **Audio:** Replace files in `assets/sounds/` and run `flutter pub get` to refresh.
- **Settings:** Add new variables to `_MantraMalaHomeState`, load/save in `_loadData()`/`_saveData()`, and update the `SettingsPage` UI.
- **Linting:** Uses `flutter_lints` defaults. No custom rules.

## Critical Don'ts
- Do **not** split [lib/main.dart](lib/main.dart) without user request.
- Do **not** enable tap sounds.
- Do **not** remove `.ambient` audio session config.
- Do **not** use `flutter clean` unless necessary (breaks audio asset loading).
- Do **not** commit signing keys or credentials.

## Key Files
- [lib/main.dart](lib/main.dart): All app logic and UI
- [pubspec.yaml](pubspec.yaml): Dependencies and versioning
- [build_release.ps1](build_release.ps1): Automated build/release script
- [RELEASE_SIGNING.md](RELEASE_SIGNING.md): Signing and credential info
- [PLAY_STORE_SUBMISSION.md](PLAY_STORE_SUBMISSION.md): Store listing templates

## Integrations
- UPI: `upi://pay?pa=6472084641@icici&pn=MantraMala&cu=INR`
- Ko-fi: https://ko-fi.com/mantramala
- Privacy Policy: https://sites.google.com/view/mantramala-privacy/
