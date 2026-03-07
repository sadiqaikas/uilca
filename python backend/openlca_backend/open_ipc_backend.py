"""OpenLCA IPC backend (FastAPI) for product-system discovery and LCA runs.

Run example:
    uvicorn open_ipc_backend:app --host 0.0.0.0 --port 8000 --reload

This service expects an openLCA IPC server (JSON-RPC) to be available,
typically at http://localhost:8080.
"""

from __future__ import annotations

import math
import os
import re
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

try:
    import olca_ipc
    import olca_schema as o
except Exception as exc:  # pragma: no cover - only triggered in bad envs
    olca_ipc = None  # type: ignore[assignment]
    o = None  # type: ignore[assignment]
    IMPORT_ERROR = str(exc)
else:
    IMPORT_ERROR = None


app = FastAPI(title="OpenLCA IPC Backend", version="0.3.0")

# Dev-friendly CORS; tighten this for production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


DEFAULT_OPENLCA_IPC_URL = os.getenv("OPENLCA_IPC_URL", "http://localhost:8080")
DEFAULT_IMPACT_METHOD_ID = os.getenv("OPENLCA_IMPACT_METHOD_ID")
DEFAULT_IMPACT_METHOD_NAME = os.getenv("OPENLCA_IMPACT_METHOD_NAME")

_UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
_IDENTIFIER_TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_FORMULA_FUNCTION_NAMES = {"min", "max", "abs", "round", "ceil", "floor"}


class OpenLcaRunScenariosRequest(BaseModel):
    product_system_id: str = Field(..., min_length=1)
    scenarios: dict[str, Any]
    ipc_url: str | None = None
    impact_method_id: str | None = None
    impact_method_name: str | None = None


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "service": "openlca-ipc-backend"}


@app.get("/openlca/product-systems")
def list_product_systems(
    ipc_url: str = Query(
        default=DEFAULT_OPENLCA_IPC_URL,
        description="JSON-RPC endpoint for openLCA IPC (e.g. http://localhost:8080)",
    )
) -> dict[str, Any]:
    """Return product-system descriptors from the connected openLCA instance."""
    _ensure_openlca_available()
    client = _new_ipc_client(ipc_url)

    try:
        descriptors = client.get_descriptors(o.ProductSystem)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to connect to openLCA IPC at {ipc_url}: {exc}",
        ) from exc

    product_systems = [_ref_to_public_dict(ref) for ref in descriptors]
    product_systems.sort(key=lambda item: (item.get("name") or "").lower())

    return {
        "success": True,
        "ipc_url": ipc_url,
        "count": len(product_systems),
        "product_systems": product_systems,
    }


@app.get("/openlca/product-systems/{product_system_id}")
def get_product_system(
    product_system_id: str,
    ipc_url: str = Query(
        default=DEFAULT_OPENLCA_IPC_URL,
        description="JSON-RPC endpoint for openLCA IPC (e.g. http://localhost:8080)",
    ),
) -> dict[str, Any]:
    """Return one product-system descriptor by id."""
    _ensure_openlca_available()
    client = _new_ipc_client(ipc_url)

    try:
        ref = client.get_descriptor(o.ProductSystem, uid=product_system_id)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to query openLCA IPC at {ipc_url}: {exc}",
        ) from exc

    if ref is None:
        raise HTTPException(
            status_code=404,
            detail=f"Product system '{product_system_id}' not found.",
        )

    return {
        "success": True,
        "ipc_url": ipc_url,
        "product_system": _ref_to_public_dict(ref),
    }


@app.get("/openlca/product-systems/{product_system_id}/project-bundle")
def get_product_system_project_bundle(
    product_system_id: str,
    ipc_url: str = Query(
        default=DEFAULT_OPENLCA_IPC_URL,
        description="JSON-RPC endpoint for openLCA IPC (e.g. http://localhost:8080)",
    ),
) -> dict[str, Any]:
    """Return an EarlyLCA canvas-compatible project bundle for one product system."""
    _ensure_openlca_available()
    client = _new_ipc_client(ipc_url)

    try:
        descriptor = client.get_descriptor(o.ProductSystem, uid=product_system_id)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to query product system descriptor at {ipc_url}: {exc}",
        ) from exc

    if descriptor is None:
        raise HTTPException(
            status_code=404,
            detail=f"Product system '{product_system_id}' not found.",
        )

    try:
        product_system = client.get(o.ProductSystem, uid=product_system_id)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to load product system '{product_system_id}' at {ipc_url}: {exc}",
        ) from exc

    process_refs = _collect_product_system_process_refs(product_system)
    reference_process_id = _pick_reference_process_id(product_system)

    process_nodes: list[dict[str, Any]] = []
    process_parameters: dict[str, list[dict[str, Any]]] = {}

    for index, process_ref in enumerate(process_refs):
        process_id = process_ref["id"]
        process_entity = _safe_get(client, o.Process, process_id)
        node, params = _process_to_canvas_node(
            process_ref=process_ref,
            process_entity=process_entity,
            index=index,
            is_functional=process_id == reference_process_id,
        )
        process_nodes.append(node)
        if params:
            process_parameters[process_id] = params

    # Fallback: if process references were not accessible, create one functional node.
    if not process_nodes:
        process_nodes.append(
            {
                "id": product_system_id,
                "name": descriptor.name or product_system_id,
                "inputs": [],
                "outputs": [
                    {
                        "name": descriptor.name or "product_system_output",
                        "amount": 1.0,
                        "unit": "units",
                    }
                ],
                "emissions": [],
                "position": {"x": 80.0, "y": 80.0},
                "isFunctional": True,
            }
        )

    flows = _collect_product_system_flows(product_system)
    if not flows:
        flows = _infer_flows_from_process_nodes(process_nodes)

    global_parameters, set_process_parameters = _extract_product_system_parameter_sets(
        product_system
    )
    runtime_global_parameters, runtime_process_parameters = _split_contextual_parameters(
        _safe_get_parameters(client, o.ProductSystem, product_system_id)
    )
    legacy_global_parameters = _extract_entity_parameters(
        getattr(product_system, "parameters", None),
        default_scope="global",
    )
    global_parameters = _merge_parameter_lists(
        global_parameters,
        runtime_global_parameters,
        prefer_secondary=False,
    )
    global_parameters = _merge_parameter_lists(
        global_parameters,
        legacy_global_parameters,
        prefer_secondary=False,
    )
    process_parameters = _merge_process_parameter_maps(
        process_parameters,
        set_process_parameters,
        prefer_extra=True,
    )
    process_parameters = _merge_process_parameter_maps(
        process_parameters,
        runtime_process_parameters,
        prefer_extra=True,
    )

    project_bundle: dict[str, Any] = {
        "processes": process_nodes,
        "flows": flows,
    }
    if global_parameters:
        project_bundle["global_parameters"] = global_parameters
    if process_parameters:
        project_bundle["process_parameters"] = process_parameters

    return {
        "success": True,
        "ipc_url": ipc_url,
        "product_system": _ref_to_public_dict(descriptor),
        "project_bundle": project_bundle,
        "stats": {
            "process_count": len(process_nodes),
            "flow_count": len(flows),
            "global_parameter_count": len(global_parameters),
            "process_parameter_count": sum(len(v) for v in process_parameters.values()),
        },
    }


@app.get("/openlca/impact-methods")
def list_impact_methods(
    ipc_url: str = Query(
        default=DEFAULT_OPENLCA_IPC_URL,
        description="JSON-RPC endpoint for openLCA IPC (e.g. http://localhost:8080)",
    )
) -> dict[str, Any]:
    """Return LCIA method descriptors from the connected openLCA instance."""
    _ensure_openlca_available()
    client = _new_ipc_client(ipc_url)

    try:
        descriptors = client.get_descriptors(o.ImpactMethod)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to query impact methods from openLCA IPC at {ipc_url}: {exc}",
        ) from exc

    impact_methods = [_ref_to_public_dict(ref) for ref in descriptors]
    impact_methods.sort(key=lambda item: (item.get("name") or "").lower())

    return {
        "success": True,
        "ipc_url": ipc_url,
        "count": len(impact_methods),
        "impact_methods": impact_methods,
    }


@app.post("/openlca/run-scenarios")
def run_scenarios(request: OpenLcaRunScenariosRequest) -> dict[str, Any]:
    """Run openLCA for all scenarios by applying scenario parameter overrides."""
    _ensure_openlca_available()

    if not request.scenarios:
        raise HTTPException(status_code=400, detail="No scenarios provided.")

    ipc_url = request.ipc_url or DEFAULT_OPENLCA_IPC_URL
    client = _new_ipc_client(ipc_url)

    try:
        product_system_ref = client.get_descriptor(
            o.ProductSystem, uid=request.product_system_id
        )
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to query product system in openLCA IPC at {ipc_url}: {exc}",
        ) from exc

    if product_system_ref is None:
        raise HTTPException(
            status_code=404,
            detail=f"Product system '{request.product_system_id}' not found.",
        )
    if product_system_ref.ref_type is None:
        product_system_ref.ref_type = o.RefType.ProductSystem

    try:
        product_system_entity = client.get(o.ProductSystem, uid=request.product_system_id)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=(
                f"Failed to load product system '{request.product_system_id}' "
                f"from openLCA IPC at {ipc_url}: {exc}"
            ),
        ) from exc

    if product_system_entity is None:
        raise HTTPException(
            status_code=404,
            detail=f"Product system '{request.product_system_id}' not found.",
        )

    parameter_catalog = _build_parameter_catalog(client, product_system_entity)

    impact_method_ref = _pick_impact_method(
        client,
        impact_method_id=request.impact_method_id or DEFAULT_IMPACT_METHOD_ID,
        impact_method_name=request.impact_method_name or DEFAULT_IMPACT_METHOD_NAME,
    )
    if impact_method_ref is None:
        if request.impact_method_id:
            raise HTTPException(
                status_code=404,
                detail=f"Impact method '{request.impact_method_id}' not found.",
            )
        if request.impact_method_name:
            raise HTTPException(
                status_code=404,
                detail=f"Impact method '{request.impact_method_name}' not found.",
            )
        raise HTTPException(
            status_code=400,
            detail=(
                "No impact method available. Set OPENLCA_IMPACT_METHOD_ID / "
                "OPENLCA_IMPACT_METHOD_NAME or provide one in the request."
            ),
        )

    results: dict[str, Any] = {}
    any_success = False

    for scenario_name, scenario_payload in request.scenarios.items():
        try:
            model = _extract_model_from_scenario_payload(scenario_payload)
            result_payload = _run_single_scenario(
                client=client,
                scenario_model=model,
                product_system_ref=product_system_ref,
                impact_method_ref=impact_method_ref,
                parameter_catalog=parameter_catalog,
            )
            results[scenario_name] = {"success": True, "result": result_payload}
            any_success = True
        except Exception as exc:
            results[scenario_name] = {"success": False, "error": str(exc)}

    return {
        "success": any_success,
        "runner": "openlca_ipc",
        "ipc_url": ipc_url,
        "product_system": _ref_to_public_dict(product_system_ref),
        "impact_method": _ref_to_public_dict(impact_method_ref),
        "results": results,
    }


def _ensure_openlca_available() -> None:
    if IMPORT_ERROR is not None or olca_ipc is None or o is None:
        raise HTTPException(
            status_code=500,
            detail=(
                "OpenLCA dependencies are missing or failed to import: "
                f"{IMPORT_ERROR}"
            ),
        )


def _new_ipc_client(ipc_url: str):
    try:
        return olca_ipc.Client(ipc_url)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to initialize openLCA IPC client for '{ipc_url}': {exc}",
        ) from exc


def _extract_model_from_scenario_payload(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ValueError("Scenario payload must be an object.")

    if isinstance(payload.get("model"), dict):
        model = dict(payload["model"])
        if isinstance(payload.get("changes"), list):
            model["changes"] = payload["changes"]
        if "number_functional_units" in payload:
            model["number_functional_units"] = payload.get("number_functional_units")
        return model

    return payload


def _safe_get(client, model_type, uid: str):
    try:
        return client.get(model_type, uid=uid)
    except Exception:
        return None


def _safe_get_parameters(client, model_type, uid: str) -> list[Any]:
    try:
        params = client.get_parameters(model_type, uid=uid)
    except Exception:
        return []
    if isinstance(params, (list, tuple)):
        return list(params)
    return []


def _collect_product_system_process_refs(product_system: Any) -> list[dict[str, str]]:
    refs_by_id: dict[str, dict[str, str]] = {}

    def add_ref(raw_ref: Any) -> None:
        ref_id = _extract_ref_id(raw_ref)
        if not ref_id:
            return
        ref_name = _extract_ref_name(raw_ref) or ref_id

        existing = refs_by_id.get(ref_id)
        if existing is None:
            refs_by_id[ref_id] = {"id": ref_id, "name": ref_name}
            return

        if not existing.get("name") and ref_name:
            existing["name"] = ref_name

    if product_system is None:
        return []

    process_list = getattr(product_system, "processes", None)
    if isinstance(process_list, (list, tuple)):
        for raw_ref in process_list:
            add_ref(raw_ref)

    add_ref(getattr(product_system, "refProcess", None))
    add_ref(getattr(product_system, "ref_process", None))
    add_ref(getattr(product_system, "reference_process", None))
    add_ref(getattr(product_system, "targetProcess", None))
    add_ref(getattr(product_system, "target_process", None))
    add_ref(getattr(product_system, "process", None))

    process_links = getattr(product_system, "process_links", None)
    if isinstance(process_links, (list, tuple)):
        for link in process_links:
            add_ref(getattr(link, "provider", None))
            add_ref(getattr(link, "process", None))

    refs = list(refs_by_id.values())
    refs.sort(key=lambda item: (item.get("name") or item.get("id") or "").lower())
    return refs


def _pick_reference_process_id(product_system: Any) -> str:
    if product_system is None:
        return ""

    candidates = [
        getattr(product_system, "refProcess", None),
        getattr(product_system, "ref_process", None),
        getattr(product_system, "reference_process", None),
        getattr(product_system, "targetProcess", None),
        getattr(product_system, "target_process", None),
        getattr(product_system, "process", None),
    ]
    for raw in candidates:
        ref_id = _extract_ref_id(raw)
        if ref_id:
            return ref_id

    reference_exchange = getattr(product_system, "ref_exchange", None)
    if reference_exchange is None:
        reference_exchange = getattr(product_system, "reference_exchange", None)
    if reference_exchange is not None:
        ref_id = _extract_ref_id(getattr(reference_exchange, "process", None))
        if ref_id:
            return ref_id

    return ""


def _process_to_canvas_node(
    process_ref: dict[str, str],
    process_entity: Any,
    index: int,
    is_functional: bool,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    process_id = process_ref["id"]
    process_name = (
        _clean_text(getattr(process_entity, "name", None))
        or _clean_text(process_ref.get("name"))
        or process_id
    )

    inputs: list[dict[str, Any]] = []
    outputs: list[dict[str, Any]] = []
    emissions: list[dict[str, Any]] = []

    parameters = _extract_entity_parameters(
        getattr(process_entity, "parameters", None),
        default_scope="process",
    )
    seen_param_names = {
        str(p.get("name") or "").strip().lower()
        for p in parameters
        if str(p.get("name") or "").strip()
    }

    exchanges = getattr(process_entity, "exchanges", None)
    if isinstance(exchanges, (list, tuple)):
        for exchange in exchanges:
            flow_ref = getattr(exchange, "flow", None)
            flow_name = (
                _extract_ref_name(flow_ref)
                or _clean_text(getattr(exchange, "name", None))
                or f"flow_{len(inputs) + len(outputs) + len(emissions) + 1}"
            )

            amount = _coerce_float(getattr(exchange, "amount", None))
            if amount is None:
                amount = 0.0

            flow_payload: dict[str, Any] = {
                "name": flow_name,
                "amount": amount,
                "unit": _extract_exchange_unit(exchange),
            }

            flow_id = _extract_ref_id(flow_ref)
            if flow_id:
                flow_payload["flow_uuid"] = flow_id

            formula = _first_non_empty_text(
                getattr(exchange, "formula", None),
                getattr(exchange, "amount_formula", None),
                getattr(exchange, "formula_text", None),
            )
            if formula:
                flow_payload["amount_expr"] = formula

                if _is_identifier(formula):
                    flow_payload["amount_param"] = formula
                    key = formula.lower()
                    if key not in seen_param_names:
                        parameters.append(
                            {
                                "name": formula,
                                "value": amount,
                                "scope": "process",
                            }
                        )
                        seen_param_names.add(key)

            if _is_elementary_flow_exchange(exchange, flow_ref):
                emissions.append(flow_payload)
            elif _exchange_is_input(exchange):
                inputs.append(flow_payload)
            else:
                outputs.append(flow_payload)

            if (
                not is_functional
                and _exchange_is_quantitative_reference(exchange)
                and not _exchange_is_input(exchange)
            ):
                is_functional = True

    columns = 4
    node = {
        "id": process_id,
        "name": process_name,
        "inputs": inputs,
        "outputs": outputs,
        "emissions": emissions,
        "position": {
            "x": 80.0 + float(index % columns) * 380.0,
            "y": 80.0 + float(index // columns) * 220.0,
        },
        "isFunctional": is_functional,
    }
    if parameters:
        node["parameters"] = parameters
    return node, parameters


def _collect_product_system_flows(product_system: Any) -> list[dict[str, Any]]:
    if product_system is None:
        return []

    process_links = getattr(product_system, "process_links", None)
    if not isinstance(process_links, (list, tuple)):
        return []

    names_by_pair: dict[tuple[str, str], set[str]] = {}
    for link in process_links:
        from_id = _extract_ref_id(getattr(link, "provider", None))
        to_id = _extract_ref_id(getattr(link, "process", None))
        if not from_id or not to_id or from_id == to_id:
            continue

        flow_name = (
            _extract_ref_name(getattr(link, "flow", None))
            or _clean_text(getattr(link, "flow_name", None))
            or _clean_text(getattr(link, "exchange_name", None))
            or "linked_flow"
        )
        key = (from_id, to_id)
        if key not in names_by_pair:
            names_by_pair[key] = set()
        names_by_pair[key].add(flow_name)

    out: list[dict[str, Any]] = []
    for (from_id, to_id), names in names_by_pair.items():
        out.append(
            {
                "from": from_id,
                "to": to_id,
                "names": sorted(names, key=lambda item: item.lower()),
            }
        )

    out.sort(key=lambda item: (item["from"], item["to"]))
    return out


def _infer_flows_from_process_nodes(
    process_nodes: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    def norm(text: str) -> str:
        return text.strip().lower()

    out: list[dict[str, Any]] = []
    for i in range(len(process_nodes)):
        for j in range(i + 1, len(process_nodes)):
            node_i = process_nodes[i]
            node_j = process_nodes[j]

            i_out = {
                norm(str(f.get("name") or ""))
                for f in node_i.get("outputs", [])
                if norm(str(f.get("name") or ""))
            }
            j_in = {
                norm(str(f.get("name") or ""))
                for f in node_j.get("inputs", [])
                if norm(str(f.get("name") or ""))
            }

            j_out = {
                norm(str(f.get("name") or ""))
                for f in node_j.get("outputs", [])
                if norm(str(f.get("name") or ""))
            }
            i_in = {
                norm(str(f.get("name") or ""))
                for f in node_i.get("inputs", [])
                if norm(str(f.get("name") or ""))
            }

            names = sorted(i_out.intersection(j_in).union(j_out.intersection(i_in)))
            if names:
                out.append(
                    {
                        "from": str(node_i.get("id") or ""),
                        "to": str(node_j.get("id") or ""),
                        "names": names,
                    }
                )
    return out


def _extract_entity_parameters(
    raw_params: Any,
    default_scope: str,
) -> list[dict[str, Any]]:
    if not isinstance(raw_params, (list, tuple)):
        return []

    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in raw_params:
        item = _parameter_to_public_dict(raw, default_scope=default_scope)
        if item is None:
            continue
        key = item["name"].strip().lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(item)

    out.sort(key=lambda item: item["name"].lower())
    return out


def _split_contextual_parameters(
    raw_params: Any,
) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    if not isinstance(raw_params, (list, tuple)):
        return [], {}

    global_out: list[dict[str, Any]] = []
    process_out: dict[str, list[dict[str, Any]]] = {}

    for raw_param in raw_params:
        context = getattr(raw_param, "context", None)
        context_id = _extract_ref_id(context)
        if context_id:
            item = _parameter_to_public_dict(raw_param, default_scope="process")
            if item is None:
                continue
            process_out.setdefault(context_id, []).append(item)
            continue

        item = _parameter_to_public_dict(raw_param, default_scope="global")
        if item is None:
            continue
        global_out.append(item)

    global_out = _merge_parameter_lists([], global_out, prefer_secondary=True)
    process_out = _merge_process_parameter_maps({}, process_out, prefer_extra=True)
    return global_out, process_out


def _parameter_to_public_dict(
    raw_param: Any,
    default_scope: str,
) -> dict[str, Any] | None:
    name = _clean_text(getattr(raw_param, "name", None))
    if not name:
        return None

    formula = _clean_text(getattr(raw_param, "formula", None))
    value = _coerce_float(getattr(raw_param, "value", None))
    if not formula and value is None:
        return None

    item: dict[str, Any] = {
        "name": name,
        "scope": _parameter_scope_name(raw_param, default_scope=default_scope),
    }
    if formula:
        item["formula"] = formula
    elif value is not None:
        item["value"] = value

    unit = _extract_unit_name(getattr(raw_param, "unit", None))
    if unit:
        item["unit"] = unit

    note = _first_non_empty_text(
        getattr(raw_param, "description", None),
        getattr(raw_param, "comment", None),
    )
    if note:
        item["note"] = note

    return item


def _parameter_scope_name(raw_param: Any, default_scope: str) -> str:
    raw_scope = getattr(raw_param, "scope", None)
    if raw_scope is None:
        raw_scope = getattr(raw_param, "parameter_scope", None)
    if raw_scope is not None:
        scope_name = _first_non_empty_text(
            getattr(raw_scope, "name", None),
            getattr(raw_scope, "value", None),
            raw_scope,
        ).lower()
        if "global" in scope_name:
            return "global"
        if "process" in scope_name:
            return "process"
    return default_scope


def _extract_exchange_unit(exchange: Any) -> str:
    name = _extract_unit_name(getattr(exchange, "unit", None))
    if name:
        return name

    flow_property_factor = getattr(exchange, "flow_property_factor", None)
    if flow_property_factor is not None:
        name = _extract_unit_name(getattr(flow_property_factor, "unit", None))
        if name:
            return name

    return "units"


def _extract_unit_name(raw_unit: Any) -> str:
    if raw_unit is None:
        return ""

    if isinstance(raw_unit, str):
        return raw_unit.strip()

    return _first_non_empty_text(
        getattr(raw_unit, "name", None),
        getattr(raw_unit, "id", None),
    )


def _exchange_is_input(exchange: Any) -> bool:
    raw = getattr(exchange, "is_input", None)
    if raw is None:
        raw = getattr(exchange, "input", None)
    if isinstance(raw, bool):
        return raw
    return str(raw).strip().lower() in {"true", "1", "yes"}


def _exchange_is_quantitative_reference(exchange: Any) -> bool:
    for attr in (
        "quantitative_reference",
        "is_quantitative_reference",
        "reference",
        "is_reference_flow",
    ):
        raw = getattr(exchange, attr, None)
        if isinstance(raw, bool) and raw:
            return True
        if str(raw).strip().lower() in {"true", "1", "yes"}:
            return True
    return False


def _is_elementary_flow_exchange(exchange: Any, flow_ref: Any) -> bool:
    for attr in ("is_emission", "elementary_flow", "is_elementary_flow"):
        raw = getattr(exchange, attr, None)
        if isinstance(raw, bool) and raw:
            return True
        if str(raw).strip().lower() in {"true", "1", "yes"}:
            return True

    flow_type = getattr(flow_ref, "flow_type", None)
    if flow_type is None:
        flow_type = getattr(flow_ref, "flowType", None)
    text = _first_non_empty_text(getattr(flow_type, "name", None), flow_type)
    return "elementary" in text.lower()


def _extract_ref_id(raw_ref: Any) -> str:
    if raw_ref is None:
        return ""
    if isinstance(raw_ref, dict):
        return _clean_text(raw_ref.get("id"))
    return _clean_text(getattr(raw_ref, "id", None))


def _extract_ref_name(raw_ref: Any) -> str:
    if raw_ref is None:
        return ""
    if isinstance(raw_ref, dict):
        return _first_non_empty_text(raw_ref.get("name"), raw_ref.get("id"))
    return _first_non_empty_text(
        getattr(raw_ref, "name", None),
        getattr(raw_ref, "id", None),
    )


def _clean_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _first_non_empty_text(*values: Any) -> str:
    for value in values:
        text = _clean_text(value)
        if text:
            return text
    return ""


def _is_identifier(text: str) -> bool:
    return bool(re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", text.strip()))


def _pick_impact_method(
    client,
    impact_method_id: str | None,
    impact_method_name: str | None,
):
    descriptors = client.get_descriptors(o.ImpactMethod)
    if not descriptors:
        return None

    if impact_method_id:
        for ref in descriptors:
            if ref.id == impact_method_id:
                if ref.ref_type is None:
                    ref.ref_type = o.RefType.ImpactMethod
                return ref
        return None

    if impact_method_name:
        needle = impact_method_name.strip().lower()
        for ref in descriptors:
            if (ref.name or "").strip().lower() == needle:
                if ref.ref_type is None:
                    ref.ref_type = o.RefType.ImpactMethod
                return ref
        for ref in descriptors:
            if needle in (ref.name or "").strip().lower():
                if ref.ref_type is None:
                    ref.ref_type = o.RefType.ImpactMethod
                return ref
        return None

    descriptors.sort(key=lambda r: (r.name or "").lower())
    picked = descriptors[0]
    if picked.ref_type is None:
        picked.ref_type = o.RefType.ImpactMethod
    return picked


def _run_single_scenario(
    client,
    scenario_model: dict[str, Any],
    product_system_ref,
    impact_method_ref,
    parameter_catalog: dict[str, Any] | None,
) -> dict[str, Any]:
    redefinitions, functional_units, param_warnings = _extract_parameter_redefinitions(
        scenario_model,
        parameter_catalog=parameter_catalog,
    )

    setup = o.CalculationSetup(
        target=product_system_ref,
        impact_method=impact_method_ref,
        parameters=redefinitions if redefinitions else None,
        amount=functional_units,
    )

    calc_result = client.calculate(setup)
    try:
        state = calc_result.wait_until_ready()
        if state.error:
            raise RuntimeError(f"openLCA calculation error: {state.error}")

        impacts = calc_result.get_total_impacts()
    finally:
        calc_result.dispose()

    scores: dict[str, float] = {}
    score_units: dict[str, str] = {}
    for impact in impacts:
        label = _impact_label(impact, len(scores) + 1)
        amount = _coerce_float(impact.amount)
        if amount is None:
            amount = 0.0
        scores[label] = amount
        unit = _impact_unit(impact)
        if unit and label not in score_units:
            score_units[label] = unit

    if not scores:
        scores["openlca_result"] = 0.0
        param_warnings.append(
            "No impact values returned by openLCA; using placeholder score."
        )

    payload: dict[str, Any] = {
        "runner": "openlca_ipc",
        "scores": scores,
        "parameter_redefinitions_applied": len(redefinitions),
        "parameter_names": [r.name for r in redefinitions if r.name],
    }
    if score_units:
        payload["score_units"] = score_units
    if functional_units is not None:
        payload["functional_units"] = functional_units
    if param_warnings:
        payload["warnings"] = param_warnings
    return payload


def _impact_label(impact, index: int) -> str:
    category = getattr(impact, "impact_category", None)
    if category is not None:
        name = (getattr(category, "name", None) or "").strip()
        if name:
            return name
        uid = (getattr(category, "id", None) or "").strip()
        if uid:
            return uid
    return f"impact_{index}"


def _impact_unit(impact: Any) -> str:
    category = getattr(impact, "impact_category", None)
    candidates = [
        getattr(impact, "unit", None),
        getattr(impact, "reference_unit", None),
        getattr(impact, "ref_unit", None),
        getattr(category, "reference_unit", None),
        getattr(category, "ref_unit", None),
        getattr(category, "unit", None),
    ]
    for raw in candidates:
        unit = _extract_unit_name(raw)
        if unit:
            return unit
    return ""


def _extract_parameter_redefinitions(
    model: dict[str, Any],
    parameter_catalog: dict[str, Any] | None = None,
):
    redefs_by_key: dict[tuple[str, str], Any] = {}
    warnings: list[str] = []
    functional_units: float | None = None

    raw_changes = model.get("changes")
    if isinstance(raw_changes, list):
        fu_from_changes = _consume_change_list(
            raw_changes=raw_changes,
            out=redefs_by_key,
            warnings=warnings,
            parameter_catalog=parameter_catalog,
        )
        if fu_from_changes is not None:
            functional_units = fu_from_changes

    if "number_functional_units" in model:
        direct_fu = _coerce_float(model.get("number_functional_units"))
        if direct_fu is None and model.get("number_functional_units") is not None:
            warnings.append(
                "Ignored 'number_functional_units' because it is not a numeric value."
            )
        elif direct_fu is not None:
            functional_units = direct_fu

    params_block = model.get("parameters")
    global_entries = None
    process_entries = None

    if isinstance(params_block, dict):
        global_entries = params_block.get("global_parameters")
        process_entries = params_block.get("process_parameters")

    # Backward compatibility with top-level parameter placement.
    if global_entries is None:
        global_entries = model.get("global_parameters")
    if process_entries is None:
        process_entries = model.get("process_parameters")

    if isinstance(global_entries, list):
        _consume_parameter_list(
            raw_list=global_entries,
            process_id=None,
            origin="global",
            out=redefs_by_key,
            warnings=warnings,
            parameter_catalog=parameter_catalog,
        )

    if isinstance(process_entries, dict):
        for process_id, raw_list in process_entries.items():
            _consume_parameter_list(
                raw_list=raw_list,
                process_id=str(process_id),
                origin=f"process:{process_id}",
                out=redefs_by_key,
                warnings=warnings,
                parameter_catalog=parameter_catalog,
            )

    return list(redefs_by_key.values()), functional_units, warnings


def _consume_change_list(
    raw_changes: list[Any],
    out: dict[tuple[str, str], Any],
    warnings: list[str],
    parameter_catalog: dict[str, Any] | None,
) -> float | None:
    functional_units: float | None = None

    for raw in raw_changes:
        if not isinstance(raw, dict):
            warnings.append("Skipped malformed change entry because it is not an object.")
            continue

        field = _clean_text(raw.get("field"))
        if not field:
            warnings.append("Skipped change entry with an empty 'field'.")
            continue

        if field == "number_functional_units":
            value = _coerce_float(raw.get("new_value"))
            if value is None:
                warnings.append(
                    "Skipped 'number_functional_units' change because 'new_value' is not numeric."
                )
                continue
            functional_units = value
            continue

        if field.startswith("parameters.global."):
            raw_name = field[len("parameters.global.") :].strip()
            name = _catalog_global_name(parameter_catalog, raw_name)
            if name is None:
                warnings.append(
                    f"Skipped unknown global parameter '{raw_name}' from change '{field}'."
                )
                continue

            value = _coerce_float(raw.get("new_value"))
            if value is None:
                warnings.append(
                    f"Skipped global parameter '{name}' because 'new_value' is not numeric."
                )
                continue

            key = ("", name.lower())
            out[key] = o.ParameterRedef(name=name, value=value)
            continue

        process_id_raw = ""
        raw_name = ""
        if field.startswith("parameters.process."):
            process_id_raw = _clean_text(raw.get("process_id"))
            raw_name = field[len("parameters.process.") :].strip()
            if not process_id_raw:
                warnings.append(
                    f"Skipped process parameter change '{field}' because 'process_id' is missing."
                )
                continue
        elif field.startswith("parameters.process:"):
            rest = field[len("parameters.process:") :]
            dot = rest.find(".")
            if dot <= 0:
                warnings.append(f"Skipped malformed process change field '{field}'.")
                continue
            process_id_raw = rest[:dot].strip()
            raw_name = rest[dot + 1 :].strip()
        else:
            warnings.append(f"Unsupported change field '{field}' was ignored.")
            continue

        process_id = _resolve_process_id(process_id_raw, parameter_catalog)
        if parameter_catalog is not None and process_id is None:
            warnings.append(
                f"Skipped process parameter change '{field}' because process "
                f"'{process_id_raw}' is unknown in the selected product system."
            )
            continue
        context_id = process_id or process_id_raw

        name = _catalog_process_name(parameter_catalog, context_id, raw_name)
        if name is None:
            warnings.append(
                f"Skipped unknown process parameter '{raw_name}' for process "
                f"'{context_id}'."
            )
            continue

        value = _coerce_float(raw.get("new_value"))
        if value is None:
            warnings.append(
                f"Skipped process parameter '{name}' for process '{context_id}' "
                "because 'new_value' is not numeric."
            )
            continue

        key = (context_id, name.lower())
        redef = o.ParameterRedef(name=name, value=value)
        redef.context = o.Ref(id=context_id, ref_type=o.RefType.Process)
        out[key] = redef

    return functional_units


def _consume_parameter_list(
    raw_list: Any,
    process_id: str | None,
    origin: str,
    out: dict[tuple[str, str], Any],
    warnings: list[str],
    parameter_catalog: dict[str, Any] | None,
) -> None:
    if not isinstance(raw_list, list):
        warnings.append(f"Skipped non-list parameter block at '{origin}'.")
        return

    context_id = ""
    if process_id is not None:
        process_id_clean = process_id.strip()
        resolved = _resolve_process_id(process_id_clean, parameter_catalog)
        if parameter_catalog is not None and resolved is None:
            warnings.append(
                f"Skipped process parameter block at '{origin}' because process "
                f"'{process_id_clean}' is unknown in the selected product system."
            )
            return
        context_id = resolved or process_id_clean

    for raw in raw_list:
        if not isinstance(raw, dict):
            warnings.append(f"Skipped malformed parameter entry at '{origin}'.")
            continue

        raw_name = str(raw.get("name") or "").strip()
        if not raw_name:
            warnings.append(f"Skipped unnamed parameter at '{origin}'.")
            continue

        if context_id:
            name = _catalog_process_name(parameter_catalog, context_id, raw_name)
            if name is None:
                warnings.append(
                    f"Skipped unknown process parameter '{raw_name}' at '{origin}'."
                )
                continue
        else:
            name = _catalog_global_name(parameter_catalog, raw_name)
            if name is None:
                warnings.append(
                    f"Skipped unknown global parameter '{raw_name}' at '{origin}'."
                )
                continue

        value = _coerce_float(raw.get("value"))
        if value is None:
            # If formula is actually numeric text, accept it.
            value = _coerce_float(raw.get("formula"))
        if value is None:
            warnings.append(
                f"Skipped parameter '{name}' at '{origin}' because it has "
                "no numeric value."
            )
            continue

        key = (context_id, name.lower())
        redef = o.ParameterRedef(name=name, value=value)
        if context_id:
            redef.context = o.Ref(id=context_id, ref_type=o.RefType.Process)
        out[key] = redef


def _catalog_global_name(
    parameter_catalog: dict[str, Any] | None,
    raw_name: str,
) -> str | None:
    name = raw_name.strip()
    if not name:
        return None
    if parameter_catalog is None:
        return name
    return parameter_catalog["global_name_map"].get(name.lower())


def _catalog_process_name(
    parameter_catalog: dict[str, Any] | None,
    process_id: str,
    raw_name: str,
) -> str | None:
    name = raw_name.strip()
    if not name:
        return None
    if parameter_catalog is None:
        return name

    process_names = parameter_catalog["process_param_name_map"].get(process_id)
    if process_names is None:
        needle = process_id.lower()
        for known_pid, known_names in parameter_catalog["process_param_name_map"].items():
            if known_pid.lower() == needle:
                process_names = known_names
                break
    if process_names is None:
        process_names = {}
    return process_names.get(name.lower())


def _resolve_process_id(
    raw_process_id: str,
    parameter_catalog: dict[str, Any] | None,
) -> str | None:
    pid = raw_process_id.strip()
    if not pid:
        return None
    if parameter_catalog is None:
        return pid

    if pid in parameter_catalog["process_ids"]:
        return pid

    lower = pid.lower()
    for known in parameter_catalog["process_ids"]:
        if known.lower() == lower:
            return known

    return parameter_catalog["process_name_map"].get(lower)


def _build_parameter_catalog(client, product_system: Any) -> dict[str, Any] | None:
    if product_system is None:
        return None

    catalog: dict[str, Any] = {
        "global_name_map": {},
        "process_ids": set(),
        "process_name_map": {},
        "process_param_name_map": {},
    }

    def add_global(name: str) -> None:
        clean = name.strip()
        if not clean:
            return
        catalog["global_name_map"].setdefault(clean.lower(), clean)

    def add_process(pid: str, pname: str | None = None) -> None:
        process_id = pid.strip()
        if not process_id:
            return
        catalog["process_ids"].add(process_id)
        catalog["process_param_name_map"].setdefault(process_id, {})
        if pname:
            label = pname.strip().lower()
            if label and label not in catalog["process_name_map"]:
                catalog["process_name_map"][label] = process_id

    def add_process_param(pid: str, param_name: str) -> None:
        process_id = pid.strip()
        clean = param_name.strip()
        if not process_id or not clean:
            return
        add_process(process_id)
        table = catalog["process_param_name_map"].setdefault(process_id, {})
        table.setdefault(clean.lower(), clean)

    set_globals, set_process = _extract_product_system_parameter_sets(product_system)
    for item in set_globals:
        add_global(str(item.get("name") or ""))
    for pid, items in set_process.items():
        add_process(pid)
        for item in items:
            add_process_param(pid, str(item.get("name") or ""))

    product_system_id = _extract_ref_id(product_system)
    if product_system_id:
        for raw_param in _safe_get_parameters(client, o.ProductSystem, product_system_id):
            context = getattr(raw_param, "context", None)
            context_id = _extract_ref_id(context)
            name = _clean_text(getattr(raw_param, "name", None))
            if not name:
                continue
            if context_id:
                add_process_param(context_id, name)
            else:
                add_global(name)

    legacy_globals = _extract_entity_parameters(
        getattr(product_system, "parameters", None),
        default_scope="global",
    )
    for item in legacy_globals:
        add_global(str(item.get("name") or ""))

    for process_ref in _collect_product_system_process_refs(product_system):
        pid = process_ref.get("id") or ""
        pname = process_ref.get("name")
        if not pid:
            continue
        add_process(pid, pname)

        process_entity = _safe_get(client, o.Process, pid)
        if process_entity is None:
            continue
        add_process(pid, _clean_text(getattr(process_entity, "name", None)))
        for param_name in _extract_process_parameter_names(process_entity):
            add_process_param(pid, param_name)
        for raw_param in _safe_get_parameters(client, o.Process, pid):
            name = _clean_text(getattr(raw_param, "name", None))
            if name:
                add_process_param(pid, name)

    return catalog


def _extract_process_parameter_names(process_entity: Any) -> set[str]:
    out: set[str] = set()

    raw_params = getattr(process_entity, "parameters", None)
    if isinstance(raw_params, (list, tuple)):
        for raw in raw_params:
            name = _clean_text(getattr(raw, "name", None))
            if name:
                out.add(name)

    exchanges = getattr(process_entity, "exchanges", None)
    if not isinstance(exchanges, (list, tuple)):
        return out

    for exchange in exchanges:
        formula = _first_non_empty_text(
            getattr(exchange, "formula", None),
            getattr(exchange, "amount_formula", None),
            getattr(exchange, "formula_text", None),
            getattr(exchange, "amount_expr", None),
            getattr(exchange, "amount_param", None),
        )
        for identifier in _extract_formula_identifiers(formula):
            out.add(identifier)

    return out


def _extract_formula_identifiers(formula: str) -> set[str]:
    if not formula:
        return set()
    out: set[str] = set()
    for token in _IDENTIFIER_TOKEN_RE.findall(formula):
        if token.lower() in _FORMULA_FUNCTION_NAMES:
            continue
        out.add(token)
    return out


def _extract_product_system_parameter_sets(
    product_system: Any,
) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    if product_system is None:
        return [], {}

    raw_sets = getattr(product_system, "parameter_sets", None)
    if raw_sets is None:
        raw_sets = getattr(product_system, "parameterSets", None)
    if not isinstance(raw_sets, (list, tuple)):
        return [], {}
    sets = [s for s in raw_sets if s is not None]
    if not sets:
        return [], {}

    picked_set = None
    for raw_set in sets:
        is_baseline = getattr(raw_set, "is_baseline", None)
        if isinstance(is_baseline, bool) and is_baseline:
            picked_set = raw_set
            break
        if str(is_baseline).strip().lower() in {"true", "1", "yes"}:
            picked_set = raw_set
            break
    if picked_set is None:
        picked_set = sets[0]
    if picked_set is None:
        return [], {}

    raw_params = getattr(picked_set, "parameters", None)
    if not isinstance(raw_params, (list, tuple)):
        return [], {}

    global_out: list[dict[str, Any]] = []
    process_out: dict[str, list[dict[str, Any]]] = {}
    for raw_param in raw_params:
        context = getattr(raw_param, "context", None)
        context_id = _extract_ref_id(context)
        context_type = _first_non_empty_text(
            getattr(getattr(context, "ref_type", None), "name", None),
            getattr(getattr(context, "ref_type", None), "value", None),
            getattr(context, "ref_type", None),
        ).lower()

        is_process_context = bool(context_id) and (
            "process" in context_type or not context_type
        )
        if is_process_context:
            item = _parameter_redef_to_public_dict(raw_param, scope="process")
            if item is None:
                continue
            process_out.setdefault(context_id, []).append(item)
        else:
            item = _parameter_redef_to_public_dict(raw_param, scope="global")
            if item is None:
                continue
            global_out.append(item)

    global_out = _merge_parameter_lists([], global_out, prefer_secondary=True)
    process_out = _merge_process_parameter_maps(
        {},
        process_out,
        prefer_extra=True,
    )
    return global_out, process_out


def _parameter_redef_to_public_dict(
    raw_param: Any,
    scope: str,
) -> dict[str, Any] | None:
    name = _clean_text(getattr(raw_param, "name", None))
    if not name:
        return None

    value = _coerce_float(getattr(raw_param, "value", None))
    formula = _clean_text(getattr(raw_param, "formula", None))
    if value is None and not formula:
        return None

    item: dict[str, Any] = {"name": name, "scope": scope}
    if value is not None:
        item["value"] = value
    if formula:
        item["formula"] = formula

    note = _first_non_empty_text(
        getattr(raw_param, "description", None),
        getattr(raw_param, "comment", None),
    )
    if note:
        item["note"] = note
    return item


def _merge_parameter_lists(
    primary: list[dict[str, Any]],
    secondary: list[dict[str, Any]],
    prefer_secondary: bool,
) -> list[dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for item in primary:
        name = _clean_text(item.get("name"))
        if not name:
            continue
        out[name.lower()] = item

    for item in secondary:
        name = _clean_text(item.get("name"))
        if not name:
            continue
        key = name.lower()
        if key not in out or prefer_secondary:
            out[key] = item

    merged = list(out.values())
    merged.sort(key=lambda item: _clean_text(item.get("name")).lower())
    return merged


def _merge_process_parameter_maps(
    base: dict[str, list[dict[str, Any]]],
    extra: dict[str, list[dict[str, Any]]],
    prefer_extra: bool,
) -> dict[str, list[dict[str, Any]]]:
    out: dict[str, list[dict[str, Any]]] = {
        pid: list(items) for pid, items in base.items()
    }
    for pid, extra_items in extra.items():
        existing = out.get(pid, [])
        out[pid] = _merge_parameter_lists(
            existing,
            list(extra_items),
            prefer_secondary=prefer_extra,
        )
    return out


def _coerce_float(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        v = float(value)
        return v if math.isfinite(v) else None
    if isinstance(value, str):
        txt = value.strip()
        if not txt:
            return None
        try:
            v = float(txt)
        except ValueError:
            return None
        return v if math.isfinite(v) else None
    return None


def _looks_like_uuid(text: str) -> bool:
    return bool(_UUID_RE.match(text.strip()))


def _ref_to_public_dict(ref) -> dict[str, Any]:
    return {
        "id": ref.id,
        "name": ref.name,
        "category": ref.category,
        "location": ref.location,
        "library": ref.library,
    }
