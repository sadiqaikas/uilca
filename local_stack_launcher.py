#!/usr/bin/env python3
"""One-click local launcher for EarlyLCA frontend + backends.

Starts:
  - Brightway backend on 127.0.0.1:8000
  - OpenLCA IPC backend on 127.0.0.1:8001
  - Static frontend from build/web on 127.0.0.1:3000
"""

from __future__ import annotations

import hashlib
import os
import signal
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen


REPO_ROOT = Path(__file__).resolve().parent
BACKEND_ROOT = REPO_ROOT / "python backend"
BACKEND_VENV = BACKEND_ROOT / ".venv"
BACKEND_REQ_ALL = BACKEND_ROOT / "requirements-all.txt"
WEB_BUILD_DIR = REPO_ROOT / "build" / "web"

BRIGHTWAY_DIR = BACKEND_ROOT / "brightway_backend"
OPENLCA_DIR = BACKEND_ROOT / "openlca_backend"

BRIGHTWAY_PORT = 8000
OPENLCA_PORT = 8001
FRONTEND_PORT = 3000
OPENLCA_IPC_URL = os.environ.get("OPENLCA_IPC_URL", "http://localhost:8080")


def log(msg: str) -> None:
    print(msg, flush=True)


def _venv_python() -> Path:
    if os.name == "nt":
        return BACKEND_VENV / "Scripts" / "python.exe"
    return BACKEND_VENV / "bin" / "python"


def _is_port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.3)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def _ensure_free_ports() -> None:
    conflicts = [p for p in (BRIGHTWAY_PORT, OPENLCA_PORT, FRONTEND_PORT) if _is_port_in_use(p)]
    if conflicts:
        joined = ", ".join(str(p) for p in conflicts)
        raise RuntimeError(
            f"Port(s) already in use: {joined}. "
            "Close the existing processes or change ports in local_stack_launcher.py."
        )


def _requirements_signature() -> str:
    req_files = sorted(BACKEND_ROOT.glob("requirements*.txt"))
    h = hashlib.sha256()
    for path in req_files:
        h.update(path.name.encode("utf-8"))
        h.update(b"\0")
        h.update(path.read_bytes())
        h.update(b"\0")
    h.update(sys.version.encode("utf-8"))
    return h.hexdigest()


def _ensure_backend_env() -> None:
    if not BACKEND_ROOT.exists():
        raise RuntimeError(f"Missing backend folder: {BACKEND_ROOT}")
    if not BACKEND_REQ_ALL.exists():
        raise RuntimeError(f"Missing requirements file: {BACKEND_REQ_ALL}")

    if not BACKEND_VENV.exists():
        log("[setup] Creating backend virtual environment...")
        subprocess.run(
            [sys.executable, "-m", "venv", str(BACKEND_VENV)],
            cwd=str(BACKEND_ROOT),
            check=True,
        )

    py = _venv_python()
    if not py.exists():
        raise RuntimeError(f"Virtualenv python not found at: {py}")

    sig_file = BACKEND_VENV / ".requirements_all.sha256"
    current = sig_file.read_text(encoding="utf-8").strip() if sig_file.exists() else ""
    needed = _requirements_signature()

    if current == needed:
        log("[setup] Backend Python dependencies already up to date.")
        return

    log("[setup] Installing backend dependencies...")
    subprocess.run(
        [str(py), "-m", "pip", "install", "-r", str(BACKEND_REQ_ALL)],
        cwd=str(BACKEND_ROOT),
        check=True,
    )
    sig_file.write_text(needed + "\n", encoding="utf-8")
    log("[setup] Backend dependencies installed.")


def _ensure_web_build_exists() -> None:
    index_file = WEB_BUILD_DIR / "index.html"
    if index_file.exists():
        return
    raise RuntimeError(
        "Missing frontend build artifact at build/web/index.html.\n"
        "Build it once on a machine with Flutter:\n"
        "  flutter pub get\n"
        "  flutter build web --release --pwa-strategy=none"
    )


def _stream_output(name: str, proc: subprocess.Popen[str]) -> None:
    assert proc.stdout is not None
    for line in proc.stdout:
        log(f"[{name}] {line.rstrip()}")
    code = proc.wait()
    log(f"[{name}] exited with code {code}")


def _start_process(
    *,
    name: str,
    cmd: list[str],
    cwd: Path,
    env: dict[str, str] | None = None,
) -> subprocess.Popen[str]:
    log(f"[start] {name}: {' '.join(cmd)}")
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        env=env or os.environ.copy(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )
    threading.Thread(target=_stream_output, args=(name, proc), daemon=True).start()
    return proc


def _http_up(url: str, timeout: float = 1.5) -> bool:
    req = Request(url, method="GET")
    try:
        with urlopen(req, timeout=timeout) as resp:
            return 200 <= resp.status < 500
    except (URLError, OSError):
        return False


def _wait_for_http(url: str, *, label: str, seconds: int = 90) -> bool:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if _http_up(url):
            log(f"[ready] {label} at {url}")
            return True
        time.sleep(0.5)
    log(f"[warn] {label} did not become ready at {url} within {seconds}s.")
    return False


def _stop_process(name: str, proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    log(f"[stop] {name}...")
    try:
        if os.name == "nt":
            proc.terminate()
        else:
            proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        log(f"[stop] {name} did not stop quickly. Killing...")
        proc.kill()


def main() -> int:
    log("EarlyLCA local launcher starting...")
    log(f"Repo: {REPO_ROOT}")

    processes: dict[str, subprocess.Popen[str]] = {}
    return_code = 0

    try:
        _ensure_free_ports()
        _ensure_backend_env()
        _ensure_web_build_exists()

        py = _venv_python()

        processes["brightway"] = _start_process(
            name="brightway",
            cmd=[
                str(py),
                "-m",
                "uvicorn",
                "main:app",
                "--host",
                "127.0.0.1",
                "--port",
                str(BRIGHTWAY_PORT),
            ],
            cwd=BRIGHTWAY_DIR,
        )

        if not _http_up(OPENLCA_IPC_URL):
            log(
                f"[warn] OpenLCA IPC is not reachable at {OPENLCA_IPC_URL}. "
                "OpenLCA backend will start, but OpenLCA requests may fail until IPC is running."
            )

        openlca_env = os.environ.copy()
        openlca_env["OPENLCA_IPC_URL"] = OPENLCA_IPC_URL
        processes["openlca"] = _start_process(
            name="openlca",
            cmd=[
                str(py),
                "-m",
                "uvicorn",
                "open_ipc_backend:app",
                "--host",
                "127.0.0.1",
                "--port",
                str(OPENLCA_PORT),
            ],
            cwd=OPENLCA_DIR,
            env=openlca_env,
        )

        # Wait briefly for backend readiness (non-fatal for openLCA IPC runtime).
        _wait_for_http(
            f"http://127.0.0.1:{BRIGHTWAY_PORT}/",
            label="Brightway backend",
            seconds=45,
        )
        _wait_for_http(
            f"http://127.0.0.1:{OPENLCA_PORT}/health",
            label="OpenLCA backend",
            seconds=45,
        )

        frontend_url = f"http://127.0.0.1:{FRONTEND_PORT}"
        processes["frontend"] = _start_process(
            name="frontend",
            cmd=[
                sys.executable,
                "-m",
                "http.server",
                str(FRONTEND_PORT),
                "--bind",
                "127.0.0.1",
                "--directory",
                str(WEB_BUILD_DIR),
            ],
            cwd=REPO_ROOT,
        )

        if _wait_for_http(frontend_url, label="Frontend", seconds=120):
            try:
                webbrowser.open(frontend_url)
            except Exception:
                pass
        else:
            log(f"[info] Open browser manually: {frontend_url}")

        log("")
        log("Local stack is running.")
        log(f"Frontend:  {frontend_url}")
        log(f"Brightway: http://127.0.0.1:{BRIGHTWAY_PORT}")
        log(f"OpenLCA:   http://127.0.0.1:{OPENLCA_PORT}")
        log("Press Ctrl+C to stop all services.")

        while True:
            time.sleep(1.0)
            for name, proc in processes.items():
                code = proc.poll()
                if code is not None:
                    raise RuntimeError(f"{name} process exited unexpectedly with code {code}")

    except KeyboardInterrupt:
        log("Interrupted. Stopping services...")
        return_code = 130
    except Exception as exc:
        log(f"[error] {exc}")
        return_code = 1
    else:
        return_code = 0
    finally:
        for name, proc in reversed(list(processes.items())):
            _stop_process(name, proc)

    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
