# earlylca

A new Flutter project.

## Local One-Click Run (No Firebase)

Run the entire local stack (Flutter frontend + Brightway backend + OpenLCA backend):

- macOS: double-click `start_local_stack.command`
- Windows: double-click `start_local_stack.bat`

This will:

1. Create/install backend Python environment automatically.
2. Start Brightway backend on `http://127.0.0.1:8000`.
3. Start OpenLCA backend on `http://127.0.0.1:8001`.
4. Start Flutter web frontend on `http://127.0.0.1:3000`.

Prerequisites:

- Python 3.12+
- Flutter SDK with `flutter` available in `PATH`
- Internet connection on first run (to download Python/Flutter dependencies)

Stop the local stack with `Ctrl+C` in the launcher terminal window.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Backend Setup

Python backend setup and run instructions are documented in:

- `python backend/README.md`

One-click launcher scripts are included in `python backend/`:

- `start_backend.command` (macOS)
- `start_backend.bat` (Windows)
