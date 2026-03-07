#!/usr/bin/env python3
"""Small GUI launcher for local backend services."""

from __future__ import annotations

import hashlib
import os
import queue
import signal
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk
from urllib.error import URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
VENV_DIR = ROOT / ".venv"
REQ_BASE = ROOT / "requirements-base.txt"
REQ_BRIGHTWAY = ROOT / "requirements-brightway.txt"
REQ_OPENLCA = ROOT / "requirements-openlca.txt"

BRIGHTWAY_DIR = ROOT / "brightway_backend"
OPENLCA_DIR = ROOT / "openlca_backend"


def _venv_python() -> Path:
    if os.name == "nt":
        return VENV_DIR / "Scripts" / "python.exe"
    return VENV_DIR / "bin" / "python"


def _venv_signature_file(name: str) -> Path:
    return VENV_DIR / f".requirements_{name}.sha256"


def _file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def _http_ok(url: str, timeout: float = 1.5) -> bool:
    req = Request(url, method="GET")
    try:
        with urlopen(req, timeout=timeout) as resp:
            return 200 <= resp.status < 500
    except (URLError, OSError):
        return False


class LauncherApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("EarlyLCA Backend Launcher")
        self.root.geometry("920x620")

        self.log_queue: queue.Queue[str] = queue.Queue()
        self.processes: dict[str, subprocess.Popen[str]] = {}
        self._setup_running = False

        self.brightway_port_var = tk.StringVar(value="8000")
        self.openlca_port_var = tk.StringVar(value="8001")
        self.openlca_ipc_url_var = tk.StringVar(
            value=os.environ.get("OPENLCA_IPC_URL", "http://localhost:8080")
        )

        self._build_ui()
        self.root.after(120, self._drain_log_queue)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self) -> None:
        frm = ttk.Frame(self.root, padding=12)
        frm.pack(fill=tk.BOTH, expand=True)

        ports = ttk.LabelFrame(frm, text="Configuration", padding=10)
        ports.pack(fill=tk.X)

        ttk.Label(ports, text="Brightway port").grid(row=0, column=0, sticky="w")
        ttk.Entry(ports, textvariable=self.brightway_port_var, width=10).grid(
            row=0, column=1, padx=(8, 20), sticky="w"
        )

        ttk.Label(ports, text="OpenLCA backend port").grid(row=0, column=2, sticky="w")
        ttk.Entry(ports, textvariable=self.openlca_port_var, width=10).grid(
            row=0, column=3, padx=(8, 20), sticky="w"
        )

        ttk.Label(ports, text="OpenLCA IPC URL").grid(row=0, column=4, sticky="w")
        ttk.Entry(ports, textvariable=self.openlca_ipc_url_var, width=28).grid(
            row=0, column=5, padx=(8, 0), sticky="w"
        )

        actions = ttk.Frame(frm, padding=(0, 12))
        actions.pack(fill=tk.X)

        ttk.Button(
            actions, text="Start Brightway", command=self.start_brightway
        ).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(
            actions, text="Start OpenLCA Bridge", command=self.start_openlca
        ).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(actions, text="Start Both", command=self.start_both).pack(
            side=tk.LEFT, padx=(0, 8)
        )
        ttk.Button(actions, text="Stop Brightway", command=self.stop_brightway).pack(
            side=tk.LEFT, padx=(0, 8)
        )
        ttk.Button(actions, text="Stop OpenLCA", command=self.stop_openlca).pack(
            side=tk.LEFT, padx=(0, 8)
        )
        ttk.Button(actions, text="Stop All", command=self.stop_all).pack(side=tk.LEFT)

        self.status_var = tk.StringVar(
            value="Ready. Click Start Brightway or Start OpenLCA Bridge."
        )
        ttk.Label(frm, textvariable=self.status_var).pack(fill=tk.X, pady=(0, 8))

        log_frame = ttk.LabelFrame(frm, text="Logs", padding=8)
        log_frame.pack(fill=tk.BOTH, expand=True)

        self.log = tk.Text(log_frame, wrap="word", height=24, state=tk.DISABLED)
        self.log.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        sb = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.log.yview)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.log.configure(yscrollcommand=sb.set)

        self._append_log("Launcher initialized.")
        self._append_log(f"Project root: {ROOT}")

    def _append_log(self, text: str) -> None:
        self.log.configure(state=tk.NORMAL)
        self.log.insert(tk.END, f"{text}\n")
        self.log.see(tk.END)
        self.log.configure(state=tk.DISABLED)

    def _queue_log(self, text: str) -> None:
        self.log_queue.put(text)

    def _drain_log_queue(self) -> None:
        while True:
            try:
                line = self.log_queue.get_nowait()
            except queue.Empty:
                break
            self._append_log(line.rstrip("\n"))
        self.root.after(120, self._drain_log_queue)

    def _read_process_output(self, name: str, proc: subprocess.Popen[str]) -> None:
        assert proc.stdout is not None
        for line in proc.stdout:
            self._queue_log(f"[{name}] {line.rstrip()}")
        code = proc.wait()
        self._queue_log(f"[{name}] exited with code {code}")

    def _validate_port(self, value: str, label: str) -> int:
        try:
            port = int(value)
        except ValueError as exc:
            raise ValueError(f"{label} must be an integer") from exc
        if port < 1 or port > 65535:
            raise ValueError(f"{label} must be in range 1..65535")
        return port

    def _run_blocking(self, cmd: list[str], cwd: Path, label: str) -> None:
        self._append_log(f"Running: {' '.join(cmd)}")
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            text=True,
            capture_output=True,
        )
        if proc.stdout:
            for line in proc.stdout.splitlines():
                self._append_log(f"[{label}] {line}")
        if proc.returncode != 0:
            if proc.stderr:
                for line in proc.stderr.splitlines():
                    self._append_log(f"[{label}] {line}")
            raise RuntimeError(f"{label} failed with exit code {proc.returncode}")

    def _ensure_venv_and_requirements(self, req_path: Path, marker_name: str) -> bool:
        if self._setup_running:
            self._append_log("Setup already running. Please wait.")
            return False

        self._setup_running = True
        self.status_var.set("Preparing Python environment...")
        try:
            if not VENV_DIR.exists():
                self._append_log("Creating .venv...")
                self._run_blocking(
                    [sys.executable, "-m", "venv", str(VENV_DIR)],
                    cwd=ROOT,
                    label="venv",
                )

            py = _venv_python()
            if not py.exists():
                raise RuntimeError(f"Virtualenv python not found at {py}")

            base_sig = _file_sha256(REQ_BASE)
            req_sig = _file_sha256(req_path)
            combined_sig = hashlib.sha256((base_sig + req_sig).encode("utf-8")).hexdigest()
            sig_file = _venv_signature_file(marker_name)
            current_sig = sig_file.read_text().strip() if sig_file.exists() else ""

            if current_sig != combined_sig:
                self._append_log(f"Installing dependencies from {req_path.name}...")
                self._run_blocking(
                    [str(py), "-m", "pip", "install", "--upgrade", "pip"],
                    cwd=ROOT,
                    label="pip",
                )
                self._run_blocking(
                    [str(py), "-m", "pip", "install", "-r", str(req_path)],
                    cwd=ROOT,
                    label="pip",
                )
                sig_file.write_text(combined_sig + "\n", encoding="utf-8")
                self._append_log("Dependency installation complete.")
            else:
                self._append_log(f"Dependencies already up to date for {req_path.name}.")

            return True
        except Exception as exc:
            self.status_var.set("Setup failed.")
            self._append_log(f"ERROR: {exc}")
            messagebox.showerror("Setup failed", str(exc))
            return False
        finally:
            self._setup_running = False

    def _start_service(
        self,
        *,
        name: str,
        req_path: Path,
        marker_name: str,
        cwd: Path,
        module_app: str,
        port: int,
        extra_env: dict[str, str] | None = None,
    ) -> None:
        if name in self.processes and self.processes[name].poll() is None:
            self._append_log(f"{name} is already running.")
            return

        if not self._ensure_venv_and_requirements(req_path, marker_name):
            return

        py = _venv_python()
        env = os.environ.copy()
        if extra_env:
            env.update(extra_env)

        cmd = [
            str(py),
            "-m",
            "uvicorn",
            module_app,
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
        ]

        self._append_log(f"Starting {name} on http://127.0.0.1:{port}")
        proc = subprocess.Popen(
            cmd,
            cwd=str(cwd),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
        )
        self.processes[name] = proc
        threading.Thread(
            target=self._read_process_output, args=(name, proc), daemon=True
        ).start()
        self.status_var.set(f"{name} started on port {port}.")

    def start_brightway(self) -> None:
        try:
            port = self._validate_port(self.brightway_port_var.get().strip(), "Brightway port")
        except ValueError as exc:
            messagebox.showerror("Invalid configuration", str(exc))
            return
        self._start_service(
            name="brightway",
            req_path=REQ_BRIGHTWAY,
            marker_name="brightway",
            cwd=BRIGHTWAY_DIR,
            module_app="main:app",
            port=port,
        )

    def start_openlca(self) -> None:
        try:
            port = self._validate_port(
                self.openlca_port_var.get().strip(), "OpenLCA backend port"
            )
        except ValueError as exc:
            messagebox.showerror("Invalid configuration", str(exc))
            return

        ipc_url = self.openlca_ipc_url_var.get().strip() or "http://localhost:8080"
        if not _http_ok(ipc_url):
            self._append_log(
                f"Warning: openLCA IPC not reachable at {ipc_url}. "
                "Backend will start, but requests may fail until openLCA IPC is on."
            )

        self._start_service(
            name="openlca",
            req_path=REQ_OPENLCA,
            marker_name="openlca",
            cwd=OPENLCA_DIR,
            module_app="open_ipc_backend:app",
            port=port,
            extra_env={"OPENLCA_IPC_URL": ipc_url},
        )

    def start_both(self) -> None:
        self.start_brightway()
        self.start_openlca()

    def _terminate(self, name: str) -> None:
        proc = self.processes.get(name)
        if proc is None:
            return
        if proc.poll() is not None:
            return

        self._append_log(f"Stopping {name}...")
        try:
            if os.name == "nt":
                proc.terminate()
            else:
                proc.send_signal(signal.SIGTERM)
            proc.wait(timeout=6)
        except subprocess.TimeoutExpired:
            self._append_log(f"{name} did not stop quickly; killing it.")
            proc.kill()
        finally:
            self.status_var.set(f"{name} stopped.")

    def stop_brightway(self) -> None:
        self._terminate("brightway")

    def stop_openlca(self) -> None:
        self._terminate("openlca")

    def stop_all(self) -> None:
        self._terminate("brightway")
        self._terminate("openlca")
        self.status_var.set("All services stopped.")

    def _on_close(self) -> None:
        self.stop_all()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    app = LauncherApp(root)
    _ = app
    root.mainloop()


if __name__ == "__main__":
    main()
