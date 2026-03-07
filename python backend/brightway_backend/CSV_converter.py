

# -*- coding: utf-8 -*-
"""
SimaPro CSV → biosphere3 linker with higher coverage for eutrophication, toxicity, and ozone.
- Stronger VOC aliases: Decane (air and water), Cresol, PAH.
- Metals: explicit water/soil ion handling with valence preference; air uses elemental.
- Salts: Magnesium chloride; Sodium ion; plus common inorganic indicators (BOD, COD, TOC, TSS).
- Resources: energy-from-oil/coal, surface water, aggregates and minerals clean-up.
- Radioactivity: canonical kBq handling.
- Unit canon keys used for indexing. Conservative matching with safe fallbacks.
"""

from __future__ import annotations

import json
import sys
import re
from pathlib import Path
from collections import defaultdict, Counter

# ---- Brightway bootstrap (no-op if already initialised)
from bw2io.migrations import create_core_migrations
create_core_migrations()

from bw2io import SimaProCSVImporter
from bw2data import Database

# ---- Similarity
try:
    from rapidfuzz import fuzz, utils
    HAVE_RF = True
except Exception:
    HAVE_RF = False
    try:
        import Levenshtein
    except ImportError:
        sys.exit("Install rapidfuzz or python-Levenshtein")

import pandas as pd

# =========================
# Settings
# =========================
CSV_PATH = Path("/Users/admin/Downloads/aluminium.csv")
DB_NAME  = "my_simapro_db"
OUT_DIR  = Path.cwd()
MANUAL_MAP_PATH = OUT_DIR / "manual_bio_map.json"

# Thresholds
THRESH_MAIN   = 0.865
MARGIN_MAIN   = 0.05
THRESH_AUTO2  = 0.975
MARGIN_AUTO2  = 0.09
TOPK_SUGGEST  = 6
ALIAS_BONUS   = 0.02

# =========================
# Normalisation helpers
# =========================
STOPWORDS = {"to","of","and","the","as","in","on","total"}
CAS_RE = re.compile(r"\b\d{2,7}-\d{2}-\d\b", re.I)

def norm_spaces(s: str) -> str:
    return re.sub(r"\s+", " ", s or "").strip()

def squash(s: str) -> str:
    s = s.replace("µ","u")
    s = re.sub(r"[‐‒–—−]", "-", s)
    s = re.sub(r"\s*[,;]\s*", ", ", s)
    s = re.sub(r"\s*/\s*", "/", s)
    return norm_spaces(s)

def lower(s: str) -> str:
    return squash(s).lower()

# Units. Canonical key is used for indices.
_UNIT_CANON_RAW = {
    # mass → kilogram
    "kg": ("kilogram", 1.0),
    "kilogram": ("kilogram", 1.0),
    "g": ("kilogram", 1/1000),
    "gram": ("kilogram", 1/1000),
    "mg": ("kilogram", 1/1e6),
    "ug": ("kilogram", 1/1e9),
    "t": ("kilogram", 1000.0),
    "ton": ("kilogram", 1000.0),
    "tonne": ("kilogram", 1000.0),

    # volume → cubic metre
    "m3": ("cubic meter", 1.0),
    "m^3": ("cubic meter", 1.0),
    "cubic meter": ("cubic meter", 1.0),
    "cubic metre": ("cubic meter", 1.0),
    "l": ("cubic meter", 1/1000),
    "liter": ("cubic meter", 1/1000),
    "litre": ("cubic meter", 1/1000),
    "ml": ("cubic meter", 1/1e6),
    "cm3": ("cubic meter", 1/1e6),

    # area → square metre
    "m2": ("square meter", 1.0),
    "m^2": ("square meter", 1.0),
    "square meter": ("square meter", 1.0),
    "square metre": ("square meter", 1.0),

    # area*time
    "m2a": ("square meter year", 1.0),
    "m^2a": ("square meter year", 1.0),

    # radioactivity → canonicalise to kBq
    "bq": ("kilo becquerel", 1/1000),
    "kbq": ("kilo becquerel", 1.0),
    "kilo becquerel": ("kilo becquerel", 1.0),
    "kilo becquerels": ("kilo becquerel", 1.0),
    "mbq": ("kilo becquerel", 1000.0),
    "gbq": ("kilo becquerel", 1_000_000.0),

    # energy
    "j": ("megajoule", 1/1e6),
    "kj": ("megajoule", 1/1000),
    "mj": ("megajoule", 1.0),
    "megajoule": ("megajoule", 1.0),
    "gj": ("megajoule", 1000.0),
    "wh": ("kilowatt hour", 1/1000),
    "kwh": ("kilowatt hour", 1.0),
    "mwh": ("kilowatt hour", 1000.0),
    "kilowatt hour": ("kilowatt hour", 1.0),
}
UNIT_CANON = {k.lower(): v for k, v in _UNIT_CANON_RAW.items()}

def unit_key(u: str) -> str:
    u0 = lower(u)
    return UNIT_CANON[u0][0] if u0 in UNIT_CANON else u

def unit_norm(u: str, amount: float) -> tuple[str, float]:
    u0 = lower(u)
    if u0 in UNIT_CANON:
        tgt, fac = UNIT_CANON[u0]
        return tgt, amount * fac
    return u, amount

def is_mass(u: str) -> bool:
    return unit_key(u) == "kilogram"

# Compartment mapping
COMP_MAP = {
    # air
    "air": ("air", None),
    "air/urban air close to ground": ("air", "urban air close to ground"),
    "air/non-urban air or from high stacks": ("air", "non-urban air or from high stacks"),
    "air/high population density": ("air", "high population density"),
    "air/low population density": ("air", "low population density"),
    # water
    "water": ("water", None),
    "water/fresh water": ("water", "surface water"),
    "water/surface water": ("water", "surface water"),
    "water/river": ("water", "surface water"),
    "water/lake": ("water", "surface water"),
    "water/ground water": ("water", "ground-"),
    "water/sea": ("water", "ocean"),
    "water/ocean": ("water", "ocean"),
    "water/brackish": ("water", "ocean"),
    # soil
    "soil": ("soil", None),
    "soil/agricultural": ("soil", "agricultural"),
    "soil/industrial": ("soil", "industrial"),
    "soil/forest": ("soil", "forest"),
    "soil/forestry": ("soil", "forest"),
    # resources and land
    "resource": ("natural resource", None),
    "resources": ("natural resource", None),
    "resource/in ground": ("natural resource", "in ground"),
    "resource/water": ("natural resource", "in water"),
    "resource/biotic": ("natural resource", "biotic"),
    "natural resources": ("natural resource", None),
    "natural resources/in ground": ("natural resource", "in ground"),
    "natural resources/water": ("natural resource", "in water"),
    "natural resource/in air": ("natural resource", "in air"),
    "land use": ("natural resource", "land"),
    "land occupation": ("natural resource", "land"),
    "land transformation": ("natural resource", "land"),
}

def parse_comp(categories) -> tuple[str|None, str|None]:
    if isinstance(categories, (list, tuple)) and categories:
        key = "/".join([c for c in categories if c]).lower()
        if key in COMP_MAP:
            return COMP_MAP[key]
        top = categories[0].lower()
        sub = categories[1].lower() if len(categories) > 1 else None
        if top in {"resources","resource","natural resources"}:
            return ("natural resource", sub or None)
        if top in {"land use","land occupation","land transformation"}:
            return ("natural resource", "land")
        return (top, sub)
    return (None, None)

# Metals and valence preferences for water/soil
METALS = {
    "aluminium","aluminum","antimony","arsenic","barium","beryllium","cadmium",
    "chromium","cobalt","copper","lead","manganese","mercury","molybdenum",
    "nickel","selenium","vanadium","zinc","thallium","iron","calcium","silver",
    "sodium","magnesium","tin","vanadium"
}
METAL_OX = {
    "aluminium": "Aluminium III", "aluminum": "Aluminium III",
    "antimony": "Antimony III", "arsenic": "Arsenic III",
    "barium": "Barium II", "beryllium": "Beryllium II", "cadmium": "Cadmium II",
    "chromium": "Chromium VI", "cobalt": "Cobalt II", "copper": "Copper II",
    "lead": "Lead II", "manganese": "Manganese II", "mercury": "Mercury II",
    "molybdenum": "Molybdenum VI", "nickel": "Nickel II", "selenium": "Selenium IV",
    "vanadium": "Vanadium V", "zinc": "Zinc II", "iron": "Iron III",
    "calcium": "Calcium II", "silver": "Silver I", "magnesium": "Magnesium II",
    "tin": "Tin II",
}

def tidy_resource(n: str) -> str:
    n0 = lower(n)
    n0 = n0.replace("barite","baryte")
    if n0.startswith("sand, quartz"): n0 = "quartz sand"
    if "apatite" in n0: n0 = "phosphate rock"
    if "chromite" in n0: n0 = "chromite"
    if "cassiterite" in n0: n0 = "cassiterite"
    # strip ore content qualifiers
    n0 = re.sub(r",\s*\d+(\.\d+)?%\s+in\s+\w+(?:\s+deposit)?", "", n0)
    n0 = re.sub(r",\s*\d+(\.\d+)?%\s+in\s+crude\s+ore", "", n0)
    n0 = re.sub(r",\s*in\s+(?:crude\s+)?ore", "", n0)
    n0 = n0.strip(", ")
    return " ".join(w.capitalize() for w in n0.split())

# as N / as P
MM = {
    "N": 14.0067, "P": 30.9738,
    "NO3": 62.0049, "NO2": 46.0055, "NH3": 17.0305, "NH4": 18.0385, "PO4": 94.9714,
}
AS_N = re.compile(r"\bas\s*n\b", re.I)
AS_P = re.compile(r"\bas\s*p\b", re.I)
def as_factor(name: str) -> float:
    n = lower(name)
    try:
        if AS_N.search(n):
            if "nitrate" in n or re.search(r"\bno\s*3\b|no3-?", n): return MM["NO3"]/MM["N"]
            if "nitrite" in n or re.search(r"\bno\s*2\b|no2-?", n): return MM["NO2"]/MM["N"]
            if "ammonium" in n or re.search(r"\bnh\s*4\b|nh4\+?", n): return MM["NH4"]/MM["N"]
            if "ammonia"  in n or re.search(r"\bnh\s*3\b|nh3\b", n):  return MM["NH3"]/MM["N"]
        if AS_P.search(n):
            if "phosphate" in n or re.search(r"\bpo\s*4\b|po4", n):  return MM["PO4"]/MM["P"]
    except Exception:
        return 1.0
    return 1.0
def apply_as(name: str, amount: float) -> float:
    return float(amount) * as_factor(name)

# GHG aliases
GHG = {
    "sf6": "Sulfur hexafluoride",
    "sulphur hexafluoride": "Sulfur hexafluoride",
    "sulfur hexafluoride": "Sulfur hexafluoride",
    "nf3": "Nitrogen trifluoride",
    "hfc-134a": "1,1,1,2-Tetrafluoroethane",
    "tetrafluoroethane": "1,1,1,2-Tetrafluoroethane",
    "hfc-23": "Trifluoromethane",
    "hfc-125": "Pentafluoroethane",
    "hfc-152a": "1,1-Difluoroethane",
    "pfc-14": "Tetrafluoromethane",
    "pfc-116": "Hexafluoroethane",
}

# Radioisotopes: choose spelling that exists in your biosphere
RAD_CHOICES = {
    "cs134": ["Caesium-134","Cesium-134"],
    "cs-134": ["Caesium-134","Cesium-134"],
    "cs137": ["Caesium-137","Cesium-137"],
    "cs-137": ["Caesium-137","Cesium-137"],
    "co-60": ["Cobalt-60"], "co60": ["Cobalt-60"],
    "i-131": ["Iodine-131"], "i131": ["Iodine-131"],
    "sr-90": ["Strontium-90"], "sr90": ["Strontium-90"],
}

# Known CAS for a few stubborn items that often lack CAS in exports
KNOWN_CAS = {
    "decane": "124-18-5",
    "cresol": "1319-77-3",
    "magnesium chloride": "7786-30-3",
}

# =========================
# Similarity
# =========================
def sratio(a: str, b: str) -> float:
    if HAVE_RF:
        a2 = utils.default_process(a)
        b2 = utils.default_process(b)
        s1 = fuzz.QRatio(a2, b2)
        s2 = fuzz.token_set_ratio(a2, b2)
        s3 = fuzz.partial_ratio(a2, b2)
        return max(0.6*s1+0.4*s2, s2, 0.5*s2+0.5*s3)/100.0
    import Levenshtein
    return Levenshtein.ratio(a, b)

def tokens(s: str) -> set[str]:
    return {t for t in re.sub(r"[^\w\- ]+"," ", lower(s)).split() if t and t not in STOPWORDS}

def tscore(a: str, b: str) -> float:
    ta, tb = tokens(a), tokens(b)
    return len(ta & tb)/max(len(ta), len(tb)) if ta and tb else 0.0

def combo(a: str, b: str) -> float:
    return 0.7*sratio(a,b) + 0.3*tscore(a,b)

# =========================
# Manual overrides
# =========================
def load_manual(path: Path) -> dict[str,str]:
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return {str(k): str(v) for k,v in data.items() if isinstance(v,str)}
        except Exception:
            pass
    return {}
def manual_key(name: str, unit: str, comp: str|None) -> str:
    return f"{lower(name)}|{unit}|{(comp or '').lower()}"

# =========================
# Build biosphere indices
# =========================
bio = Database("biosphere3")

bio_records = []
bio_by_exact = {}
bio_by_exact_comp = {}
bio_by_unit = defaultdict(list)
bio_by_unit_comp = defaultdict(list)
bio_by_cas = defaultdict(list)
bio_names_by_unit = defaultdict(set)

def canon_name(n: str) -> str:
    return squash(n)

for f in bio:
    name = canon_name(f["name"])
    u_raw = f.get("unit","")
    u_key = unit_key(u_raw)
    cats = tuple(f.get("categories") or ())
    comp = cats[0] if cats else None
    cas  = f.get("CAS number") or None

    rec = {
        "name": name,
        "unit": u_raw,
        "unit_key": u_key,
        "uuid": str(f["code"]),
        "compartment": comp,
        "cats": cats,
        "name_norm": lower(name),
    }
    bio_records.append(rec)
    bio_by_exact[(lower(name), u_key)] = rec
    bio_by_exact_comp[(lower(name), u_key, comp)] = rec
    bio_by_unit[u_key].append(rec)
    bio_by_unit_comp[(u_key, comp)].append(rec)
    bio_names_by_unit[u_key].add(lower(name))
    if cas:
        bio_by_cas[cas].append(rec)

manual_map = load_manual(MANUAL_MAP_PATH)
stats = Counter()

def pick_existing(cands: list[str], u_key: str) -> str|None:
    pool = bio_names_by_unit.get(u_key, set())
    for nm in cands:
        if lower(nm) in pool:
            return nm
    # any unit fallback
    for pool in bio_names_by_unit.values():
        for nm in cands:
            if lower(nm) in pool:
                return nm
    return None

# =========================
# Aliasing
# =========================
def metal_alias(base: str, comp: str|None, raw: str, u_key: str) -> str:
    base_l = base.lower()
    proper = "Aluminium" if base_l == "aluminum" else base.capitalize()
    if comp and comp.startswith("natural resource"):
        return f"{proper}, in ground"
    if comp in {"water","soil","forest","agricultural","industrial"}:
        ox = METAL_OX.get(base_l)
        if ox and lower(ox) in bio_names_by_unit.get(u_key,set()):
            return ox
        for cand in (f"{proper}, ion", proper):
            if lower(cand) in bio_names_by_unit.get(u_key,set()):
                return cand
        return f"{proper}, ion"
    if "ion" in raw.lower():
        return proper
    return proper

def energy_alias(n: str, u_key: str) -> str|None:
    t = lower(n)
    pairs = [
        ("from oil","Energy, gross calorific value, in crude oil"),
        ("from coal","Energy, gross calorific value, in hard coal"),
        ("from wood","Energy, gross calorific value, in biomass"),
        ("from biomass","Energy, gross calorific value, in biomass"),
        ("from wind","Energy, kinetic (in wind), converted"),
        ("from solar","Energy, solar, converted"),
        ("from hydro","Energy, potential (in hydropower reservoir), converted"),
    ]
    for key, nm in pairs:
        if key in t and lower(nm) in bio_names_by_unit.get(u_key,set()):
            return nm
    if "from oil" in t:
        # fallback to crude oil resource
        for pool in bio_names_by_unit.values():
            if "crude oil, in ground" in pool:
                return "Crude oil, in ground"
    return None

def alias_with_comp(name: str, comp: str|None, u_key: str) -> tuple[str,bool]:
    n_raw = name or ""
    n = lower(n_raw)
    # remove as N/P flags
    n = norm_spaces(AS_N.sub("", n))
    n = norm_spaces(AS_P.sub("", n))

    # tidy tokens
    n = n.replace("sulphur","sulfur").replace("naphtalene","naphthalene")
    n = re.sub(r"\bno\s*3\b","no3", n)
    n = re.sub(r"\bno\s*2\b","no2", n)
    n = re.sub(r"\bnh\s*4\b","nh4", n)
    n = re.sub(r"\bnh\s*3\b","nh3", n)
    n = re.sub(r"\bpo\s*4\b","po4", n)

    # particulates buckets
    if "particulate" in n or "particulates" in n or re.search(r"\bpm\s*10\b|\bpm\s*2\.?5\b", n):
        cands = []
        if "2.5" in n or "< 2.5" in n:
            cands = ["Particulate matter, < 2.5 um"]
        elif "> 10" in n:
            cands = ["Particulates, > 10 um", "Particulate matter, > 10 um"]
        else:
            cands = [
                "Particulate matter, > 2.5 um, and < 10um",
                "Particulate matter, > 2.5 um and < 10um",
            ]
        return pick_existing(cands, u_key) or cands[0], True

    # GHG
    if "co2" in n or "carbon dioxide" in n:
        return ("Carbon dioxide, biogenic" if "biogenic" in n else "Carbon dioxide, fossil"), True
    if n.strip()=="ch4" or "methane" in n:
        return ("Methane, biogenic" if "biogenic" in n else "Methane, fossil"), True
    if n.strip()=="n2o" or "nitrous oxide" in n:
        return "Nitrous oxide", True
    for k,v in GHG.items():
        if k in n:
            return v, True

    # radioisotopes
    for k, cands in RAD_CHOICES.items():
        if k in n:
            return pick_existing(cands, u_key) or cands[0], True

    # nutrients
    if "nitrate" in n or "no3" in n:  return "Nitrate", True
    if "nitrite" in n or "no2" in n:  return "Nitrite", True
    if "ammonium" in n or "nh4" in n: return "Ammonium", True
    if "ammonia" in n or "nh3" in n:  return "Ammonia", True
    if "phosphate" in n or "po4" in n or "orthophosphate" in n: return "Phosphate", True

    # standard water quality
    if re.search(r"\bbod\b|\bbod5\b|biochemical oxygen demand", n): return "Biochemical oxygen demand, BOD5", True
    if re.search(r"\bcod\b|chemical oxygen demand", n):          return "Chemical oxygen demand", True
    if "total organic carbon" in n or re.search(r"\btoc\b", n):  return "Total organic carbon", True
    if "total suspended solids" in n or re.search(r"\btss\b", n):return "Total suspended solids", True

    # NMVOC
    if "nmvoc" in n or "volatile organic compounds, unspecified origin" in n or n.strip() == "voc":
        if comp == "air":
            return "NMVOC, non-methane volatile organic compounds", True

    # PAH
    if "pah" in n or "polycyclic aromatic hydrocarbons" in n:
        cands = ["PAH, polycyclic aromatic hydrocarbons"]
        return pick_existing(cands, u_key) or cands[0], True

    # key VOCs
    if re.search(r"\bdecane\b", n):
        cands = ["n-Decane","Decane"]
        return pick_existing(cands, u_key) or "Decane", True
    if "cresol" in n:
        cands = ["Cresol","Cresols","m-Cresol","o-Cresol","p-Cresol"]
        return pick_existing(cands, u_key) or "Cresol", True
    for voc in ("benzene","toluene","xylene","formaldehyde","acetaldehyde","styrene",
                "ethanol","methanol","naphthalene","phenol","acetone","ethylbenzene"):
        if voc in n:
            return voc.capitalize(), True

    # AOX
    if "aox" in n:
        cands = [
            "AOX, Adsorbable organic halogens, as Cl",
            "AOX, Adsorbable Organic Halogen",
            "AOX, Adsorbable organic halogen",
        ]
        return pick_existing(cands, u_key) or cands[0], True

    # resources
    if comp and str(comp).startswith("natural resource"):
        if n.strip() in {"water, surface","water surface"}:
            return "Water, surface water", True
        pe = energy_alias(n, u_key)
        if pe:
            return pe, True
        base = tidy_resource(n)
        c = (comp or "").lower()
        if "in ground" in c and not base.endswith(", in ground"):
            base += ", in ground"
        elif "in water" in c and not base.endswith(", in water"):
            base += ", in water"
        elif "in air" in c and not base.endswith(", in air"):
            base += ", in air"
        if base.lower() in {"aggregate, natural","aggregates, natural"}:
            cands = ["Aggregates, natural, in ground","Aggregates, natural"]
            return pick_existing(cands, u_key) or cands[-1], True
        return base, True

    # salts
    if "magnesium chloride" in n:
        return "Magnesium chloride", True
    if "sodium, ion" in n:
        return "Sodium, ion", True

    # metals
    base = n.split(",")[0].strip()
    if base in METALS:
        return metal_alias(base, comp, name, u_key), True

    # default title-case
    return " ".join(w.capitalize() for w in n.split()), False

# =========================
# Helpers
# =========================
def extract_cas(name: str, obj: dict) -> str|None:
    for k in ("CAS","cas","CAS number","CasNumber","cas_number"):
        v = obj.get(k)
        if isinstance(v, str):
            m = CAS_RE.search(v.strip())
            if m: return m.group(0)
    m = CAS_RE.search(name or "")
    if m: return m.group(0)
    # last resort: known CAS if exact base name
    base = lower((name or "").split(",")[0])
    return KNOWN_CAS.get(base)

def try_exact_any_comp(n_norm: str, u_key: str):
    for r in bio_by_unit.get(u_key, []):
        if r["name_norm"] == n_norm:
            return r
    return None

def try_exact_comp(n_norm: str, u_key: str, comp: str|None):
    return bio_by_exact_comp.get((n_norm, u_key, comp))

def try_mass_name_any_unit(n_norm: str, source_unit: str) -> dict|None:
    if not is_mass(source_unit):
        return None
    for r in bio_by_unit.get("kilogram", []):
        if r["name_norm"] == n_norm:
            return r
    return None

def direction(x: float) -> str:
    return "emission" if float(x) >= 0 else "uptake"

# =========================
# Matching
# =========================
def match_bio(name: str, unit_in: str, categories, exc_obj: dict, amount_in: float):
    unit, amount = unit_norm(unit_in, amount_in)
    u_key = unit_key(unit)
    new_amount = apply_as(name, amount)
    if new_amount != amount:
        amount = new_amount
        stats["as_basis_converted"] += 1

    comp, _ = parse_comp(categories)

    # manual override
    mk = manual_key(name, unit, comp)
    if mk in manual_map:
        stats["manual"] += 1
        return manual_map[mk], {"method":"manual","score":1.0}, unit, amount, name

    # CAS first
    cas = extract_cas(name, exc_obj)
    if cas:
        cands = bio_by_cas.get(cas, [])
        if cands:
            pool = [r for r in cands if r["unit_key"] == u_key]
            if comp is not None:
                pool2 = [r for r in pool if r["compartment"] == comp]
                pool = pool2 or pool
            if len(pool) == 1:
                r = pool[0]
                stats["cas_exact"] += 1
                return r["uuid"], {"method":"cas","score":1.0}, unit, amount, r["name"]
            scored = [(combo(name, r["name"]), r) for r in (pool or cands)]
            scored.sort(key=lambda x: x[0], reverse=True)
            best_s, best_r = scored[0]
            second_s = scored[1][0] if len(scored)>1 else 0.0
            if best_s >= THRESH_MAIN and best_s - second_s >= MARGIN_MAIN:
                stats["cas_tiebreak"] += 1
                return best_r["uuid"], {"method":"cas+tiebreak","score":float(best_s)}, unit, amount, best_r["name"]
            stats["cas_ambiguous"] += 1

    # alias then exact
    aliased, rule_hit = alias_with_comp(name, comp, u_key)
    n_norm = lower(aliased)

    r_comp = try_exact_comp(n_norm, u_key, comp)
    if r_comp:
        stats["exact"] += 1
        return r_comp["uuid"], {"method":"exact_name_unit_comp","score":1.0}, unit, amount, r_comp["name"]

    r_any = try_exact_any_comp(n_norm, u_key)
    if r_any:
        if comp and r_any["compartment"] and r_any["compartment"] != comp:
            pool = [r for r in bio_by_unit_comp.get((u_key, comp), []) if r["name_norm"] == n_norm]
            if pool:
                r = pool[0]
                stats["exact_comp_fix"] += 1
                return r["uuid"], {"method":"exact_name_unit+comp_fix","score":1.0}, unit, amount, r["name"]
        stats["exact_any_comp"] += 1
        return r_any["uuid"], {"method":"exact_name_unit_any_comp","score":1.0}, unit, amount, r_any["name"]

    # fuzzy
    pool = bio_by_unit_comp.get((u_key, comp)) or bio_by_unit.get(u_key, [])
    if not pool:
        pool = bio_records
        stats["fullpool"] += 1
    scored = [(combo(n_norm, r["name_norm"]), r) for r in pool]
    scored.sort(key=lambda x: x[0], reverse=True)
    best_s, best_r = scored[0]
    second_s = scored[1][0] if len(scored)>1 else 0.0

    if rule_hit and (best_s + ALIAS_BONUS >= THRESH_MAIN - 0.03) and (best_s - second_s >= MARGIN_MAIN):
        stats["fuzzy_rule_hit"] += 1
        return best_r["uuid"], {"method":"rule_hit+fuzzy","score":float(best_s)}, unit, amount, best_r["name"]

    if best_s >= THRESH_MAIN and best_s - second_s >= MARGIN_MAIN:
        stats["fuzzy_link"] += 1
        return best_r["uuid"], {"method":"fuzzy_high_conf","score":float(best_s)}, unit, amount, best_r["name"]

    # unit-only fallback
    if best_s >= THRESH_MAIN - 0.05:
        pool_u = bio_by_unit.get(u_key, [])
        scored_u = [(combo(n_norm, r["name_norm"]), r) for r in pool_u]
        scored_u.sort(key=lambda x: x[0], reverse=True)
        if scored_u and scored_u[0][0] >= THRESH_MAIN:
            r = scored_u[0][1]
            stats["fallback_unit_only"] += 1
            return r["uuid"], {"method":"fuzzy_unit_fallback","score":float(scored_u[0][0])}, unit, amount, r["name"]

    # coarse particulate downgrade
    if "particulate matter" in n_norm and "> 10" in n_norm:
        for alt in ["Particulate matter, > 2.5 um, and < 10um",
                    "Particulate matter, > 2.5 um and < 10um"]:
            r_alt = try_exact_any_comp(lower(alt), u_key)
            if r_alt:
                stats["particulate_downgrade"] += 1
                return r_alt["uuid"], {"method":"particulate_bucket_downgrade","score":1.0}, unit, amount, r_alt["name"]

    # last mass-safe
    r_mass = try_mass_name_any_unit(n_norm, unit)
    if r_mass:
        stats["exact_name_any_unit_mass"] += 1
        return r_mass["uuid"], {"method":"exact_name_any_unit_mass","score":1.0}, unit, amount, r_mass["name"]

    # suggestions
    stats["suggest"] += 1
    topk = [{"name": r["name"], "uuid": r["uuid"], "score": float(s)} for s, r in scored[:TOPK_SUGGEST]]
    return None, {"method":"suggest","score":float(best_s),"topk":topk}, unit, amount, None

# =========================
# Import SimaPro and link
# =========================
imp = SimaProCSVImporter(str(CSV_PATH), DB_NAME)

# protect strategies that expect 'allocation'
for ds in imp.data:
    for exc in ds.get("exchanges", []) or []:
        if exc.get("type") == "production" and "allocation" not in exc:
            exc["allocation"] = None

imp.apply_strategies()

linked_entries, suggestions, complete_entries = [], [], []

for ds in imp.data:
    ds_id = str(ds.get("code",""))
    ds_name = ds.get("name","")
    inputs, outputs, emis_linked = [], [], []
    sug_ds = []

    for exc in ds.get("exchanges", []) or []:
        etype = exc.get("type","")
        name  = exc.get("name","")
        amount= float(exc.get("amount",0) or 0)
        unit0 = exc.get("unit","")
        cats  = exc.get("categories")

        if etype == "technosphere":
            if exc.get("input") is not None:
                _, code = exc["input"]
                inputs.append({"name":name,"amount":amount,"unit":unit0,"flow_uuid":str(code)})
            else:
                inputs.append({"name":name,"amount":amount,"unit":unit0,"flow_uuid":None})

        elif etype == "production":
            outputs.append({"name":name,"amount":amount,"unit":unit0})

        elif etype == "biosphere":
            if exc.get("input") is not None:
                _, code = exc["input"]
                u_n, a_n = unit_norm(unit0, amount)
                a_n2 = apply_as(name, a_n)
                if a_n2 != a_n:
                    a_n = a_n2; stats["as_basis_converted"] += 1
                emis_linked.append({
                    "name": name, "amount": a_n, "unit": u_n,
                    "flow_uuid": str(code), "direction": direction(a_n),
                })
                stats["prelinked"] += 1
            else:
                uuid, info, u_n, a_n, disp = match_bio(name, unit0, cats, exc, amount)
                if uuid:
                    emis_linked.append({
                        "name": disp or name, "amount": a_n, "unit": u_n,
                        "flow_uuid": uuid, "direction": direction(a_n),
                    })
                else:
                    sug = {
                        "dataset_id": ds_id, "dataset_name": ds_name,
                        "flow_name": name, "unit": unit0, "categories": cats,
                        "amount": amount,
                        "score": round(info.get("score",0.0), 3) if isinstance(info,dict) else 0.0,
                        "method": info.get("method") if isinstance(info,dict) else None,
                        "topk": info.get("topk", []) if isinstance(info,dict) else [],
                    }
                    sug_ds.append(sug)

    linked_entries.append({
        "id": ds_id, "name": ds_name,
        "inputs": inputs, "outputs": outputs, "emissions": emis_linked,
        "position": {"x":0,"y":0}, "isFunctional": False,
    })

    # very strict auto insert to "complete"
    emis_complete = list(emis_linked)
    for s in sug_ds:
        topk = s.get("topk") or []
        if not topk:
            continue
        if topk[0]["score"] >= THRESH_AUTO2 and (
            len(topk) == 1 or topk[0]["score"] - topk[1].get("score",0.0) >= MARGIN_AUTO2
        ):
            amt = float(s["amount"])
            amt = apply_as(s.get("flow_name",""), amt)
            if amt != float(s["amount"]):
                stats["as_basis_converted"] += 1
            emis_complete.append({
                "name": topk[0]["name"], "amount": amt, "unit": s["unit"],
                "flow_uuid": topk[0]["uuid"], "direction": direction(amt),
            })
        # special case: very high confidence radioisotopes in kBq
        elif re.search(r"\bces(i|a)um-1(34|37)\b", lower(s.get("flow_name",""))) and topk[0]["score"] >= 0.99:
            emis_complete.append({
                "name": topk[0]["name"], "amount": s["amount"], "unit": s["unit"],
                "flow_uuid": topk[0]["uuid"], "direction": direction(s["amount"]),
            })

    complete_entries.append({
        "id": ds_id, "name": ds_name,
        "inputs": inputs, "outputs": outputs, "emissions": emis_complete,
        "position": {"x":0,"y":0}, "isFunctional": False,
    })

    suggestions.extend(sug_ds)

# =========================
# Write outputs
# =========================
OUT_DIR.mkdir(parents=True, exist_ok=True)
paths = {
    "linked":   OUT_DIR / f"{DB_NAME}_linked.json",
    "unlinked": OUT_DIR / f"{DB_NAME}_unlinked.json",
    "complete": OUT_DIR / f"{DB_NAME}_complete.json",
}
with open(paths["linked"], "w", encoding="utf-8") as f:
    json.dump(linked_entries, f, indent=2, ensure_ascii=False)
with open(paths["unlinked"], "w", encoding="utf-8") as f:
    json.dump(suggestions, f, indent=2, ensure_ascii=False)
with open(paths["complete"], "w", encoding="utf-8") as f:
    json.dump(complete_entries, f, indent=2, ensure_ascii=False)

# Excel of suggestions
def flatten_suggestions(suggs):
    rows = []
    for s in suggs:
        base = {k:v for k,v in s.items() if k != "topk"}
        topk = s.get("topk") or []
        for i in range(TOPK_SUGGEST):
            if i < len(topk):
                base[f"cand{i+1}_name"]  = topk[i]["name"]
                base[f"cand{i+1}_uuid"]  = topk[i]["uuid"]
                base[f"cand{i+1}_score"] = round(topk[i]["score"], 3)
            else:
                base[f"cand{i+1}_name"]  = ""
                base[f"cand{i+1}_uuid"]  = ""
                base[f"cand{i+1}_score"] = ""
        rows.append(base)
    return rows

pd.DataFrame(flatten_suggestions(suggestions)).to_excel(OUT_DIR / f"{DB_NAME}_unlinked.xlsx", index=False)

# =========================
# Diagnostics
# =========================
print("\nDiagnostics: top unlinked flow names")
print(Counter((s.get("flow_name","").lower().strip() or "<blank>") for s in suggestions).most_common(25))

print("\nDiagnostics: top unlinked units")
print(Counter((s.get("unit","") or "<blank>").strip().lower() for s in suggestions).most_common(12))

def comp_key(s):
    cats = s.get("categories") or []
    if isinstance(cats,(list,tuple)) and cats:
        return "/".join(cats).lower()
    return "<none>"

print("\nDiagnostics: top unlinked compartments")
print(Counter(comp_key(s) for s in suggestions).most_common(15))

co2_matched = sum(1 for d in linked_entries for e in d["emissions"]
                  if isinstance(e.get("name"), str) and "carbon dioxide" in e["name"].lower())
co2_suggest = sum(1 for s in suggestions
                  if isinstance(s.get("flow_name"), str) and "carbon dioxide" in s["flow_name"].lower())
print(f"\nCO2 already matched: {co2_matched}, CO2 still suggested: {co2_suggest}")
print(f"Applied 'as N/P' conversions: {int(stats.get('as_basis_converted', 0))}")

met_unlinked = [s for s in suggestions
                if isinstance(s.get("flow_name"), str)
                and any(m in s["flow_name"].lower() for m in METALS)]
print(f"Unlinked suspected metal flows: {len(met_unlinked)}")

aox_unlinked = [s for s in suggestions
                if isinstance(s.get("flow_name"), str) and "aox" in s["flow_name"].lower()]
print(f"Unlinked AOX flows: {len(aox_unlinked)}")

# Coverage
total_bio = sum(1 for ds in imp.data for e in (ds.get("exchanges") or []) if e.get("type") == "biosphere")
matched = sum(len(d["emissions"]) for d in linked_entries)
print(f"\nMatched biosphere exchanges: {matched}/{total_bio} ({matched / max(1,total_bio):.1%})")
print("Link sources:", dict(stats))
print(f"Wrote JSON + Excel into {OUT_DIR}")

print("\nNote: if your ReCiPe method name shows 'GWP1000', that is a label quirk in your local method key for GWP100.")
  