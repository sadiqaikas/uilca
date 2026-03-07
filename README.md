# InstantLCA

A new Flutter project.

## Local One-Click Run 

Run the entire local stack (Flutter frontend + Brightway backend + OpenLCA backend):

- macOS: double-click `start_local_stack.command`
- Windows: double-click `start_local_stack.bat`

This will:

1. Create/install backend Python environment automatically.
2. Start Brightway backend on `http://127.0.0.1:8000`.
3. Start OpenLCA backend on `http://127.0.0.1:8001`.
4. Serve prebuilt frontend (`build/web`) on `http://127.0.0.1:3000`.

User prerequisites:

- Python 3.12+
- Internet connection on first run (to download Python backend dependencies)

-Ensure the OpenLCA IPC server is started for Openlca use (Tools → Developer Tools → IPC Server) 

Stop the local stack with `Ctrl+C` in the launcher terminal window.


## Build Frontend Once (Maintainer Step)

Run this only when you change frontend code and want to refresh `build/web`:

```bash
flutter pub get
flutter build web --release --pwa-strategy=none
```

After building, commit `build/web` so end users can run without Flutter.

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


To show all processes in a product system, click the button as shown in the image below.
<img width="891" height="154" alt="image" src="https://github.com/user-attachments/assets/23a04f6d-c4bc-4990-95d5-eb2a639afb98" />
