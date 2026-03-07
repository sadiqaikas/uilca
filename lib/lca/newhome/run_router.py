"""Small router for selecting the LCA execution backend."""

from __future__ import annotations

import inspect
from collections.abc import Awaitable, Callable
from typing import Any


Runner = Callable[[], Any | Awaitable[Any]]


async def run_router(
    run_mode: str,
    run_openlca_ipc: Runner,
    run_brightway2: Runner,
) -> Any:
    """Route an LCA run request to the selected backend runner.

    Supported values for ``run_mode``:
    - ``openlca_ipc``
    - ``brightway2``
    """
    normalized = (run_mode or "").strip().lower()

    if normalized in {"openlca_ipc", "openlca-ipc", "openlca"}:
        return await _resolve_runner(run_openlca_ipc)

    if normalized in {"brightway2", "brightway"}:
        return await _resolve_runner(run_brightway2)

    raise ValueError(
        "Unsupported run mode. Expected 'openlca_ipc' or 'brightway2', "
        f"received '{run_mode}'.",
    )


async def _resolve_runner(runner: Runner) -> Any:
    """Execute either a sync or async runner and return its result."""
    result = runner()
    if inspect.isawaitable(result):
        return await result
    return result
