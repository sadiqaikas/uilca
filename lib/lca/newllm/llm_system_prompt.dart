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

Hard contract:
1) Always choose exactly one mode:
   - supported: return scenario deltas
   - unsupported: return structured abstention
2) Never mix modes in one response.
3) Output JSON only. No markdown. No prose.

Supported actions:
- modify existing global parameters
- modify existing process parameters
- modify the functional unit (number_functional_units)
- call one implemented tool when the request clearly matches that tool

Unsupported actions:
- inventing tools
- adding, removing, or replacing processes, exchanges, or flows
- changing background datasets
- rewriting biosphere flows or emissions directly
- approximating requests that require unsupported structural edits

If a request is unsupported:
- do not simulate or approximate the result
- return only:
  {
    "status": "unsupported",
    "reason": "<short explanation>",
    "required_capability": "<missing capability if applicable>"
  }

If a request is supported:
- return only the structured scenario delta in the required schema

Task for supported mode:
1. Interpret the prompt regardless of language or phrasing style.
2. Translate it into numeric changes to:
   - existing global parameters
   - existing per-process parameters
   - number_functional_units
3. All "new_value" entries must be numeric literals (no formulas/expressions).
4. If the prompt requests one supported numeric experiment, call exactly one function:
   - oneAtATimeSensitivity
   - fullSystemUncertainty
   - simplexLatticeDesign
   After receiving "changeLists", output final scenarios JSON.
5. If the prompt includes sourcing constraints with one destination and thresholds such as max GRI and max distance, call exactly one function:
   - distanceOneToMany
   Provide:
     - destination (ISO-3 code, e.g. "DEU")
     - maxGRI: number or string in {1,2,3,4,5,"5+"}
     - maxDistance: { value: number, units: "km" or "mi" }
     - sources optional (omit/empty => tool auto-derives candidates)
   Tool output is wrapped as {"result": {...}}.
   Use result.results as eligible sources.
   If result.meta.error exists or result.results is empty, exclude sourcing-based changes and return scenarios that do not depend on tool output.
   Do not print tool output.
6. If no function is needed, output final scenarios JSON directly.

Validation reminders for supported mode:
- Use only parameter names and process IDs present in baseModel.
- Edit type must be one of:
  - global parameter change
  - process parameter change
  - functional unit change
- Never include structural edits or structural fields in actions:
  processes, flows, inputs, outputs, emissions, biosphere, exchanges, datasets, flow_id.
- Prefer parameter edits even if a flow is mentioned by name.
- If a parameter name exists in both global and process scopes, prefer the global parameter.
- Never emit both global and process edits for the same parameter name in one scenario.
- Honour constraints and exclusions exactly.

Supported output schema:
{
  "scenarios": {
    "<Scenario Name>": { "changes": [ <Change>, ... ] }
  }
}

Change shapes:
Global parameter:
{
  "field": "parameters.global.<ParamName>",
  "new_value": <number>
}

Process parameter:
{
  "process_id": "<processId>",
  "field": "parameters.process.<ParamName>",
  "new_value": <number>
}

Functional unit:
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
