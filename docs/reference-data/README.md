# SMART3.1 reference data

This directory documents the small reference tables used by the SMART3.1
pipeline. The legacy workflow downloaded heterogeneous files and created many
objects in the global R environment. The revised workflow instead:

1. loads the legacy `.RData` file into a private environment;
2. validates source structure and key fields;
3. standardizes names, identifiers and types;
4. writes one explicit file per dataset;
5. records unresolved problems in `validation_issues.csv`.

Run the preparation script from the repository root:

```r
Rscript data-raw/prepare_reference_data.R \
  data-raw/SMART31_reference_inputs_raw.RData \
  data/reference \
  GSA12,GSA13,GSA14,GSA15,GSA16
```

Load the outputs without adding separate objects to the global environment:

```r
source("R/load_reference_data.R")
reference_data <- load_reference_data("data/reference", strict = TRUE)
```

`strict = TRUE` is intentional. It prevents the economic and habitat modules
from using unresolved reference values. Use `strict = FALSE` only to inspect
the standardized data while corrections are still being prepared.

The optional third argument is a comma-separated list of study GSAs. When it is
provided, the script verifies that `economic_reference` overlaps the case-study
area. Omitting it keeps the preparation workflow general but skips this one
case-specific coverage check.

## Principal changes from SMART2.0

| Legacy object | Standardized dataset | Main change |
|---|---|---|
| `prices` | `species_prices` | Integer month, normalized GSA, explicit EUR/kg field |
| `agg_price` | `species_price_monthly_mean` | Recomputed from observed prices; missing prices are not set to zero |
| `fao3` | `fao_species` | Stable `species_code` key and snake-case names |
| `fleet_register` | `fleet_register` | Character vessel identifier and explicit LOA unit |
| `ranges` | `species_depth_ranges` | Explicit metre units and conflict status |
| `Harbs` | `harbours.gpkg` | Point geometry in EPSG:4326 |
| `Species_LPUE_thrs` | `lpue_thresholds` | Long format with species–gear key |
| `sala_params` | `fuel_consumption_parameters` | Parameters named by their role in the formula |
| `EcoRef` | `economic_reference` | Fishing technique separated from gear and indicators expanded |
| `mNISEA` | `nisea_reference` | Stable gear–indicator key |

## Formula represented by the fuel parameters

The historical `IBM2eco()` function applies the parameters as:

```text
fuel_consumption = fuel_coefficient * loa_m^loa_exponent * total_activity_hours
```

The physical unit of the resulting consumption and the bibliographic source of
the coefficients must be stated before publication. The preparation script
therefore standardizes the parameter names but does not invent missing source
metadata.

## Publication decision

The generated files are usable locally for inspection, but they should not all
be committed to a public repository yet.

| Dataset | Recommended GitHub treatment |
|---|---|
| `species_prices` and its monthly mean | Hold until data source, currency year and reuse permission are documented |
| `fao_species` | Prefer a versioned download from the official FAO/ASFIS source rather than vendoring the full table |
| `fleet_register` | Keep local or reconstruct from the official fleet-register source; do not publish this copy yet |
| `species_depth_ranges` | Hold until the `SYC` conflict and scientific sources are resolved |
| `harbours` | Hold until source and reuse conditions are documented |
| `lpue_thresholds` | Suitable as methodological configuration after the missing LLS policy is confirmed |
| `fuel_consumption_parameters` | Suitable with complete citation, formula and units |
| `economic_reference` and `nisea_reference` | Do not publish without explicit permission from the data provider |

The repository can safely contain the preparation script, loader, dictionary,
validation report and ignore rules now. The data files should be added only
after the status above has been resolved.
