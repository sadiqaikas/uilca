# File: model_ingest.py
from __future__ import annotations
import logging
from typing import Dict, Any, List, Tuple, Optional

L = logging.getLogger(__name__)


# --- Data structures ---
LoopEntry = Dict[str, Any]
LoopData = List[LoopEntry]


def validate_model(model: Dict[str, Any]) -> None:
    """Check that model has the required keys and structure."""
    if "processes" not in model or not isinstance(model["processes"], list):
        raise ValueError("Model must contain a 'processes' list")

    for proc in model["processes"]:
        if "id" not in proc:
            raise ValueError("Each process must have an 'id'")


def select_fu(
    model: Dict[str, Any],
    scenario_payload: Optional[Dict[str, Any]] = None
) -> Tuple[str, float]:
    """
    Decide the functional unit process and the scaling factor.
    Returns (fu_process_id, fu_scale).
    """
    fu_override = (scenario_payload or {}).get("fu_process")

    if fu_override:
        return fu_override, float(model.get("number_functional_units", 1))

    # else, try to detect from isFunctional
    marked = [p["id"] for p in model.get("processes", []) if p.get("isFunctional")]
    if len(marked) == 1:
        return marked[0], float(model.get("number_functional_units", 1))
    elif len(marked) > 1:
        raise ValueError(f"Multiple processes marked isFunctional: {marked}")

    # fallback: error if no explicit FU
    raise ValueError("No functional unit specified and none detected")


def build_loop_data(model: Dict[str, Any]) -> LoopData:
    """
    Convert model (from UI) into loop_data format:
    [{process, inputs[], outputs[], emissions[]}].
    Links inputs by matching product names to producing processes.
    """
    loop_data: LoopData = [
        {"process": p["id"], "inputs": [], "outputs": [], "emissions": []}
        for p in model.get("processes", [])
    ]
    by_id = {entry["process"]: entry for entry in loop_data}

    # pass 1: collect outputs & emissions
    ref_by_product: Dict[str, str] = {}
    for proc in model.get("processes", []):
        entry = by_id[proc["id"]]

        outs = proc.get("outputs", [])
        if outs:
            ref_name = outs[0]["name"]
            ref_by_product[ref_name] = proc["id"]
            for out in outs:
                entry["outputs"].append({
                    "name": out["name"],
                    "quantity": out["amount"],
                    "unit": out.get("unit", "unit")
                })

        for em in proc.get("emissions", []):
            if "flow_uuid" not in em:
                raise KeyError(f"Emission missing flow_uuid in process {proc['id']}")
            entry["emissions"].append({
                "flow_uuid": em["flow_uuid"],
                "quantity": em["amount"],
                "unit": em.get("unit", "kg")
            })

    # # pass 2: wire inputs to producers (if known)
    # for proc in model.get("processes", []):
    #     entry = by_id[proc["id"]]
    #     for inp in proc.get("inputs", []) or []:
    #         from_pid = ref_by_product.get(inp["name"])
    #         entry["inputs"].append({
    #             "name": inp["name"],
    #             "quantity": inp["amount"],   # sign handled later in DB layer
    #             "unit": inp.get("unit", "unit"),
    #             "from_process": from_pid
    #         })
    for proc in model.get("processes", []):
        entry = by_id[proc["id"]]
        for inp in proc.get("inputs", []) or []:
            from_pid = ref_by_product.get(inp["name"])
            if not from_pid:
                # This input has no producer in the model. It is likely a waste or a biosphere flow
                # from the source dataset. Skip it here to avoid auto-creating stub activities.
                L.debug("Skipping unlinked input on %s: %s", proc["id"], inp["name"])
                continue
            entry["inputs"].append({
                "name": inp["name"],
                "quantity": inp["amount"],
                "unit": inp.get("unit", "unit"),
                "from_process": from_pid,
            })

    return loop_data


def parse_model(
    model: Dict[str, Any],
    scenario_payload: Optional[Dict[str, Any]] = None
) -> Tuple[LoopData, str, float]:
    """
    Entry point: validate, select FU, and build loop_data.
    Returns (loop_data, fu_pid, fu_scale).
    """
    validate_model(model)
    fu_pid, fu_scale = select_fu(model, scenario_payload)
    loop_data = build_loop_data(model)
    L.debug("Parsed model: FU=%s, scale=%s, processes=%d",
            fu_pid, fu_scale, len(loop_data))
    return loop_data, fu_pid, fu_scale
