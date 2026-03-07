# Backend Setup Guide

If you want one click for the full local app stack (frontend + backends),
use the repo-root scripts:

- `start_local_stack.command` (macOS)
- `start_local_stack.bat` (Windows)

The full-stack launcher installs dependencies automatically and requires internet on first run.
It serves frontend files from `build/web`, so end users do not need Flutter installed.

This project has two Python backends:

1. `brightway_backend` (Brightway2 LCA runner)
2. `openlca_backend` (openLCA IPC bridge)

They can run independently. If you run both at the same time, use different ports.

## Quick Start (One Click)

macOS:

1. Double-click `start_backend.command`
2. In the launcher window, click:
   - `Start Brightway`, or
   - `Start OpenLCA Bridge`, or
   - `Start Both`

Windows:

1. Double-click `start_backend.bat`
2. Use the same launcher buttons.

Notes:

- The launcher automatically creates `.venv` and installs requirements on first run.
- OpenLCA bridge still requires openLCA desktop IPC to be running (default `http://localhost:8080`).

## 1) Python Version

Tested with Python `3.12`.

## 2) Create Environment

```bash
cd "python backend"
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
```

## 3) Install Dependencies

Choose one:

```bash
# Brightway backend only
pip install -r requirements-brightway.txt

# openLCA backend only
pip install -r requirements-openlca.txt

# Both backends + converter utilities
pip install -r requirements-all.txt
```

Converter utility only (optional):

```bash
pip install -r requirements-converter.txt
```

## 4) Run Brightway Backend

```bash
cd "python backend/brightway_backend"
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Health check:

```bash
curl http://localhost:8000/
```

Main endpoint:

- `POST /run_lca_all`

Optional env var:

- `CUSTOM_CF_FILE` (path to custom CF Excel file)

## 5) Run OpenLCA Backend

Before running this backend, start openLCA desktop and enable IPC (default URL is `http://localhost:8080`).

```bash
cd "python backend/openlca_backend"
OPENLCA_IPC_URL=http://localhost:8080 uvicorn open_ipc_backend:app --host 0.0.0.0 --port 8001 --reload
```

Health check:

```bash
curl http://localhost:8001/health
```

Main endpoints:

- `GET /openlca/product-systems`
- `GET /openlca/impact-methods`
- `POST /openlca/run-scenarios`

Optional env vars:

- `OPENLCA_IPC_URL`
- `OPENLCA_IMPACT_METHOD_ID`
- `OPENLCA_IMPACT_METHOD_NAME`

## 6) Common Issues

- If both backends use port `8000`, one will fail to start. Run OpenLCA backend on `8001` (or another free port).
- If OpenLCA backend returns import errors, install `requirements-openlca.txt` in the active virtual environment.
- If Brightway backend fails on import from `bw_database`, verify `python backend/brightway_backend/bw_database.py` contains the expected function implementations (`create_db`, `ensure_biosphere`, `choose_method`, `load_custom_cfs_from_table`).
- If macOS blocks `start_backend.command`, run once in Terminal: `chmod +x "python backend/start_backend.command"`.

## 7) Pre-push Checklist

1. Start Brightway backend and hit `GET /`.
2. Start OpenLCA backend (with openLCA IPC running) and hit `GET /health`.
3. Confirm frontend backend URLs match the ports you run.
