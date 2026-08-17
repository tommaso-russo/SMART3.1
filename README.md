# SMART3.1

### Spatially explicit, age-aware and bio-economic modelling for fisheries management

[![Language](https://img.shields.io/badge/language-R-276DC3.svg)](https://www.r-project.org/)
[![Status](https://img.shields.io/badge/status-active%20development-f39c12.svg)](#development-status)
[![License: CC0-1.0](https://img.shields.io/badge/license-CC0--1.0-lightgrey.svg)](LICENSE)

**SMART3.1** is a modular research workflow for reconstructing spatial fisheries dynamics and evaluating management strategies. It integrates vessel activity, landings, biological surveys, environmental information and fleet economics within a coherent spatial and temporal framework.

The central idea is simple: fishing pressure, resource distribution and fleet behaviour interact in space. Management measures should therefore be assessed not only by how much effort they remove, but also by **where and when effort is displaced**, which population components are affected, and how fleets respond economically.

<p align="center">
  <img src="docs/images/smart31_workflow_overview.jpg" width="900" alt="Conceptual overview of the SMART3.1 workflow">
</p>

> SMART3.1 is under active development. The current public repository provides the validated reference-data foundation; the complete modelling workflow is being migrated incrementally from the research implementation into documented, testable and reusable modules.

## Scientific scope

SMART was originally developed as a spatially explicit bio-economic model for demersal trawl fisheries. SMART3.1 extends that scientific architecture into a more general and auditable workflow designed to support multi-species and multi-gear case studies.

The framework links five interacting dimensions:

1. **Fishing activity** - vessel movements, fishing time, gear, fleet structure and access to fishing grounds.
2. **Production** - calibrated landings, spatial LPUE and the origin-to-harbour flow of catches.
3. **Population structure** - species distributions, habitat constraints and depth-dependent catch composition by age.
4. **Fleet economics** - revenues, steaming requirements, fuel consumption, operating costs and profitability.
5. **Management response** - effort reallocation and biological-economic feedback under alternative spatial, temporal and capacity measures.

SMART3.1 is intended as a **decision-support and Management Strategy Evaluation framework**, not as a substitute for stock assessment. Its role is to connect assessed or reconstructed biological states with the spatial behaviour of fleets and the consequences of management choices.

## End-to-end workflow

```mermaid
flowchart TD
    A["VMS or AIS activity"] --> F["Validation and harmonisation"]
    B["Logbooks and landings"] --> F
    C["Surveys, environment and economics"] --> F
    F --> G["Spatially explicit baseline"]
    G --> H["Coupled biological and fleet state"]
    H --> I["Management scenarios"]
    I --> J["Biological, spatial and economic outcomes"]
    J -->|"behavioural and population feedback"| H
```

### 1. Configure the case study

A case study defines years, species, gears, geographical subareas, spatial resolution and model settings. Reference tables are loaded into a named object rather than injected into the global environment. Keys, units, ranges and unresolved validation issues are checked before analytical processing begins.

### 2. Reconstruct fleet activity and accessibility

Vessel positions are classified and interpolated into fishing activity, then aggregated over a common spatial grid. Grid cells are assigned to biological management areas, and navigational distances between harbours and fishing grounds are calculated over water rather than as straight lines across land.

<p align="center">
  <img src="docs/images/effort_accessibility.jpg" width="760" alt="Fishing effort and water-constrained accessibility in SMART3.1">
</p>

### 3. Estimate spatial LPUE and conserve catch mass

Within each year-month-area-species-gear stratum, non-negative least squares estimates a vector of spatial catch rates:

$$
\widehat{\boldsymbol{\lambda}}
=\arg\min_{\boldsymbol{\lambda}\geq 0}
\left\|\mathbf{A}\boldsymbol{\lambda}-\mathbf{c}\right\|_2^2,
$$

where $\mathbf{A}$ represents gridded vessel effort and $\mathbf{c}$ contains calibrated vessel catches. Estimated rates provide relative spatial weights. The final allocation is normalised within each stratum so that

$$
\sum_i E_{k,i}\widehat{\lambda}_{k,i}=C_k,
$$

where $C_k$ is the calibrated catch target. This design guarantees non-negative production and explicit conservation of landings mass.

Fallbacks are hierarchical, restricted and labelled. When declared catch has no target-year VMS support, SMART3.1 preserves it as an explicit non-VMS biological removal rather than inventing vessel effort, trips or economic costs.

<p align="center">
  <img src="docs/images/lpue_mass_balance.jpg" width="760" alt="Mass-conserving spatial LPUE reconstruction">
</p>

### 4. Reconstruct catch composition by age and habitat

Survey length-frequency and biomass observations are combined with stock-specific growth and length-weight parameters. A depth-dependent model modifies the marginal age composition for each species and spatial cell:

$$
p_{a,i}=
\frac{\pi_a r_a(d_i)}
{\sum_{a^\prime}\pi_{a^\prime}r_{a^\prime}(d_i)},
\qquad \sum_a p_{a,i}=1,
$$

where $\pi_a$ is the baseline contribution of age $a$ and $r_a(d_i)$ is its relative response at the depth of cell $i$. This allows spatial measures to affect juveniles, adults and spawning biomass differently.

<p align="center">
  <img src="docs/images/age_depth_structure.jpg" width="760" alt="Depth-dependent age structure in SMART3.1">
</p>

### 5. Assemble the vessel-level bio-economic state

The activity-level model connects vessels, months, gears, fishing grounds, harbours, effort, production and prices. Economic calculations are performed once per activity before any age expansion, preventing effort and costs from being multiplied by the number of species or age classes.

Core indicators include:

$$
GVL=\sum_s W_s P_s,
\qquad
GVA=GVL-EC-OC,
\qquad
GP=GVA-LC,
$$

where $W_s$ and $P_s$ are landed weight and price, while $EC$, $OC$ and $LC$ are energy, operating and labour costs.

### 6. Simulate management strategies

Alternative scenarios can modify fishing capacity, total effort, fishing seasons, spatial access or combinations of these measures. Fleet activity is reallocated subject to scenario constraints, after which the biological and economic states are updated and compared with the verified baseline.

<p align="center">
  <img src="docs/images/bioeconomic_mse_loop.jpg" width="760" alt="Bio-economic Management Strategy Evaluation loop">
</p>

## Principal objects and their relationships

The diagram below describes the intended object architecture of the complete SMART3.1 workflow. Not all modules shown here are yet available on the public `main` branch.

```mermaid
flowchart TD
    CFG["run_configuration"] --> REF["reference_data"]
    CFG --> GRID["grid_sf and grid_gsa_lookup"]

    VMS["effort_sf_gridded_list"] --> EFF["effort_gridded_agg_list"]
    LOG["landings_list"] --> CAL["calibrated_landings_targets"]

    REF --> LPUE["df_lpue_rates_mass_conserving"]
    GRID --> LPUE
    EFF --> LPUE
    CAL --> LPUE

    LPUE --> PROD["df_prod"]
    PROD --> AGE["age_proportions"]

    EFF --> ACT["IBM_effort"]
    ACT --> IBM["IBM"]
    LPUE --> IBM

    IBM --> ECO["IBM.eco and IBM.eco.annual"]
    PROD --> OUT["simulation_bundle"]
    AGE --> OUT
    ECO --> OUT
    NVM["non_vms_landings_ledger"] --> OUT
```

| Object | Role | Principal key or resolution |
|---|---|---|
| `run_configuration` | Reproducible case-study selections and settings | Run level |
| `reference_data` | Validated prices, fleet, species, depth, harbour and economic tables | Named list of explicit datasets |
| `grid_sf` | Spatial grid and case-study geometry | `id_grid` |
| `grid_gsa_lookup` | Exact association between grid cells and biological areas | `id_grid × GSA_code` |
| `effort_sf_gridded_list` | Vessel-level gridded activity | Vessel × year × month × gear × cell |
| `effort_gridded_agg_list` | Analytical effort surface | Year × month × gear × cell |
| `landings_list` | Calibrated vessel-level landings | Vessel × year × month × species × gear × area |
| `df_lpue_rates_mass_conserving` | Sparse, non-negative and mass-conserving LPUE rates | Year × month × area × species × gear × cell |
| `df_prod` | Spatial production, including all biologically allocated catch | Effort × LPUE at cell level |
| `age_proportions` | Depth-dependent catch proportions by age | Area × species × cell × age |
| `IBM_effort` | Activity-level fleet state used for costs and behaviour | Unique fishing activity |
| `IBM` | Species production linked to observed fleet activity | Activity × production month × species |
| `non_vms_landings_ledger` | Declared catch without target-year VMS support | Vessel × catch stratum; biological removal only |
| `IBM.eco.annual` | Annual vessel-economic indicators | Vessel × year × gear × harbour |
| `simulation_bundle` | Versioned and validated hand-off to scenario simulation | Run level, with manifest and checksums |

## Design principles

- **Spatially explicit by construction** - grid cell and biological area remain part of analytical keys.
- **Mass conserving** - every calibrated catch target is reconciled against spatial production.
- **Non-negative** - LPUE and production cannot become negative through model fitting.
- **Age aware** - catch composition responds to habitat and depth rather than relying only on pooled age vectors.
- **Economically coherent** - effort, trips, fuel and costs are calculated once at the appropriate activity scale.
- **Transparent fallback hierarchy** - weak or missing support is classified, diagnosed and never silently imputed.
- **Fail-fast validation** - invalid keys, units, duplicates, missing coverage and failed reconciliation stop the workflow.
- **Auditable outputs** - versions, manifests, checksums and compact diagnostic tables accompany simulation inputs.
- **Case-study portability** - study areas, species, gears and years are supplied through configuration rather than embedded in analytical functions.

## Development status

SMART3.1 is being refactored from a complete research workflow into a documented and reusable codebase. The current public release focuses on **reference-data preparation and validation**:

- legacy multi-object archives are loaded into a private environment;
- names, identifiers, units and keys are standardised;
- one explicit file is written for each reference dataset;
- unresolved issues are recorded in a machine-readable validation table;
- strict loading prevents downstream models from using unresolved errors.

The spatial LPUE, production, age-structure, IBM, economic and simulation-export modules described above are the target architecture and are being migrated progressively.

## Repository contents

- [`R/load_reference_data.R`](R/load_reference_data.R) - strict loader for standardised reference datasets.
- [`data-raw/prepare_reference_data.R`](data-raw/prepare_reference_data.R) - reproducible conversion and validation of legacy inputs.
- [`docs/reference-data/README.md`](docs/reference-data/README.md) - preparation workflow and publication decisions.
- [`docs/reference-data/data_dictionary.csv`](docs/reference-data/data_dictionary.csv) - field definitions, units and key roles.
- [`docs/reference-data/validation_report.md`](docs/reference-data/validation_report.md) - resolved issues, warnings and methodological limitations.

Raw fleet, vessel, price and provider-restricted economic data are not distributed automatically. Users are responsible for access rights, confidentiality, licences and case-study-specific validation.

## Current quick start: reference data

From the repository root:

```bash
Rscript data-raw/prepare_reference_data.R \
  data-raw/SMART31_reference_inputs_raw.RData \
  data/reference \
  GSA12,GSA13,GSA14,GSA15,GSA16
```

Then load the validated outputs without populating the global environment:

```r
source("R/load_reference_data.R")

reference_data <- load_reference_data(
  data_dir = "data/reference",
  strict = TRUE
)
```

`strict = TRUE` is deliberate: unresolved validation errors block downstream analysis. Use `strict = FALSE` only for diagnostic inspection while source problems are being resolved.

## Reproducibility and data governance

SMART3.1 separates source data, standardised analytical inputs, diagnostics and model outputs. A complete case study should record:

- source, version, licence and units for every external dataset;
- the exact configuration and spatial reference system;
- object and model version identifiers;
- mass-balance and economic reconciliation results;
- an output manifest and file checksums;
- any catch retained as a non-VMS biological removal;
- all justified transfers, fallbacks or exclusions.

This repository does not confer permission to redistribute third-party or confidential fisheries data. The repository licence applies to material owned by the repository authors, not automatically to external inputs.

## Scientific lineage

SMART3.1 builds on four complementary developments:

1. the original spatially explicit SMART bio-economic framework;
2. the integration of landings and VMS data to reconstruct fishing-ground production and harbour flows;
3. the multi-species bio-economic simulation of alternative management measures;
4. the modular `smartR` implementation for scenario simulation and decision support.

### References

- Russo, T. et al. (2014). **SMART: A Spatially Explicit Bio-Economic Model for Assessing and Managing Demersal Fisheries, with an Application to Italian Trawlers in the Strait of Sicily.** *PLoS ONE*, 9(1), e86222. [https://doi.org/10.1371/journal.pone.0086222](https://doi.org/10.1371/journal.pone.0086222)
- Russo, T. et al. (2018). **A model combining landings and VMS data to estimate landings by fishing ground and harbor.** *Fisheries Research*, 199, 218-230. [https://doi.org/10.1016/j.fishres.2017.11.002](https://doi.org/10.1016/j.fishres.2017.11.002)
- Russo, T. et al. (2019). **Simulating the Effects of Alternative Management Measures of Trawl Fisheries in the Central Mediterranean Sea: Application of a Multi-Species Bio-economic Modeling Approach.** *Frontiers in Marine Science*, 6, 542. [https://doi.org/10.3389/fmars.2019.00542](https://doi.org/10.3389/fmars.2019.00542)
- D'Andrea, L. et al. (2020). **smartR: An R package for spatial modelling of fisheries and scenario simulation of management strategies.** *Methods in Ecology and Evolution*. [https://doi.org/10.1111/2041-210X.13394](https://doi.org/10.1111/2041-210X.13394)

## Citation

Until a dedicated SMART3.1 software release and `CITATION.cff` are published, please cite the methodological paper or papers corresponding to the modules used in your analysis. When reporting a SMART3.1 application, also record the repository commit, case-study configuration and analytical-output version.

## Contributing

SMART3.1 is research software under active development. Contributions are welcome through [GitHub issues](https://github.com/tommaso-russo/SMART3.1/issues), particularly for:

- reproducible case-study configurations;
- tests and validation datasets that can be shared legally;
- documentation of units and data provenance;
- modularisation of validated workflow components;
- performance improvements that preserve numerical and mass-balance safeguards.

## Licence

Repository-owned code and documentation are released under [CC0 1.0 Universal](LICENSE), unless otherwise stated. External data, scientific publications and provider-derived parameters remain subject to their original terms and permissions.

---

The conceptual illustrations in this README were prepared specifically for SMART3.1. They are explanatory graphics rather than maps, measurements or quantitative model outputs.
