# Local input contracts

Paths are specified in `config/case_study.R`. No case-study input is supplied by this refactor. The existing `data/reference` loader and [reference dictionary](reference-data/data_dictionary.csv) define the baseline reference schemas. Reference sets must be appropriate for the selected case, even if the repository contains a previously prepared reference set.

## Step 1

- Reference directory: the objects required by `R/load_reference_data.R`, including fleet register, harbours, depth ranges, gear/economic mappings and fuel-consumption parameters.
- Area shapefile and bathymetry RDS: spatial resources consumed by the existing grid/accessibility functions, in compatible coordinates and depth conventions.
- Effort and landings: one RDS per configured year, consumed by `R/prepareEffort.R` and `R/getLandings.R`; preserve their source field names, units and vessel identifiers.
- FDI tables A, G, H and I: RDS data frames using the existing FDI field conventions. Step 1 checks the fields it consumes.
- Fuel CSV: `YEAR,fuel_cost`, one positive EUR/l value per historical year. Step 2's fuel override does not edit this file or the Step 1 bundle.
- MEDITS TA, TB, TC: workbooks with country, area, vessel, year, haul number, codend closure and survey identifiers, plus the table-specific fields enumerated in `scripts/prepare_survey_cache.R`. The cache builder normalizes headers and selects the configured country/area/year scope, preserving all taxa for the age module to match. Cache source MD5, dimensions and scope are checked by Step 1.
- Stock parameters: `species,gsa,linf,k,t0,a,b,age_min,age_plus,length_type,length_unit,weight_unit`; valid positive parameters, length in mm or cm and weight in g. These are biological inputs to review independently.

Optional Step 1 commercial biomass-at-age proportions are read from `paths$commercial_age_baseline` (`Species,Age,report_baseline_proportion`, summing to one by species). An empty path explicitly retains the existing MEDITS-based fallback. Taxon mappings are configured in `survey$species_crosswalk`; economic gear/length mappings and explicit segment fallbacks are configured in `economics`. No empirical commercial age distribution or case-specific segment fallback is embedded in the numerical code.

## Step 2

| Input | Required fields / role |
|---|---|
| Step 1 bundle | Exact validated RDS; metadata and manifests checked at loading |
| Effort quotas | `YEAR,SCENARIO_ID,GEAR,LENGTH_CLASS,MIN_LOA_M,MAX_LOA_M,EFF1_MED2_DAYS,EFF2_MED2_DAYS,EFFORT_QUOTA_DAYS,SOURCE_STATUS` |
| Catch quotas | `Species,YEAR,quota_kg`; may be displayed without enforcement; empty path allowed only when ordinary catch constraints are disabled |
| Cessation list | Optional CSV containing CFR identifiers; empty path means no supplied cessations |
| FMSY limits | `Species,YEAR,quota_kg,assessment_stock,Fmsy,F_external_floor,anchor_2025_t,maximum_future_to_anchor_ratio,age_F_ITA_anchor,age_M_reference,age_F_external,calibration,source` |
| Constraint scope | `Species,GSA_code,assessment_stock`, one unambiguous stock for each species/parent-area pair |

Effort bounds are inclusive in the inherited importer. Adjacent bands must not overlap (for example, an upper bound of 17.99 before a lower bound of 18). The two component day columns must sum to the total. Supply each configured LOA class for every required scenario/year combination. Species quota keys and `STOCK::<assessment_stock>` keys remain distinct so two stocks of one species are not pooled accidentally.

FMSY age vectors use semicolon-separated finite non-negative numbers with matching lengths. They must reproduce the external-F floor, anchor F and inverse FMSY catch bound. Future-year rows represent the same annual constraint; inconsistent repeated rows stop loading. All selected stock IDs need complete coverage. Monitor/reference rows may include more stocks than the enforcement subset.

## Economic audit and Step 3

The economic workbook uses year, GSA, fishing technique, vessel length class, variable name and value, with the existing FDI economic indicator names. It must cover the case's mapped Gear/VL segments and the configured reference years. The audit reconstructs the completed run using frozen physical outputs; it does not rerun optimization.

Step 3 reads the paths listed under `paths$step3`:

- stock-area crosswalk, stock-age parameters and commercial age baseline;
- stock reference points and provenance;
- assessment stock crosswalk, history, anchor and total-catch history;
- FDI catch workbook for the matched landing anchor;
- an independent calibration check with `assessment_stock,expected_anchor_2025_t,expected_q_ref`;
- a documented Annex F-target input (diagnostic only), including `EMU,assessment_stock,target_type,target_F_value,official_2027_target,source,note`;
- authorization workbook and optional independently verified single-stock advice.

The authorization sheet contains `row_no,CFR,authorized_ARA_ARS,source_year,pdf_page,source_decree,use_in_step3` in that order, after the configured number of skipped rows. `authorized_ARA_ARS` is the compatibility field selecting the first configured effort group. Set the expected authorized vessel count from the verified source. Identifier normalization accepts numeric CFRs or the configured prefix and rejects foreign prefixes. The authorization year is the configured baseline year.

The executable `read_contract_csv()` calls in `workflows/step3.Rmd` declare complete field lists and the validators enforce uniqueness, age coverage, physical ranges and provenance. Keep missing values explicit: a missing official advice value is not a zero or an inferred quota. The optional advice template is exported by Step 3; only verified advice with matching year, scope, units and source is published.

Compatibility suffixes in fields are explained in [workflows.md](workflows.md#adapter-boundaries). Preserve the schema while supplying numerical values for the configured calendar.
