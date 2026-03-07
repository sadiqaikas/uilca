
# File: bw_database.py
from __future__ import annotations
import logging
import re
import os
import math
from functools import lru_cache
from typing import Dict, Tuple, Any, List, Optional

import bw2data as bd
from bw2data.errors import InvalidExchange

try:
    import pandas as pd
except Exception:
    pd = None

L = logging.getLogger(__name__)

# --- regex to parse missing activities from InvalidExchange messages ---
_MISSING_RE = re.compile(r"\('(.*?)',\s*'(.*?)'\)")

def _parse_missing(exc_msg: str, db_name: str) -> set[str]:
    """Extract missing activity codes for our technosphere DB from an error message."""
    return {code for db, code in _MISSING_RE.findall(exc_msg) if db == db_name}

# --- biosphere helpers ---

def ensure_biosphere(name: str = "biosphere3") -> None:
    """Ensure the biosphere database exists; raise if not."""
    if name not in bd.databases:
        raise RuntimeError(f"Biosphere database '{name}' not found")
    L.info("Using biosphere database '%s'", name)

def ensure_custom_biosphere(name: str = "custom_biosphere") -> bd.Database:
    """Ensure a custom biosphere DB exists and is marked as type 'biosphere'."""
    if name not in bd.databases:
        db = bd.Database(name)
        db.register()
    meta = bd.databases.get(name, {})
    if meta.get("type") != "biosphere":
        meta["type"] = "biosphere"
        bd.databases[name] = meta
        bd.databases.flush()
    return bd.Database(name)

@lru_cache(maxsize=100000)
def find_emission_flow(flow_uuid: str, biosphere_name: str = "biosphere3") -> Tuple[str, str]:
    """
    Fast lookup by direct key membership with caching.

    Returns (biosphere_name, flow_uuid) if the dataset exists in that DB, else raises KeyError.
    """
    bios = bd.Database(biosphere_name)
    key = (biosphere_name, flow_uuid)
    if key in bios:
        return key
    # Keep behaviour identical when missing
    raise KeyError(f"Flow UUID '{flow_uuid}' not found in database '{biosphere_name}'")

def _resolve_or_create_flow_for_emission(
    em: dict,
    default_biosphere: str = "biosphere3",
    custom_biosphere_name: str = "custom_biosphere",
) -> Tuple[str, str]:
    """
    Resolve an emission flow key.
    Try default_biosphere by code, else create in custom_biosphere.

    Expected fields in `em`:
      - flow_uuid or flow_code (required)
      - name (optional)
      - unit (optional, default 'kg')
      - compartment (optional, e.g. 'water')
      - subcompartment (optional, e.g. 'freshwater')
    """
    code = em.get("flow_uuid") or em.get("flow_code")
    if not code:
        raise KeyError("Emission is missing 'flow_uuid' or 'flow_code'")

    # Fast path: direct membership with cache
    try:
        return find_emission_flow(code, default_biosphere)
    except KeyError:
        raise KeyError(f"Flow '{code}' not found in '{default_biosphere}' (creation disabled)")

    # except KeyError:
    #     cdb = ensure_custom_biosphere(custom_biosphere_name)
    #     key = (custom_biosphere_name, code)
    #     if key not in cdb:
    #         categories: List[str] = []
    #         comp = em.get("compartment")
    #         subc = em.get("subcompartment")
    #         if comp and subc:
    #             categories = [comp, subc]
    #         elif comp:
    #             categories = [comp]
    #         cdb.write({
    #             key: {
    #                 "name": em.get("name", code),
    #                 "exchanges": [],
    #                 "unit": em.get("unit", "kg"),
    #                 "categories": categories,
    #             }
    #         })
    #         L.info("Created custom biosphere flow '%s' in DB '%s'", code, custom_biosphere_name)
    #     return key

# --- impact method selection ---

def choose_method(desired: Tuple[str, str, str]) -> Tuple[str, str, str]:
    """
    Return the official Brightway method key if installed.
    No overlays are consulted or created.
    """
    methods_set = set(bd.methods)
    if desired in methods_set:
        return desired
    raise KeyError(f"Impact method {desired} not found in installed methods")

# --- core: technosphere database creation ---

def create_db(
    loop_data: List[Dict[str, Any]],
    db_name: str = "LCA_Loop_Database",
    biosphere_name: str = "biosphere3",
    *,
    negative_technosphere: bool = True,
    max_heal_attempts: int = 5,
) -> bd.Database:
    """
    Build or replace a Brightway technosphere database from loop_data.

    Policy: processes with non-positive or non-finite reference amounts are treated as
    disabled and are not written into the database. Technosphere inputs that reference
    disabled processes are skipped, since those providers do not exist in this scenario.

    loop_data entry format (as produced by model_ingest.build_loop_data):
      {
        "process": "<pid>",
        "outputs": [ { "name": str, "quantity": float, "unit": str } ],
        "inputs":  [ { "name": str, "quantity": float, "unit": str, "from_process": Optional[str] } ],
        "emissions":[ { "flow_uuid" or "flow_code": str, "quantity" or "amount": float, "unit": str,
                        "name"?: str, "compartment"?: str, "subcompartment"?: str } ]
      }
    """
    ensure_biosphere(biosphere_name)

    def _ref_amount(entry: Dict[str, Any]) -> float:
        if entry.get("outputs"):
            try:
                return float(entry["outputs"][0].get("quantity", 1.0))
            except Exception:
                return float("nan")
        return 1.0

    def _is_active_ref(x: float) -> bool:
        try:
            return math.isfinite(x) and x > 0.0
        except Exception:
            return False

    # Work out which processes are active for this scenario
    disabled_codes: set[str] = set()
    for entry in loop_data:
        ra = _ref_amount(entry)
        if not _is_active_ref(ra):
            disabled_codes.add(entry["process"])
    if disabled_codes:
        L.info("Disabled processes excluded from DB due to zero or invalid reference amount: %s",
               sorted(disabled_codes))

    # Start fresh
    if db_name in bd.databases:
        L.info("Removing existing technosphere database '%s'", db_name)
        del bd.databases[db_name]
    db = bd.Database(db_name)

    # Prepare activity stubs for active processes only
    data: Dict[Tuple[str, str], dict] = {
        (db_name, entry["process"]): {
            "name": entry["process"],
            "location": "GLO",
            "exchanges": [],
        }
        for entry in loop_data
        if entry["process"] not in disabled_codes
    }

    # Fill exchanges for all active entries
    for entry in loop_data:
        pid = entry["process"]
        if pid in disabled_codes:
            continue

        exchanges: List[dict] = []

        # Decide reference product and unit for active process
        ref_unit = "unit"
        ref_amount = 1.0
        if entry.get("outputs"):
            ref = entry["outputs"][0]
            ref_unit = ref.get("unit", "unit")
            try:
                ref_amount = float(ref.get("quantity", 1.0))
            except Exception:
                ref_amount = 1.0

        # Production exchange
        exchanges.append({
            "input": (db_name, pid),
            "amount": ref_amount,
            "unit": ref_unit,
            "type": "production",
        })

        # Technosphere inputs
        for inp in entry.get("inputs", []):
            src = inp.get("from_process") or inp["name"]
            if src in disabled_codes:
                L.info("Skipping technosphere input on '%s' from disabled provider '%s'",
                       pid, src)
                continue
            amt = float(inp["quantity"])
            if negative_technosphere:
                amt = -abs(amt)
            exchanges.append({
                "input": (db_name, src),
                "amount": amt,
                "unit": inp.get("unit", "unit"),
                "type": "technosphere",
            })

        # Biosphere emissions
        # for em in entry.get("emissions", []):
        #     key = _resolve_or_create_flow_for_emission(
        #         em, default_biosphere=biosphere_name, custom_biosphere_name="custom_biosphere"
        #     )
        #     exchanges.append({
        #         "input": key,
        #         "amount": float(em.get("quantity", em.get("amount", 0.0))),
        #         "unit": em.get("unit", "kg"),
        #         "type": "biosphere",
        #     })
        # Biosphere emissions
        for em in entry.get("emissions", []):
            try:
                key = _resolve_or_create_flow_for_emission(
                    em,
                    default_biosphere=biosphere_name,
                    custom_biosphere_name="custom_biosphere",
                )
            except KeyError:
                # Missing flow, skip it
                continue

            exchanges.append({
                "input": key,
                "amount": float(em.get("quantity", em.get("amount", 0.0))),
                "unit": em.get("unit", "kg"),
                "type": "biosphere",
            })


        data[(db_name, pid)]["exchanges"] = exchanges

    # Single preflight: ensure every technosphere input inside this DB exists
    needed_codes: set[str] = set()
    for _, ds in data.items():
        for exc in ds.get("exchanges", []):
            if exc.get("type") == "technosphere":
                inp_db, inp_code = exc.get("input", (None, None))
                # Only auto-create if input refers to this DB, is not already defined,
                # and is not a disabled provider
                if inp_db == db_name and (inp_db, inp_code) not in data and inp_code not in disabled_codes:
                    needed_codes.add(inp_code)
    if needed_codes:
        L.warning("Auto-creating minimal producers for missing technosphere inputs: %s",
                  sorted(needed_codes))
        for code in needed_codes:
            data[(db_name, code)] = {
                "name": code,
                "location": "GLO",
                "exchanges": [{
                    "input": (db_name, code),
                    "amount": 1.0,
                    "unit": "unit",
                    "type": "production",
                }],
            }

    # Write with healing (rare, but keep behaviour)
    for attempt in range(1, max_heal_attempts + 1):
        try:
            db.write(data)
            L.info("Successfully wrote Brightway database '%s'", db_name)
            return db
        except InvalidExchange as e:
            missing = _parse_missing(str(e), db_name)
            # Do not heal by creating disabled providers
            missing = {code for code in missing if code not in disabled_codes}
            if not missing:
                raise
            L.warning("DB write failed, healing missing processes (attempt %d): %s",
                      attempt, sorted(missing))
            for code in missing:
                if (db_name, code) not in data:
                    data[(db_name, code)] = {
                        "name": code,
                        "location": "GLO",
                        "exchanges": [{
                            "input": (db_name, code),
                            "amount": 1.0,
                            "unit": "unit",
                            "type": "production",
                        }],
                    }
    raise RuntimeError("Could not write Brightway DB after healing attempts")

# ---------- Custom CFs: read from Excel/CSV and return in-memory map (no overlays) ----------

def _read_table(path: str) -> List[dict]:
    """Read .xlsx or .csv into list of dict rows. Return [] on error."""
    if not path or not os.path.isfile(path):
        return []
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext == ".csv":
            import csv
            with open(path, "r", newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                return [{k.strip(): v for k, v in row.items()} for row in reader]
        elif ext in {".xlsx", ".xls"}:
            if pd is None:
                L.error("Pandas is required to read Excel files: %s", path)
                return []
            df = pd.read_excel(path, sheet_name=0)
            return [{str(k).strip(): v for k, v in r.items()} for r in df.to_dict(orient="records")]
    except Exception as e:
        L.error("Failed to read custom CF file '%s': %s", path, e)
    return []

def _installed_methods_index() -> Dict[str, Tuple[str, str, str]]:
    """Build a lookup: normalised string -> method triple."""
    idx: Dict[str, Tuple[str, str, str]] = {}
    all_methods = list(bd.methods)
    for m in all_methods:
        idx[", ".join(m).strip().lower()] = m
        idx[" | ".join(m).strip().lower()] = m
    # also map unique first element only if unique
    counts: Dict[str, int] = {}
    for m in all_methods:
        k = m[0].strip().lower()
        counts[k] = counts.get(k, 0) + 1
    for m in all_methods:
        k = m[0].strip().lower()
        if counts[k] == 1:
            idx[k] = m
    return idx

def _resolve_method_from_single_cell(s: str) -> Tuple[str, str, str]:
    """Resolve a Brightway method triple from a single 'method_0' string."""
    s_norm = (s or "").strip()
    if not s_norm:
        raise ValueError("Empty method_0 cell")
    idx = _installed_methods_index()
    k = s_norm.lower()
    if k in idx:
        return idx[k]
    parts = [p.strip() for p in (s_norm.split(" | ") if " | " in s_norm else s_norm.split(","))]
    if len(parts) >= 3:
        cand = (parts[0], parts[1], ", ".join(parts[2:]))
        if cand in bd.methods:
            return cand
    examples = [", ".join(m) for m in list(bd.methods)[:5]]
    raise ValueError(f"Could not resolve method from 'method_0': '{s_norm}'. Examples: {examples}")

def load_custom_cfs_from_table(
    path: str,
    default_biosphere: str = "biosphere3",
    custom_biosphere_name: str = "custom_biosphere",
) -> Dict[Tuple[str, str, str], Dict[Tuple[str, str], Tuple[float, str]]]:
    """
    Read custom CF rows without touching Brightway methods.

    Excel/CSV headers (case-insensitive):
      required: method_0, cf, unit, and one of {flow_uuid, flow_code}
      optional: flow_db, flow_name, compartment, subcompartment

    Returns:
      { base_method_triple: { (flow_db, flow_code): (cf_value, unit) } }

    Behaviour:
      - Resolve 'method_0' to an official Brightway method triple.
      - Ensure each flow exists (use flow_db if provided, else try default_biosphere, else create in custom_biosphere).
      - Do not write or alter any Brightway method. Purely returns an in-memory mapping.
    """
    rows = _read_table(path)
    out: Dict[Tuple[str, str, str], Dict[Tuple[str, str], Tuple[float, str]]] = {}
    if not rows:
        return out

    ensure_custom_biosphere(custom_biosphere_name)

    def get_ci(row: dict, name: str, default: Any = None) -> Any:
        for k, v in row.items():
            if k.strip().lower() == name:
                return v
        return default

    for r in rows:
        mcell = get_ci(r, "method_0")
        if not mcell or str(mcell).strip() == "":
            L.warning("Skipping row without method_0: %s", r)
            continue
        try:
            base_mkey = _resolve_method_from_single_cell(str(mcell))
        except Exception as e:
            L.error("Skipping row. %s Row: %s", e, r)
            continue

        code_raw = get_ci(r, "flow_uuid") or get_ci(r, "flow_code")
        if not code_raw or str(code_raw).strip() == "":
            L.warning("Skipping row without flow_uuid/flow_code: %s", r)
            continue
        code = str(code_raw).strip()

        try:
            cf_val = float(get_ci(r, "cf"))
        except Exception:
            L.warning("Skipping row with non-numeric CF for flow '%s': %s", code, r)
            continue

        cf_unit = str(get_ci(r, "unit", "kg")).strip() or "kg"

        flow_db = str(get_ci(r, "flow_db", "") or "").strip()
        flow_name = str(get_ci(r, "flow_name", "") or "").strip() or code
        comp = str(get_ci(r, "compartment", "") or "").strip()
        subc = str(get_ci(r, "subcompartment", "") or "").strip()

        # Resolve or create the flow
        if flow_db:
            target_dbs = [flow_db]
        else:
            target_dbs = [default_biosphere, custom_biosphere_name]

        fk: Optional[Tuple[str, str]] = None
        for cand_db in target_dbs:
            try:
                fk = find_emission_flow(code, cand_db)  # fast path with cache
                break
            except KeyError:
                continue

        if fk is None:
            # create in custom biosphere
            cdb = ensure_custom_biosphere(custom_biosphere_name)
            fk = (custom_biosphere_name, code)
            if fk not in cdb:
                categories: List[str] = []
                if comp and subc:
                    categories = [comp, subc]
                elif comp:
                    categories = [comp]
                cdb.write({
                    fk: {
                        "name": flow_name or code,
                        "exchanges": [],
                        "unit": "kg",
                        "categories": categories,
                    }
                })
                L.info("Created custom biosphere flow '%s' in DB '%s' for custom CF",
                       code, custom_biosphere_name)

        out.setdefault(base_mkey, {})[fk] = (cf_val, cf_unit)

    return out

# Backward compatibility stub. You asked to keep Brightway methods intact,
# so this function no longer writes overlay methods.
def upsert_custom_cfs_from_table(*args, **kwargs) -> None:
    L.warning("upsert_custom_cfs_from_table is deprecated. No overlays are created. "
              "Use load_custom_cfs_from_table and runtime augmentation instead.")
    return None
