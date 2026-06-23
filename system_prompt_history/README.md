# System Prompt History

This folder records the two prompt/tool conditions used for the simplex-lattice
formula-calculation experiment.

The runtime implementation is in:

- `lib/lca/newllm/llm_system_prompt.dart`
- `lib/lca/newllm/llm_scenario_controller.dart`
- `lib/lca/lca_functions.dart`

## Variants

1. `edge_remover_no_calculator`
   - UI switch: Formula calculator condition = off
   - Tool list excludes `formulaCalculator`
   - Simplex lattice still supports `removeEdges=true`

2. `edge_remover_formula_calculator_v1`
   - UI switch: Formula calculator condition = on
   - Tool list includes `formulaCalculator`
   - The controller permits one additional tool round after
     `simplexLatticeDesign`, limited to `formulaCalculator`

## Reviewer Rerun Instructions

Open the LLM Scenario Generator page and use the `Formula calculator condition`
switch before pressing `Run models`.

- Off: no-calculator condition.
- On: formula-calculator condition.

The selected variant is recorded in generation diagnostics as:

- `system_prompt_variant`
- `formula_calculator_enabled`
- `request.tools_offered`

