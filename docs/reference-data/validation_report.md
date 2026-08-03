# Validation of legacy SMART3.1 reference inputs

The raw archive contains all ten expected objects and can be read successfully.
The standardized outputs preserve every usable source record, except for one
documented conflicting depth-range record that has been explicitly resolved.

No structural validation errors remain. Three warnings and one methodological
coverage limitation still require consideration before the corresponding data
are used in the SMART3.1 pipeline.

## Resolved issues

### 1. Zero prices are valid economic values

The legacy `agg_price` table contains 264 species–month combinations
(22 species × 12 months), including 84 records with `Price = 0` for `JAI`,
`JRS`, `QUB`, `RJC`, `RJO`, `SDV` and `SYC`.

These zero values indicate species with no commercial value. They are therefore
retained as valid observations and remain distinct from missing (`NA`) prices.
They are not excluded, replaced or imputed.

The standardized `species_price_monthly_mean` is constructed directly from
`agg_price` and consequently contains all 264 species–month combinations,
including the 84 valid zero values.

The separate `species_prices` table preserves the available GSA-specific price
observations.

### 2. Depth range selected for `SYC`

The source table contained two depth intervals for *Scyliorhinus canicula*
(`SYC`):

| Minimum depth (m) | Maximum depth (m) |
|---:|---:|
| 10 | 200 |
| 100 | 400 |

Following methodological review, the 100–400 m interval was selected as the
correct value. The alternative 10–200 m record is excluded during reference-data
preparation.

The preparation script verifies that the two expected legacy records are present
before applying this decision. This prevents the correction from being applied
silently if the source data change.

The resulting `species_depth_ranges` table contains one unique `SYC` record,
marked `validated_selected_depth_range`.

## Open methodological limitation

### Economic reference has no study-area coverage

`economic_reference` contains ten rows covering only `GSA09` and `GSA10`. The
current Strait of Sicily configuration specifies `GSA12`–`GSA16`. Consequently,

```r
EcoRef <- EcoRef |> filter(GSA %in% CS_gsas)

```

returns zero rows. The regressions used to derive operating-cost, investment and
labour-cost factors cannot be fitted for this case study until suitable reference
data or a documented transferability strategy is provided.

This is not a structural defect in the reference table, but it remains a
methodological limitation for the Strait of Sicily application.

## Validation warnings

### Incomplete GSA-specific price coverage

Not every species–month is represented in all five GSAs. Each species represented
in `species_prices` has observations for all 12 months, but spatial coverage
varies among species–month combinations.

The canonical monthly table is taken from `agg_price`; the incomplete coverage
warning applies specifically to analyses requiring GSA-specific prices.

### Missing vessel identifier

One fleet-register row has no CFR and a LOA of 40.7 m. It is excluded because it
cannot be joined reliably to vessel data. The remaining 26,140 vessel identifiers
are unique, and LOA values range from 2.0 to 81.53 m.

### No LLS LPUE thresholds are defined

All 22 `LLS` cells in the original wide table are missing, whereas `OTB` contains
22 configured upper quantiles (0.75 or 0.95).

The long table preserves all 44 species–gear combinations and marks the LLS rows
with `is_configured = FALSE`. It must be confirmed whether this means that LLS
LPUE should remain uncapped or whether thresholds still need to be supplied.

## Other findings

- The 12,771 FAO/ASFIS three-letter codes and taxonomic codes are unique.
  Missing vernacular names are expected and do not affect scientific-name
  lookup.
- All 368 harbour names and coordinate pairs are unique and globally valid.
  The table also includes Dakar, Antsiranana and Port Victoria; case-study
  filtering must therefore occur downstream.
- Fuel-consumption parameters are positive and unique by gear. Their source,
  formula units and coefficient interpretation still require a formal citation.
- NISEA reference values are complete and unique by gear–indicator pair, but
  their temporal basis, monetary reference year and reuse permission are not
  encoded in the source file.

## Decisions still required

1. determine how incomplete GSA-specific price coverage should be handled;
2. provide suitable economic references for `GSA12`–`GSA16` or document a
   transferable calibration strategy;
3. confirm whether LLS LPUE should remain uncapped or define justified
   thresholds;
4. add source, version, unit and licence metadata for every externally derived
   table.
