 
import json
import logging
import os
import time
from typing import Any, Dict, Optional

from fastapi import FastAPI, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware

from scenario_runner import run_many as run_lca_for_scenarios

app = FastAPI(title="Brightway LCA Service")
logging.basicConfig(level=logging.INFO)
L = logging.getLogger(__name__)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def health() -> Dict[str, str]:
    return {"status": "ok"}

@app.post("/run_lca_all")
def run_all(payload: Dict[str, Any] = Body(...)) -> Dict[str, Any]:
    try:
        L.info("Received payload top-level keys: %s", list(payload.keys()))
    except Exception:
        pass

    scenarios = payload.get("scenarios")
    if not isinstance(scenarios, dict):
        raise HTTPException(
            status_code=400,
            detail="'scenarios' must be an object mapping names to {model: …}",
        )

    # Pick custom CF file: payload override > env var > default filename
    custom_cf_file: Optional[str] = payload.get("custom_cf_file") \
        or os.environ.get("CUSTOM_CF_FILE") \
        or "upsert_custom_cfs_from_table.xlsx"

    # Check presence, but do not crash if missing
    if custom_cf_file and not os.path.isfile(custom_cf_file):
        L.warning("Custom CF file not found: %s (proceeding without overlay)", custom_cf_file)
        custom_cf_file = None
    else:
        L.info("Using custom CF file: %s", custom_cf_file)

    try:
        start = time.perf_counter()
        results = run_lca_for_scenarios(
            scenarios=scenarios,
            custom_cf_file=custom_cf_file,
        )
        elapsed = time.perf_counter() - start

        L.info("Full results:\n%s", json.dumps(results, indent=2))
        L.info("Returning results for scenarios: %s", list(results.keys()))
        L.info("Time to compute LCA for %d scenarios: %.3f seconds", len(scenarios), elapsed)

        return results
    except Exception as e:
        L.exception("Exception in run_lca_for_scenarios")
        raise HTTPException(status_code=500, detail=f"LCA error: {e}") from e

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
# uvicorn main:app --reload
