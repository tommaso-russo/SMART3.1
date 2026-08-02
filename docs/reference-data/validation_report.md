# Validation of legacy SMART3.1 reference inputs

The raw archive contains all ten expected objects and can be read successfully.
The standardized outputs preserve every usable source record while avoiding
silent imputations. Four issues require a methodological decision before the
new pipeline can run in strict mode.

## Blocking issues

### 1. Missing prices were encoded as zero

`prices` contains 779 positive observations for 15 species, 12 months and five
GSAs. The legacy `agg_price` table contains 84 additional rows (seven species ×
12 months) with `Price = 0`. These are placeholders, not observed market prices.
Using them in `add_WLV()` forces the estimated gross value of landings to zero
for `JAI`, `JRS`, `QUB`, `RJC`, `RJO`, `SDV` and `SYC`.

The revised `species_price_monthly_mean` contains only the 180 observed
species-month combinations. The seven unpriced species remain missing until an
explicit imputation or alternative price source is selected.

### 2. Conflicting depth ranges for `SYC`

`species_depth_ranges` contains two records for *Scyliorhinus canicula* (`SYC`):

| Minimum depth (m) | Maximum depth (m) |
|---:|---:|
| 10 | 200 |
| 100 | 400 |

Both records are retained and marked `requires_review_duplicate_species_code`.
One documented interval must be selected before the habitat filtering step;
otherwise `which(ranges$Species == "SYC")` returns two values and makes the
current filtering logic ambiguous.

### 3. Economic reference has no study-area coverage

`economic_reference` contains ten rows covering only `GSA09` and `GSA10`. The
current Strait of Sicily configuration specifies `GSA12`–`GSA16`. Consequently,
the legacy instruction

```r
EcoRef <- EcoRef |> filter(GSA %in% CS_gsas)
```

returns zero rows, so the regressions used to derive operating-cost,
investment and labour-cost factors cannot be fitted for this case study.

### 4. No LLS LPUE thresholds are defined

All 22 `LLS` cells in the original wide table are missing, whereas `OTB`
contains 22 configured upper quantiles (0.75 or 0.95). The long table preserves
all 44 species–gear combinations and flags the LLS rows with
`is_configured = FALSE`. It must be decided whether this means “do not cap LLS
LPUE” or whether thresholds are missing and must be supplied.

## Non-blocking findings

- One fleet-register row has no CFR and a LOA of 40.7 m. It is excluded because
  it cannot be joined reliably to vessel data. The remaining 26,140 vessel IDs
  are unique and LOA values range from 2.0 to 81.53 m.
- Price coverage is incomplete across GSAs. Each species is represented in all
  12 months, but a species-month can have observations from only two to five
  GSAs. The derived monthly price is currently an unweighted mean across the
  GSAs available for that species-month.
- The 12,771 FAO/ASFIS three-letter codes and taxonomic codes are unique. Missing
  vernacular names are expected and do not affect the scientific-name lookup.
- All 368 harbour names and coordinate pairs are unique and coordinates are
  globally valid. The table also includes Dakar, Antsiranana and Port Victoria;
  case-study filtering must therefore occur downstream rather than during
  reference-data preparation.
- Fuel-consumption parameters are positive and unique by gear. Their source,
  formula units and coefficient interpretation still require a formal citation.
- NISEA reference values are complete and unique by gear–indicator pair, but
  their temporal basis, monetary reference year and reuse permission are not
  encoded in the source file.

## Required decisions before strict loading

1. choose a documented missing-price strategy for the seven species;
2. resolve the `SYC` depth interval;
3. provide or justify transferable economic references for GSA12–GSA16;
4. confirm the intended handling of LLS LPUE outliers;
5. add source, version, unit and licence metadata for every externally derived
   table.
