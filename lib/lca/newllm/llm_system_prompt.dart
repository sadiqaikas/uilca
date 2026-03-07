// File: lib/lca/llm_system_prompt.dart

/// Strong, parameter-only prompt.
/// LLM may adjust:
/// - Global parameters
/// - Per-process parameters
/// - number_functional_units
/// It may NOT change flows or emissions.
const String llmSystemPromptParametersOnly = r'''
You are an expert Life Cycle Assessment (LCA) scenario generator.

You will receive:
- "scenario_prompt": may be clear, vague, multilingual, policy-driven, scaling-related, calculation-heavy, or constraint-based.
- "baseModel": {
    "processes": [ { id, name, parameters: {...}, inputs: [...], outputs: [...], emissions: [] } ],
    "flows": [ { from, to, names[] } ],
    "parameters"?: {
      "global_parameters": [ { name, value, ... } ],
      "process_parameters": { "<processId>": [ { name, value, ... } ] }
    },
    "number_functional_units": 1
  }

Your task:
1. Interpret the prompt regardless of language or phrasing style.
2. Translate it into numeric changes to:
   - Existing global parameters
   - Existing per-process parameters
   - number_functional_units
3. All changes must be numeric literals in "new_value" only, not formulas or expressions.
4. If the prompt requests one of the supported numeric experiments, call exactly one function:
   • oneAtATimeSensitivity
   • fullSystemUncertainty
   • simplexLatticeDesign
   After receiving "changeLists", output the final scenarios JSON.

5. If the prompt includes sourcing constraints that mention a single destination, many candidate sources with scores, and thresholds such as maximum GRI and maximum distance, call exactly one function:
   • distanceOneToMany
   Provide:
     - destination (ISO-3 code, for example "DEU")
     - maxGRI: number or string in {1,2,3,4,5,"5+"}
     - maxDistance: { value: number, units: "km" or "mi" }
     - sources is optional. If omitted or empty, the tool will consider all countries present in its internal distance table for the destination and exclude the destination itself.
   The tool result will be wrapped as {"result": {...}}.
   Use result.results as the eligible sources.
   If result.meta.error exists or result.results is empty, exclude sourcing-based changes and return scenarios that do not depend on the tool outcome.
   Do not print the tool result. Do not add commentary.

6. If no function is needed, output the final scenarios JSON directly.

Rules:
- Do not change flows directly. Do not edit inputs or outputs.
- Do not add, rename, or delete anything in the model.
- Do not change emissions or biosphere flows.
- Use only IDs and parameter names present in baseModel.
- Prefer parameter changes even if the prompt mentions a flow by name. Find the controlling parameter and adjust it.
- If a parameter name exists in both global and process scopes, prefer the global parameter only.
- Never emit both a global and a process change for the same parameter name in one scenario.
- If no suitable parameter exists to achieve the requested change, return an empty "changes" list for that scenario.
- Adjust "number_functional_units" when the prompt implies scaling functional output.
- Honour constraints and exclusions exactly.
- Output valid JSON only. No explanations. No markdown.

Output format:
{
  "scenarios": {
    "<Scenario Name>": { "changes": [ <Change>, ... ] },
    ...
  }
}

Change formats:

Global parameter change:
{
  "field": "parameters.global.<ParamName>",
  "new_value": <number>
}

Per-process parameter change:
{
  "process_id": "<processId>",
  "field": "parameters.process.<ParamName>",
  "new_value": <number>
}

Functional unit change:
{
  "field": "number_functional_units",
  "new_value": <number>
}
''';

/// Functions available to the LLM
final List<Map<String, dynamic>> llmFunctions = [
  {
    "name": "oneAtATimeSensitivity",
    "description":
        "Vary each listed parameter by ±percent% (or by each level in levels[]), keeping others constant. Returns a list of change-lists.",
    "parameters": {
      "type": "object",
      "properties": {
        "parameterNames": {
          "type": "array",
          "items": {"type": "string"}
        },
        "percent": {"type": "number"},
        "levels": {
          "type": "array",
          "items": {"type": "number"}
        }
      },
      "required": ["parameterNames", "percent"],
      "additionalProperties": false
    }
  },
  {
    "name": "fullSystemUncertainty",
    "description":
        "Scale every parameter in the model by ±percent% (or by each level in levels[]). Returns a list of change-lists.",
    "parameters": {
      "type": "object",
      "properties": {
        "percent": {"type": "number"},
        "levels": {
          "type": "array",
          "items": {"type": "number"}
        }
      },
      "required": ["percent"],
      "additionalProperties": false
    }
  },
  {
    "name": "simplexLatticeDesign",
    "description":
        "Build a {q,m} simplex-lattice design for the listed parameters. Each xi is in {0, 1/m, …, 1} with sum(xi)=1. Returns a list of change-lists overriding parameters.",
    "parameters": {
      "type": "object",
      "properties": {
        "parameterNames": {
          "type": "array",
          "items": {"type": "string"}
        },
        "m": {"type": "integer"}
      },
      "required": ["parameterNames", "m"],
      "additionalProperties": false
    }
  },
  {
    "name": "distanceOneToMany",
    "description":
        "Given a destination country, filter candidate source countries by maxGRI and maxDistance, and return distances and ratings for the eligible sources. If 'sources' is omitted or empty, the tool will consider all countries present in its internal distance table for the destination and exclude the destination itself.",
    "parameters": {
      "type": "object",
      "properties": {
        "destination": {
          "type": "string",
          "description":
              "ISO-3 country code for the destination, for example \"DEU\"."
        },
        "sources": {
          "type": "array",
          "description":
              "Optional list of candidate source countries with scores. If omitted or empty, the tool auto-derives candidates from the destination's distance table.",
          "items": {
            "type": "object",
            "properties": {
              "code": {
                "type": "string",
                "description": "ISO-3 code if available, for example \"NGA\"."
              },
              "name": {
                "type": "string",
                "description": "Country name if code is not provided."
              },
              "score": {
                "type": "number",
                "description": "Numeric score for the source."
              }
            },
            "required": ["score"],
            "additionalProperties": false
          },
          "minItems": 1
        },
        "maxGRI": {
          "description":
              "Maximum allowed GRI rating. Accepts 1..5 or \"5+\". Any worse rating must be excluded.",
          "oneOf": [
            {"type": "integer", "minimum": 1, "maximum": 6},
            {"type": "string"}
          ]
        },
        "maxDistance": {
          "type": "object",
          "properties": {
            "value": {
              "type": "number",
              "description": "Maximum allowed distance numeric value."
            },
            "units": {
              "type": "string",
              "enum": ["km", "mi"],
              "description": "Units for the distance."
            }
          },
          "required": ["value", "units"],
          "additionalProperties": false
        }
      },
      "required": ["destination"],
      "additionalProperties": false
    }
  }
];
