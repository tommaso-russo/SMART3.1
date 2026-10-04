# Configurable workflows

SMART3.1 keeps each workflow's numerical code directly in its Rmd chunks, with separate case configuration, reusable helpers and downstream exports. The public example is a template to review, not a management recommendation or a reproduction of a particular working-group exercise.

## Setup

Use R 4.3 or newer and run commands from the repository root. Pandoc is needed for HTML rendering (RStudio normally supplies it). Spatial packages may need GDAL, GEOS, PROJ and UDUNITS development libraries; the effort-repair solver requires GLPK. On Debian/Ubuntu these are generally provided by `libgdal-dev`, `libgeos-dev`, `libproj-dev`, `libudunits2-dev`, `libglpk-dev` and `pandoc`. Installation details depend on the operating system.

```bash
Rscript scripts/install_dependencies.R all
```

`config/dependencies.R` records direct package dependencies and minimum versions used by the source. It is not a tested lockfile for every platform. After validating a local installation, use `renv` to record that environment:

```r
source("config/dependencies.R")
renv::init(bare = TRUE)
renv::snapshot(packages = unique(unlist(smart31_dependencies)), prompt = FALSE)
```

Review the generated `renv.lock` before committing it; do not commit a local package library. The automated checks exercise synthetic fixtures without private inputs. They do not establish equivalence of complete case-study simulations after refactoring.

## Case configuration

Copy `config/case_study.example.R` to `config/case_study.R`. Local configurations are ignored by Git. Supply paths and scientific assumptions, then set `configured = TRUE`. The template deliberately stops until reviewed.

| Configuration | Purpose |
|---|---|
| `case_id` | Separate case output directory; use a new ID for a distinct experiment |
| `calendar` | Assessment anchor, baseline, contiguous future years and calibration years |
| `domain` | Historical years, species, gears, GSAs, member state and grid resolution |
| `paths` | Explicit local inputs, upstream results and economic audit |
| `survey` | MEDITS areas, years and workbook sheet |
| `step1_controls` | Reconstruction, physical and economic settings |
| `management$enforce_catch_quotas` | Apply ordinary species catch limits (`TRUE`) or display supplied limits only (`FALSE`) |
| `management$fmsy_stocks` | Exact assessment stock IDs to constrain; `character()` disables these constraints |
| `management$fuel_price_eur_l` | `NULL` retains the historical reference; a positive value overrides the simulation reference in memory |
| `scenarios` | Baseline and alternatives A/B: identifiers, closures, methods and compensation fractions |
| `controls$step2` | Sweep budget, replicates, seed, workers and other numerical controls |
| `reporting` | Authorization workbook layout, verified count, two effort groups, stock scope and provenance descriptions |

A stock is never selected for enforcement by its species abbreviation alone. A selected stock requires a complete, calibrated FMSY limit series and an unambiguous species–area crosswalk. A future period represents **one annual state**, repeated across its years, rather than a recursive projection. Annual limits for that period are checked using the existing limiting-year logic.

Keep the baseline, A and B roles. The supplied Annex-style adapter compares a no-CM alternative A with a with-CM alternative B; use those statuses for those roles. Both methods and balanced replicates are required to produce its between-method bounds. These bounds are descriptive minima and maxima, not confidence intervals.

The numerical search profile retains regularised spatial LPUE, no dynamic LPUE response, the historical-maximum crowding reference and the common operational reference. The configuration validator rejects unsupported combinations instead of silently changing the scientific procedure.

## Execution order

Execute each command in a fresh R process. This also accommodates Step 1's existing global-environment checkpoint interface. The files in `workflows/` contain the complete calculation chunks, including validation fixtures and conditionally evaluated age modules. Render them with the runner to preserve chunk order and evaluation options. They still require the shared configuration, helpers and local inputs in the project; copying an Rmd alone does not provide those dependencies.

```bash
Rscript scripts/prepare_survey_cache.R config/case_study.R
Rscript scripts/run_workflow.R step1 config/case_study.R
```

Record the exact emitted Step 1 RDS path in `paths$step1_bundle`. Then:

```bash
Rscript scripts/run_workflow.R step2 config/case_study.R
```

Record the exact overview path in `paths$step2_result`. Keep its complete directory, including per-run archives, references and `diagnostics_other_gvl`; the overview is not a standalone replacement for those files.

```bash
Rscript scripts/run_workflow.R economic_audit config/case_study.R
```

Record the exact audit RDS in `paths$economic_audit`, then:

```bash
Rscript scripts/run_workflow.R step3 config/case_study.R
```

The runner checks required inputs before knitting. It uses a single case file for all stages. Step 3 checks Step 1/Step 2 provenance, declared catch/FMSY policy, calendar and the calibrated limits actually enforced by Step 2. An old case-specific overview is not silently promoted to the new generic schema.

### Preparing FMSY constraints for a new case

The limits must come from a compatible assessment calibration, not from invented quota values. If no compatible limits exist, an initial explicitly unconstrained Step 2 run and Step 3 calibration can supply diagnostic limits. Review and pin that exported file and the stock-area constraint scope before starting a **new** constrained Step 2 run. Leave `fmsy_stocks` empty and the two FMSY input paths empty for the initial unconstrained run. It must never be described as FMSY-compliant solely because a limit was subsequently calculated.

`assessment_only_stocks` explicitly declares stocks that have assessment-level calibration but no raw Step 1 age-allocation crosswalk. `catch_only_stock_ids` explicitly declares stocks reported for catches without a full mortality assessment. Neither option implies that those stocks were constrained during a completed simulation. No stock-specific advice number is embedded in the report code.

## Outputs

Principal outputs are under `outputs/<case_id>/step1`, `step2`, `economic_audit` and `step3`. Step 2 adds a search-configuration subdirectory. Step 3 puts individual workbooks in `step3/tables`. Some Step 1 intermediate checkpoints and diagnostics retain their existing `checkpoints`, `Diagnostics`, `diagnostics` and `SetUps` locations; keep a separate project working copy for concurrently running cases.

The calibrated CSV retains the `SMART31_step3_calibrated_f_at_age_<timestamp>.csv` prefix. Use `F_total` for the assessment-scale fishing-mortality vector, subject to the biological/calibration audit. It includes the modelled fleet component and the fixed external component; it does not include natural mortality.

```bash
Rscript scripts/export_f.R path/to/calibrated_f.csv path/to/F_at_age.xlsx config/case_study.R 1
Rscript scripts/rebuild_gallery.R path/to/step2_overview.rds config/case_study.R
```

The F exporter selects one replicate and the configured primary calibration. It keeps the two methods separate, rejects duplicate or incomplete vectors, and repeats the declared annual vector across its period. It does not repair an unsuccessful Step 3 gate. Check `metadata$ready_for_downstream` in the Step 3 result before sending vectors to a population model.

## Adapter boundaries

This is a configurable implementation of the supplied workflow, not a universal fisheries-data importer. The current adapters retain FDI, MEDITS, numeric GSA codes (including GSA 11.1/11.2 pooling), the OTB effort/compensation convention, a baseline plus two alternatives, and an Annex-style effort report with two authorization groups and four LOA bands (<12, 12–18, 18–24, ≥24 m). Another data convention or report structure requires an explicit adapter change and validation.

For compatibility with the supplied controlled tables, some machine-readable columns retain names such as `anchor_2025_t`, `F_ITA_anchor_2025`, `single_stock_advice_catch_t_2027` and `official_2027_target`. In this workflow their roles are **configured anchor**, **modelled fleet component**, and **configured scenario year**, respectively. The actual `YEAR`/`Year` values, representative periods and calibration identifiers must match the case calendar. Historical suffixes do not override it. Human-readable table headings use the configured years. Do not recycle an old numerical input merely by renaming its year.

## Checks and publication

```bash
Rscript scripts/install_dependencies.R tests
Rscript scripts/check_workflows.R
```

Checks cover configuration, ordered report blocks, ordinary/FMSY policy separation, spatial stock accounting, monitor isolation, physical and LP repair invariants, partial-F inversion and annual vector export. No fleet simulation is launched by the checks.

Commit source, templates and documentation only. `.gitignore` excludes local configurations, new input files, raw data, bundles, generated reports, checkpoints and credentials. Previously tracked reference assets remain part of the repository; the refactor neither replaces them nor adds a case-study dataset. Always inspect `git diff --cached --stat` and the staged filenames before publishing.
