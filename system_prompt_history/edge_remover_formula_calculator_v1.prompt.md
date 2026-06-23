# edge_remover_formula_calculator_v1

Canonical runtime prompt:

- `llmSystemPromptBase + llmSystemPromptFormulaCalculatorAddon` in
  `lib/lca/newllm/llm_system_prompt.dart`

Tool condition:

- `DocumentParameterisation`
- `searchOpenLcaIndicators`
- `oneAtATimeSensitivity`
- `simplexLatticeDesign`
- `formulaCalculator`

Formula catalog version:

- `engineering_formula_catalog_v1`

Supported formulas:

- `abrams_compressive_strength`: `f_c = a / b^(w/c)`
- `electrical_resistivity`: `rho = R * A / L`
- `thermal_conduction_rate`: `q_dot = k * A * delta_T / L`
- `capital_recovery_factor`: `CRF = i(1+i)^n / ((1+i)^n - 1)`
- `learning_curve_cost`: `cost = C0 * (Q/Q0)^(ln(progress_ratio)/ln(2))`

Key methodological behavior:

- Simplex-lattice mixture requests use `simplexLatticeDesign`.
- Boundary/edge removal remains deterministic in the simplex-lattice tool.
- If formula calculations depend on lattice candidates, the model should call
  `simplexLatticeDesign` first and then call `formulaCalculator` once with a
  batched `calculations` list.
- The model should not call `simplexLatticeDesign` and `formulaCalculator` in
  the same assistant turn when calculator arguments depend on lattice
  candidates.
- Each formula calculation requires an `id`.
- For lattice-dependent calculations, the model should preserve candidate
  identity by using one calculation per `candidate_summaries` item, setting
  each calculation id to `candidate_summaries[].id`, and deriving
  lattice-dependent arguments from `candidate_summaries[].parameter_values`.
- After receiving formula results, the model should use returned numeric outputs
  directly and should not recalculate them or assign them to a different
  candidate.

UI setting:

- `Formula calculator condition` = on
