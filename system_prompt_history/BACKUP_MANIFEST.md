# Backup Manifest

Date: 2026-06-22

Canonical source files:

- `lib/lca/newllm/llm_system_prompt.dart`
- `lib/lca/newllm/llm_scenario_controller.dart`
- `lib/lca/lca_functions.dart`

Prompt variants:

- `edge_remover_no_calculator`
- `edge_remover_formula_calculator_v1`

UI control:

- `Formula calculator condition`

Clean-run rule:

- Run each experiment condition with the UI switch set before generation.
- Do not change the switch mid-run.
- The active condition is recorded in diagnostics as `system_prompt_variant`
  and `formula_calculator_enabled`.

