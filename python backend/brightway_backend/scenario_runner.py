
# File: (main module that contains run_single/run_many)
from __future__ import annotations
import logging
from typing import Dict, Any, List, Tuple, Optional
import json
import hashlib
import math
import numpy as np
import bw2data as bd
from bw2calc.lca import LCA

from model_ingest import parse_model
from bw_database import (
    create_db,
    ensure_biosphere,
    choose_method,                  # returns official method only
    load_custom_cfs_from_table,     # reads Excel into memory, no overlays
)

L = logging.getLogger(__name__)

IMPACT_METHODS: List[Tuple[str, str, str]] = [
    ("ReCiPe 2016 v1.03, midpoint (H)", "climate change", "global warming potential (GWP1000)"),
    ("ReCiPe 2016 v1.03, midpoint (H)", "photochemical oxidant formation: human health", "photochemical oxidant formation potential: humans (HOFP)"),
    ("ReCiPe 2016 v1.03, midpoint (H)", "ecotoxicity: freshwater", "freshwater ecotoxicity potential (FETP)"),
    ("ReCiPe 2016 v1.03, midpoint (H)", "eutrophication: freshwater", "freshwater eutrophication potential (FEP)"),
    ("ReCiPe 2016 v1.03, midpoint (H)",
     "photochemical oxidant formation: terrestrial ecosystems",
     "photochemical oxidant formation potential: ecosystems (EOFP)"),
    ("ReCiPe 2016 v1.03, midpoint (H)", "acidification: terrestrial", "terrestrial acidification potential (TAP)"),
]

# Small numerical tolerance to avoid dropping tiny but non-zero flows
_TOL = 1e-18

# New: methods for which we take totals directly from the flow contributions
_TARGET_FLOW_TOTAL_METHODS = {
    "ReCiPe 2016 v1.03, midpoint (H), ecotoxicity: freshwater, freshwater ecotoxicity potential (FETP)"
}

def _characterised_contributions(
    lca: LCA,
    method: Tuple[str, str, str],
    extra_cfs: Optional[Dict[Tuple[str, str], Tuple[float, str]]] = None,
) -> Tuple[float, float, List[Tuple[str, float]]]:
    """
    Return (base_total, extra_total, top3).

    base_total: total from the official method only. Taken directly from lca.score
                which is Brightway's own characterisation of the solved system.
    extra_total: total from custom CFs applied to the solved biosphere amounts v = B·s,
                 excluding any flows already in the official method.
    top3: top three biosphere flow contributors across both sets.
    """
    # Solved supply and biosphere
    s = np.asarray(lca.supply_array).ravel()
    B = lca.biosphere_matrix.tocsr()
    v = np.asarray(B.dot(s)).ravel()  # solved amount for each biosphere flow

    # Load official method entries and key set
    m = bd.Method(method)
    entries = m.load()
    base_cf_map: Dict[Tuple[str, str], float] = {}
    for t in entries:
        if len(t) == 3:
            fk, v_cf, _u = t
        else:
            fk, v_cf = t
        base_cf_map[(fk[0], fk[1])] = float(v_cf)
    base_keys = set(base_cf_map.keys())

    # Base total is Brightway's score for the solved system
    base_total = float(lca.score)

    # Build combined list for ranking, and compute extra total on v
    contribs_all: List[Tuple[str, float]] = []

    # Base flows for ranking
    for (dbn, code), cf in base_cf_map.items():
        idx = lca.biosphere_dict.get((dbn, code))
        if idx is None:
            continue
        amt = float(v[idx])
        if abs(amt) < _TOL:
            continue
        val = amt * float(cf)
        if val:
            try:
                act = bd.get_activity((dbn, code))
                label = f"{act.get('name', code)} [{dbn}]"
            except Exception:
                label = f"{code} [{dbn}]"
            contribs_all.append((label, val))

    # Custom flows on solved v, excluding overlaps
    extra_total = 0.0
    if extra_cfs:
        for (dbn, code), (cf_val, _u) in extra_cfs.items():
            if (dbn, code) in base_keys:
                # never double count a flow that the base method already covers
                continue
            idx = lca.biosphere_dict.get((dbn, code))
            if idx is None:
                continue
            amt = float(v[idx])
            if abs(amt) < _TOL:
                continue
            val = amt * float(cf_val)
            if val:
                extra_total += val
                try:
                    act = bd.get_activity((dbn, code))
                    label = f"{act.get('name', code)} [{dbn}]"
                except Exception:
                    label = f"{code} [{dbn}]"
                contribs_all.append((label, val))

    contribs_all.sort(key=lambda x: abs(x[1]), reverse=True)
    top3 = contribs_all[:3]
    return base_total, extra_total, top3

def _top3_biosphere_flows(
    lca: LCA,
    method: Tuple[str, str, str],
    extra_cfs: Optional[Dict[Tuple[str, str], Tuple[float, str]]] = None,
) -> List[Tuple[str, float]]:
    _, _, top3 = _characterised_contributions(lca, method, extra_cfs)
    return top3

def _process_contributions_table(
    lca: LCA,
    method: Tuple[str, str, str],
    extra_cfs: Optional[Dict[Tuple[str, str], Tuple[float, str]]] = None,
) -> List[Tuple[str, float]]:
    """
    Per-process characterised contributions including custom CFs.

    Base part: per-unit characterised inventory CI_per_unit = C · B,
               then weight by solved supply s once.
    Custom part: for flows not in official method, add cf * B_row per unit,
                 then weight by s once.
    """
    C = lca.characterization_matrix.tocsr()
    B = lca.biosphere_matrix.tocsr()
    CI_per_unit = (C.dot(B)).tocsr()  # per-unit characterised inventory

    s = np.asarray(lca.supply_array).ravel()
    base_cols = np.asarray(CI_per_unit.sum(axis=0)).ravel()

    # keys covered by the official method
    m = bd.Method(method)
    base_entries = m.load()
    base_keys = {(t[0][0], t[0][1]) for t in base_entries}

    # extras per unit of each process
    extra_cols = np.zeros(B.shape[1], dtype=float)
    if extra_cfs:
        for (dbn, code), (cf_val, _u) in extra_cfs.items():
            if (dbn, code) in base_keys:
                continue
            idx = lca.biosphere_dict.get((dbn, code))
            if idx is None:
                continue
            row = B.getrow(idx)
            if row.nnz:
                extra_cols += float(cf_val) * row.toarray().ravel()

    col_sums = base_cols + extra_cols
    contrib = col_sums * s  # apply s exactly once

    # map indices back to activity labels
    rev_act = {idx: key for key, idx in lca.activity_dict.items()}
    rows: List[Tuple[str, float]] = []
    for j, val in enumerate(contrib):
        if not val:
            continue
        key = rev_act.get(j)
        if key is not None:
            try:
                act = bd.get_activity(key)
                label = f"{act.get('name', key[1])} [{key[0]}]"
            except Exception:
                label = f"{key[1]} [{key[0]}]"
        else:
            label = f"(unknown activity {j})"
        rows.append((label, float(val)))

    rows.sort(key=lambda x: abs(x[1]), reverse=True)
    return rows

def _flow_contributions_table(
    lca: LCA,
    method: Tuple[str, str, str],
    extra_cfs: Optional[Dict[Tuple[str, str], Tuple[float, str]]] = None,
) -> List[Tuple[str, float, str]]:
    """
    Full list of biosphere flow contributions for a method plus any custom CFs.
    Returns [(label, value, source)], where source is 'base' or 'custom'.
    Computed on solved amounts v = B · s to stay consistent with totals.
    """
    s = np.asarray(lca.supply_array).ravel()
    B = lca.biosphere_matrix.tocsr()
    v = np.asarray(B.dot(s)).ravel()

    m = bd.Method(method)
    entries = m.load()

    base_cf_map: Dict[Tuple[str, str], float] = {}
    for t in entries:
        if len(t) == 3:
            fk, v_cf, _u = t
        else:
            fk, v_cf = t
        base_cf_map[(fk[0], fk[1])] = float(v_cf)

    rows: List[Tuple[str, float, str]] = []

    # base flows
    for (dbn, code), cf in base_cf_map.items():
        idx = lca.biosphere_dict.get((dbn, code))
        if idx is None:
            continue
        amt = float(v[idx])
        if abs(amt) < _TOL:
            continue
        val = amt * float(cf)
        if val:
            try:
                act = bd.get_activity((dbn, code))
                label = f"{act.get('name', code)} [{dbn}]"
            except Exception:
                label = f"{code} [{dbn}]"
            rows.append((label, val, "base"))

    # custom flows for missing ones only
    if extra_cfs:
        base_keys = set(base_cf_map.keys())
        for (dbn, code), (cf_val, _u) in extra_cfs.items():
            if (dbn, code) in base_keys:
                continue
            idx = lca.biosphere_dict.get((dbn, code))
            if idx is None:
                continue
            amt = float(v[idx])
            if abs(amt) < _TOL:
                continue
            val = amt * float(cf_val)
            if val:
                try:
                    act = bd.get_activity((dbn, code))
                    label = f"{act.get('name', code)} [{dbn}]"
                except Exception:
                    label = f"{code} [{dbn}]"
                rows.append((label, val, "custom"))

    rows.sort(key=lambda x: abs(x[1]), reverse=True)
    return rows

def _run_impacts(
    db_name: str,
    fu_pid: str,
    fu_scale: float,
    methods: List[Tuple[str, str, str]],
    *,
    custom_cf_map: Optional[Dict[Tuple[str, str, str], Dict[Tuple[str, str], Tuple[float, str]]]] = None,
) -> Tuple[Dict[str, float], Dict[str, Any]]:
    """
    Compute details as before.

    For `scores`, return the full total impact including custom CFs
    (base_total from the official method + extra_total from custom CFs).
    """
    scores: Dict[str, float] = {}
    details: Dict[str, Any] = {}
    demand = {(db_name, fu_pid): float(fu_scale)}

    for method in methods:
        chosen = choose_method(method)
        lca = LCA(demand, chosen)
        lca.lci()
        lcia_methods = lca.lcia()
        _ = lcia_methods  # keep original behaviour
        print(f"\n[Method diagnostics] {', '.join(chosen)}")
        print(f"  C.nnz = {lca.characterization_matrix.nnz}, B.nnz = {lca.biosphere_matrix.nnz}")
        m = bd.Method(chosen); ents = m.load()
        matched = sum(1 for t in ents if lca.biosphere_dict.get((t[0][0], t[0][1])) is not None)
        print(f"  factors in method = {len(ents)}")
        print(f"  factors matched to inventory = {matched}")
        print(f"  Brightway score (base only) = {lca.score}")

        extra_for_method = (custom_cf_map or {}).get(chosen, {})

        # Totals and top3 using consistent, solved-system arithmetic
        base_total, extra_total, top3 = _characterised_contributions(lca, chosen, extra_for_method)
        if extra_total:
            print(f"  Extra custom CFs applied -> additional = {extra_total}")
        total_with_custom = base_total + extra_total
        print(f"  Total impact (base + custom) = {total_with_custom}")

        full_name = ", ".join(chosen)

        # Per-process including custom CFs via per-unit C·B
        proc_rows = _process_contributions_table(lca, chosen, extra_for_method)
        per_process_sum = float(sum(val for _, val in proc_rows))
        print(f"  Per-process signed sum (base + custom) = {per_process_sum}")

        # Full flow table
        flow_rows = _flow_contributions_table(lca, chosen, extra_for_method)

        # Special override
        if full_name in _TARGET_FLOW_TOTAL_METHODS:
            base_from_flows = float(sum(val for _, val, src in flow_rows if src == "base"))
            custom_from_flows = float(sum(val for _, val, src in flow_rows if src == "custom"))
            flow_total = base_from_flows + custom_from_flows
            print("  Using flow-contribution totals for this method")
            base_total = base_from_flows
            extra_total = custom_from_flows
            total_with_custom = flow_total

        # Report to front end: full total LCA including customs
        scores[full_name] = float(total_with_custom)

        # Friendly prints
        print(f"\n[Top 3 flows] {full_name} (base + custom)")
        if not top3:
            print("  (no contributing biosphere flows found)")
        else:
            for label, val in top3:
                print(f"  - {label}: {val:.6g}")

        # Process table
        print(f"\n[Process contributions] {full_name}")
        if not proc_rows:
            print("  (no contributing processes found)")
        else:
            header_l = "Process"
            header_r = "Contribution"
            print(f"  {header_l:60} | {header_r}")
            print("  " + "-" * 60 + "+----------------")
            for label, val in proc_rows:
                print(f"  {label:60} | {val:.6g}")

        # Reprint flow table after possible override to keep visibility
        print(f"\n[Flow contributions] {full_name}")
        if not flow_rows:
            print("  (no contributing flows found)")
        else:
            header_l = "Flow"
            header_r = "Contribution"
            header_s = "Source"
            print(f"  {header_l:60} | {header_r:>13} | {header_s}")
            print("  " + "-" * 60 + "+---------------+--------")
            for label, val, src in flow_rows:
                print(f"  {label:60} | {val:13.6g} | {src}")

        if lca.characterization_matrix.nnz:
            print(
                f"\n  Cross-check: base_total = {base_total}, lca.score = {lca.score}, "
                f"per-process sum = {per_process_sum}, total_with_custom = {total_with_custom}"
            )

        # Collect details for front end and file
        details[full_name] = {
            "base_total": float(base_total),
            "extra_total": float(extra_total),
            "top3_flows": [(str(a), float(b)) for a, b in top3],
            "process_contributions": [(str(a), float(b)) for a, b in proc_rows],
            "flow_contributions": [(str(a), float(b), str(c)) for a, b, c in flow_rows],
        }

        # Persist JSON once per method
        with open("lca_contributions.json", "w", encoding="utf-8") as f:
            json.dump(details, f, indent=2)

        # Repeat assignment to mirror your previous pattern
        details[full_name] = {
            "base_total": float(base_total),
            "extra_total": float(extra_total),
            "top3_flows": [(str(a), float(b)) for a, b in top3],
            "process_contributions": [(str(a), float(b)) for a, b in proc_rows],
            "flow_contributions": [(str(a), float(b), str(c)) for a, b, c in flow_rows],
        }

    return scores, details

def run_single(
    model: Dict[str, Any],
    *,
    methods: Optional[List[Tuple[str, str, str]]] = None,
    db_name: str = "LCA_Loop_Database",
    biosphere: str = "biosphere3",
    fu_override: Optional[str] = None,
    negative_technosphere: bool = True,
    custom_cf_file: Optional[str] = None,
) -> Dict[str, Any]:
    ensure_biosphere(biosphere)

    custom_cf_map = {}
    if custom_cf_file:
        custom_cf_map = load_custom_cfs_from_table(
            custom_cf_file,
            default_biosphere=biosphere,
            custom_biosphere_name="custom_biosphere",
        )

    loop_data, inferred_fu, fu_scale = parse_model(model, {"fu_process": fu_override} if fu_override else None)
    fu_pid = fu_override or inferred_fu
    fu_scale = float(fu_scale if fu_scale is not None else 1.0)

    # Determine FU reference amount before building the DB
    ref_amount_raw = 1.0
    for e in loop_data:
        if e["process"] == fu_pid and e.get("outputs"):
            try:
                ref_amount_raw = float(e["outputs"][0].get("quantity", 1.0))
            except Exception:
                ref_amount_raw = float("nan")
            break

    # If FU has non-positive or invalid reference amount, short-circuit to zeros
    if not (math.isfinite(ref_amount_raw) and ref_amount_raw > 0.0):
        method_set = methods or IMPACT_METHODS
        zero_scores = {", ".join(m): 0.0 for m in method_set}
        zero_details = {
            ", ".join(m): {
                "base_total": 0.0,
                "extra_total": 0.0,
                "top3_flows": [],
                "process_contributions": [],
                "flow_contributions": [],
            } for m in method_set
        }
        return {
            "process": fu_pid,
            "scores": zero_scores,
            "details": zero_details,
            "unit": "impact units",
            "database": db_name,
            "processes": [e["process"] for e in loop_data if (e.get("outputs") and isinstance(e["outputs"], list) and
                                                              isinstance(e["outputs"][0].get("quantity", 1.0), (int, float)) and
                                                              float(e["outputs"][0].get("quantity", 1.0)) > 0.0)],
            "fu_scale": 0.0,
        }

    # Apply reference amount scaling once here, as before
    fu_scale = fu_scale * float(ref_amount_raw)

    # Build DB with zero-output processes excluded
    create_db(
        loop_data,
        db_name=db_name,
        biosphere_name=biosphere,
        negative_technosphere=negative_technosphere,
    )

    method_set = methods or IMPACT_METHODS
    scores, details = _run_impacts(
        db_name,
        fu_pid,
        fu_scale,
        method_set,
        custom_cf_map=custom_cf_map,
    )

    return {
        "process": fu_pid,
        "scores": scores,            # full total impact, base + custom or flow override when applicable
        "details": details,          # tables consistent with totals
        "unit": "impact units",
        "database": db_name,
        "processes": [e["process"] for e in loop_data if (e.get("outputs") and isinstance(e["outputs"], list) and
                                                          isinstance(e["outputs"][0].get("quantity", 1.0), (int, float)) and
                                                          float(e["outputs"][0].get("quantity", 1.0)) > 0.0)],
        "fu_scale": fu_scale,
    }

# ---------- Updated: reuse the same technosphere DB across scenarios with the same model ----------
def _fingerprint_model(model: Dict[str, Any]) -> str:
    """Create a stable fingerprint for a model to decide whether the DB can be reused."""
    try:
        blob = json.dumps(model, sort_keys=True, separators=(",", ":"))
    except Exception:
        blob = repr(model)
    return hashlib.sha1(blob.encode("utf-8")).hexdigest()

def run_many(
    scenarios: Dict[str, Any],
    *,
    methods: Optional[List[Tuple[str, str, str]]] = None,
    db_name: str = "LCA_Loop_Database",
    biosphere: str = "biosphere3",
    negative_technosphere: bool = False,
    custom_cf_file: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Run multiple scenarios more efficiently.

    Changes:
      - Load custom CFs once.
      - Build the technosphere database once per unique model and reuse it
        for all scenarios that share that model. This avoids repeated
        deletion and re-write of the same DB which was the main cost.
      - If the FU reference amount is non-positive or invalid, return zeros without building an LCA.
    """
    results: Dict[str, Any] = {}

    # One-time setup
    ensure_biosphere(biosphere)

    custom_cf_map = {}
    if custom_cf_file:
        custom_cf_map = load_custom_cfs_from_table(
            custom_cf_file,
            default_biosphere=biosphere,
            custom_biosphere_name="custom_biosphere",
        )

    # Cache: database built for this fingerprint
    current_fp: Optional[str] = None
    cached_process_list: List[str] = []

    method_set = methods or IMPACT_METHODS

    for name, payload in scenarios.items():
        try:
            model = payload.get("model", payload)
            fu_override = payload.get("fu_process")

            # Decide FU and scale for this scenario
            loop_data, inferred_fu, fu_scale = parse_model(model, {"fu_process": fu_override} if fu_override else None)
            fu_pid = fu_override or inferred_fu
            fu_scale = float(fu_scale if fu_scale is not None else 1.0)

            # FU reference amount for this scenario
            ref_amount_raw = 1.0
            for e in loop_data:
                if e["process"] == fu_pid and e.get("outputs"):
                    try:
                        ref_amount_raw = float(e["outputs"][0].get("quantity", 1.0))
                    except Exception:
                        ref_amount_raw = float("nan")
                    break

            # If FU is disabled, short-circuit to zeros
            if not (math.isfinite(ref_amount_raw) and ref_amount_raw > 0.0):
                zero_scores = {", ".join(m): 0.0 for m in method_set}
                zero_details = {
                    ", ".join(m): {
                        "base_total": 0.0,
                        "extra_total": 0.0,
                        "top3_flows": [],
                        "process_contributions": [],
                        "flow_contributions": [],
                    } for m in method_set
                }
                active_procs = [e["process"] for e in loop_data if (e.get("outputs") and isinstance(e["outputs"], list) and
                                                                    isinstance(e["outputs"][0].get("quantity", 1.0), (int, float)) and
                                                                    float(e["outputs"][0].get("quantity", 1.0)) > 0.0)]
                results[name] = {
                    "success": True,
                    "result": {
                        "process": fu_pid,
                        "scores": zero_scores,
                        "details": zero_details,
                        "unit": "impact units",
                        "database": db_name,
                        "processes": active_procs,
                        "fu_scale": 0.0,
                    },
                }
                continue

            # Apply reference amount scaling exactly once
            fu_scale = fu_scale * float(ref_amount_raw)

            # Build DB only when the model changes, with zero-output processes excluded
            fp = _fingerprint_model(model)
            if fp != current_fp:
                L.info("Model fingerprint changed. Rebuilding technosphere DB '%s'.", db_name)
                create_db(
                    loop_data,
                    db_name=db_name,
                    biosphere_name=biosphere,
                    negative_technosphere=negative_technosphere,
                )
                current_fp = fp
                cached_process_list = [e["process"] for e in loop_data if (e.get("outputs") and isinstance(e["outputs"], list) and
                                                                           isinstance(e["outputs"][0].get("quantity", 1.0), (int, float)) and
                                                                           float(e["outputs"][0].get("quantity", 1.0)) > 0.0)]
            else:
                L.info("Reusing existing technosphere DB '%s' for scenario '%s'.", db_name, name)

            # Compute impacts with the shared custom CFs
            scores, details = _run_impacts(
                db_name,
                fu_pid,
                fu_scale,
                method_set,
                custom_cf_map=custom_cf_map,
            )

            single = {
                "process": fu_pid,
                "scores": scores,
                "details": details,
                "unit": "impact units",
                "database": db_name,
                "processes": cached_process_list or [e["process"] for e in loop_data if (e.get("outputs") and isinstance(e["outputs"], list) and
                                                                                         isinstance(e["outputs"][0].get("quantity", 1.0), (int, float)) and
                                                                                         float(e["outputs"][0].get("quantity", 1.0)) > 0.0)],
                "fu_scale": fu_scale,
            }

            results[name] = {"success": True, "result": single}
        except Exception as e:
            L.exception("Scenario '%s' failed", name)
            msg = str(e).strip() or type(e).__name__
            results[name] = {
                "success": False,
                "error": msg,
                "error_type": type(e).__name__,
            }

    return results
 
