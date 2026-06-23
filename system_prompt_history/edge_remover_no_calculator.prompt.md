# edge_remover_no_calculator

Canonical runtime prompt:

- `llmSystemPromptBase` in `lib/lca/newllm/llm_system_prompt.dart`

Tool condition:

- `DocumentParameterisation`
- `searchOpenLcaIndicators`
- `oneAtATimeSensitivity`
- `simplexLatticeDesign`

Excluded tool:

- `formulaCalculator`

Key methodological behavior:

- Simplex-lattice mixture requests use `simplexLatticeDesign`.
- Boundary/edge removal is deterministic when the prompt requests removing
  edges, excluding boundary points, avoiding zero components, or keeping every
  mixture component present.
- Formula calculations must be performed by the LLM without the deterministic
  formula registry.

UI setting:

- `Formula calculator condition` = off

