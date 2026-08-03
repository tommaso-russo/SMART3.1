# Prepare the SMART3.1 reference datasets from the legacy multi-object RData file.
#
# Usage:
#   Rscript data-raw/prepare_reference_data.R \
#     path/to/SMART31_reference_inputs_raw.RData \
#     data/reference \
#     GSA12,GSA13,GSA14,GSA15,GSA16
#
# The script deliberately loads the legacy file into a private environment. It
# never injects its objects into the global workspace. Each standardized table
# is then saved separately, which makes dependencies explicit and prevents an
# old .RData file from silently overwriting objects already in memory.

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
raw_file <- if (length(args) >= 1L) args[[1L]] else "data-raw/SMART31_reference_inputs_raw.RData"
output_dir <- if (length(args) >= 2L) args[[2L]] else "data/reference"
case_study_gsas <- if (length(args) >= 3L && nzchar(args[[3L]])) {
  strsplit(args[[3L]], ",", fixed = TRUE)[[1L]]
} else {
  character()
}

if (!file.exists(raw_file)) {
  stop("Raw reference-data file not found: ", raw_file, call. = FALSE)
}

if (!requireNamespace("sf", quietly = TRUE)) {
  stop("Package 'sf' is required to create harbours.gpkg.", call. = FALSE)
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

required_objects <- c(
  "prices", "agg_price", "fao3", "fleet_register", "ranges", "Harbs",
  "Species_LPUE_thrs", "sala_params", "EcoRef", "mNISEA"
)

raw <- new.env(parent = emptyenv())
loaded_objects <- load(raw_file, envir = raw)
missing_objects <- setdiff(required_objects, loaded_objects)

if (length(missing_objects) > 0L) {
  stop(
    "The raw file is missing required objects: ",
    paste(missing_objects, collapse = ", "),
    call. = FALSE
  )
}

as_table <- function(name) {
  x <- get(name, envir = raw, inherits = FALSE)
  if (!is.data.frame(x)) {
    stop("Object '", name, "' is not a data frame.", call. = FALSE)
  }
  as.data.frame(x, stringsAsFactors = FALSE)
}

assert_columns <- function(x, required, dataset) {
  missing <- setdiff(required, names(x))
  if (length(missing) > 0L) {
    stop(
      "Dataset '", dataset, "' is missing columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
}

duplicate_key <- function(x, key) {
  duplicated(x[key]) | duplicated(x[key], fromLast = TRUE)
}

assert_unique <- function(x, key, dataset) {
  bad <- duplicate_key(x, key)
  if (any(bad)) {
    stop(
      "Dataset '", dataset, "' has a non-unique key: ",
      paste(key, collapse = " + "),
      call. = FALSE
    )
  }
}

clean_character <- function(x, upper = FALSE) {
  x <- trimws(as.character(x))
  x[x == ""] <- NA_character_
  if (upper) x <- toupper(x)
  x
}

normalize_gsa <- function(x) {
  x <- clean_character(x, upper = TRUE)
  number <- sub("^GSA", "", x)
  valid <- !is.na(number) & grepl("^[0-9]+$", number)
  out <- rep(NA_character_, length(number))
  out[valid] <- sprintf("GSA%02d", as.integer(number[valid]))
  out
}

issues <- data.frame(
  severity = character(),
  dataset = character(),
  check = character(),
  details = character(),
  action_required = character(),
  stringsAsFactors = FALSE
)

add_issue <- function(severity, dataset, check, details, action_required) {
  issues <<- rbind(
    issues,
    data.frame(
      severity = severity,
      dataset = dataset,
      check = check,
      details = details,
      action_required = action_required,
      stringsAsFactors = FALSE
    )
  )
}


normalize_month <- function(x) {
  x_chr <- trimws(as.character(x))
  month_num <- suppressWarnings(as.integer(x_chr))

  unresolved <- is.na(month_num)

  if (any(unresolved)) {
    month_key <- tolower(x_chr[unresolved])

    month_from_name <- match(month_key, tolower(month.name))
    month_from_abbr <- match(month_key, tolower(month.abb))

    month_num[unresolved] <- ifelse(
      !is.na(month_from_name),
      month_from_name,
      month_from_abbr
    )
  }

  if (anyNA(month_num) || any(month_num < 1L | month_num > 12L)) {
    invalid_values <- unique(x_chr[
      is.na(month_num) | month_num < 1L | month_num > 12L
    ])

    stop(
      paste0(
        "Invalid month values: ",
        paste(invalid_values, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  month_num
}

# -----------------------------------------------------------------------------
# Species prices
# -----------------------------------------------------------------------------

prices_raw <- as_table("prices")
assert_columns(prices_raw, c("MONTH", "Species", "GSA", "Price"), "prices")

month_number <- match(clean_character(prices_raw$MONTH), month.name)
if (anyNA(month_number)) {
  stop("Dataset 'prices' contains invalid English month names.", call. = FALSE)
}

species_prices <- data.frame(
  month = as.integer(month_number),
  month_name = month.name[month_number],
  species_code = clean_character(prices_raw$Species, upper = TRUE),
  gsa = normalize_gsa(prices_raw$GSA),
  price_eur_per_kg = as.numeric(prices_raw$Price),
  stringsAsFactors = FALSE
)

if (anyNA(species_prices[c("species_code", "gsa", "price_eur_per_kg")])) {
  stop("Dataset 'prices' contains missing or invalid required values.", call. = FALSE)
}
# Zero is a valid economic value for species with no commercial value.
# Only negative or non-finite prices are invalid.
if (any(!is.finite(species_prices$price_eur_per_kg)) ||
    any(species_prices$price_eur_per_kg < 0)) {
  stop(
    "Dataset 'prices' contains negative or non-finite prices.",
    call. = FALSE
  )
}

assert_unique(
  species_prices,
  c("month", "species_code", "gsa"),
  "species_prices"
)
species_prices <- species_prices[
  order(
    species_prices$species_code,
    species_prices$month,
    species_prices$gsa
  ),
]
row.names(species_prices) <- NULL

# The source table agg_price provides the canonical monthly price by species.
# Price = 0 is retained as an observed value indicating no commercial value;
# it is not interpreted as missing and is not imputed.
agg_price_raw <- as_table("agg_price")
assert_columns(
  agg_price_raw,
  c("Species", "MONTH", "Price"),
  "agg_price"
)




agg_month <- normalize_month(agg_price_raw$MONTH)

species_price_monthly_mean <- data.frame(
  species_code = clean_character(
    agg_price_raw$Species,
    upper = TRUE
  ),
  month = agg_month,
  month_name = month.name[agg_month],
  price_eur_per_kg = as.numeric(agg_price_raw$Price),
  stringsAsFactors = FALSE
)

if (anyNA(
  species_price_monthly_mean[
    c("species_code", "month", "price_eur_per_kg")
  ]
)) {
  stop(
    "Dataset 'agg_price' contains missing or invalid required values.",
    call. = FALSE
  )
}

if (any(!is.finite(
  species_price_monthly_mean$price_eur_per_kg
)) ||
any(species_price_monthly_mean$price_eur_per_kg < 0)) {
  stop(
    "Dataset 'agg_price' contains negative or non-finite prices.",
    call. = FALSE
  )
}

assert_unique(
  species_price_monthly_mean,
  c("species_code", "month"),
  "species_price_monthly_mean"
)

species_price_monthly_mean <- species_price_monthly_mean[
  order(
    species_price_monthly_mean$species_code,
    species_price_monthly_mean$month
  ),
]
row.names(species_price_monthly_mean) <- NULL

price_coverage <- aggregate(
  gsa ~ species_code + month,
  data = species_prices,
  FUN = length
)

if (any(
  price_coverage$gsa < length(unique(species_prices$gsa))
)) {
  add_issue(
    "warning",
    "species_prices",
    "incomplete_gsa_coverage",
    paste(
      "Not every species-month is represented in all five GSAs.",
      "The GSA-specific price table therefore has incomplete",
      "spatial coverage."
    ),
    paste(
      "Account for incomplete coverage in analyses requiring",
      "GSA-specific prices."
    )
  )
}

# -----------------------------------------------------------------------------
# FAO/ASFIS species lookup
# -----------------------------------------------------------------------------

fao_raw <- as_table("fao3")
assert_columns(
  fao_raw,
  c(
    "ISSCAAP", "TAXOCODE", "3A_CODE", "Scientific_name", "English_name",
    "Author", "Family", "Order", "Stats_data"
  ),
  "fao3"
)

fao_species <- data.frame(
  isscaap_group = clean_character(fao_raw$ISSCAAP),
  taxonomic_code = clean_character(fao_raw$TAXOCODE),
  species_code = clean_character(fao_raw[["3A_CODE"]], upper = TRUE),
  scientific_name = clean_character(fao_raw$Scientific_name),
  english_name = clean_character(fao_raw$English_name),
  author = clean_character(fao_raw$Author),
  family = clean_character(fao_raw$Family),
  order = clean_character(fao_raw$Order),
  statistics_data = clean_character(fao_raw$Stats_data),
  stringsAsFactors = FALSE
)
assert_unique(fao_species, "species_code", "fao_species")
fao_species <- fao_species[order(fao_species$species_code), ]
row.names(fao_species) <- NULL

# -----------------------------------------------------------------------------
# Fleet register
# -----------------------------------------------------------------------------

fleet_raw <- as_table("fleet_register")
assert_columns(fleet_raw, c("CFR", "loa"), "fleet_register")

fleet_register <- data.frame(
  vessel_id = clean_character(fleet_raw$CFR),
  loa_m = as.numeric(fleet_raw$loa),
  stringsAsFactors = FALSE
)

missing_vessel_id <- is.na(fleet_register$vessel_id)
if (any(missing_vessel_id)) {
  add_issue(
    "warning",
    "fleet_register",
    "missing_vessel_id",
    paste0(sum(missing_vessel_id), " row has no CFR/vessel identifier and was removed."),
    "Verify the source row if the vessel with LOA 40.7 m must be retained."
  )
  fleet_register <- fleet_register[!missing_vessel_id, ]
}
if (anyNA(fleet_register$loa_m) || any(fleet_register$loa_m <= 0)) {
  stop("Dataset 'fleet_register' contains missing or non-positive LOA values.", call. = FALSE)
}
assert_unique(fleet_register, "vessel_id", "fleet_register")
fleet_register <- fleet_register[order(fleet_register$vessel_id), ]
row.names(fleet_register) <- NULL

# -----------------------------------------------------------------------------
# Species depth ranges
# -----------------------------------------------------------------------------

ranges_raw <- as_table("ranges")
assert_columns(ranges_raw, c("Name", "Species", "minD", "maxD"), "ranges")

species_depth_ranges <- data.frame(
  species_code = clean_character(ranges_raw$Species, upper = TRUE),
  scientific_name = clean_character(ranges_raw$Name),
  min_depth_m = as.numeric(ranges_raw$minD),
  max_depth_m = as.numeric(ranges_raw$maxD),
  stringsAsFactors = FALSE
)

if (anyNA(species_depth_ranges) ||
    any(species_depth_ranges$min_depth_m < 0) ||
    any(species_depth_ranges$max_depth_m < species_depth_ranges$min_depth_m)) {
  stop("Dataset 'ranges' contains missing or invalid depth limits.", call. = FALSE)
}

# Source review confirmed that the defensible depth range for
# Scyliorhinus canicula (SYC) is 100-400 m. The alternative
# legacy record (10-200 m) is therefore excluded.
syc_rows <- species_depth_ranges$species_code == "SYC"

syc_ranges_found <- paste(
  species_depth_ranges$min_depth_m[syc_rows],
  species_depth_ranges$max_depth_m[syc_rows],
  sep = "-"
)

expected_syc_ranges <- c("10-200", "100-400")

if (!identical(
  sort(syc_ranges_found),
  sort(expected_syc_ranges)
)) {
  stop(
    paste(
      "Unexpected source records for species code SYC.",
      "Review the depth-range resolution before proceeding."
    ),
    call. = FALSE
  )
}

species_depth_ranges <- species_depth_ranges[
  !(
    species_depth_ranges$species_code == "SYC" &
      species_depth_ranges$min_depth_m == 10 &
      species_depth_ranges$max_depth_m == 200
  ),
]

depth_duplicate <- duplicate_key(
  species_depth_ranges,
  "species_code"
)

species_depth_ranges$record_status <- ifelse(
  species_depth_ranges$species_code == "SYC",
  "validated_selected_depth_range",
  "validated_unique_key"
)

species_depth_ranges$record_status[depth_duplicate] <-
  "requires_review_duplicate_species_code"

if (any(depth_duplicate)) {
  duplicate_codes <- sort(unique(
    species_depth_ranges$species_code[depth_duplicate]
  ))

  add_issue(
    "error",
    "species_depth_ranges",
    "conflicting_duplicate_key",
    paste0(
      "Duplicated species code(s): ",
      paste(duplicate_codes, collapse = ", "),
      ". Source records are retained and marked for review."
    ),
    paste(
      "Select and document one defensible depth range for every",
      "duplicated species code before using this table."
    )
  )
}
species_depth_ranges <- species_depth_ranges[
  order(species_depth_ranges$species_code, species_depth_ranges$min_depth_m),
]
row.names(species_depth_ranges) <- NULL

# -----------------------------------------------------------------------------
# Harbours
# -----------------------------------------------------------------------------

harbours_raw <- as_table("Harbs")
assert_columns(harbours_raw, c("PORT", "LON", "LAT"), "Harbs")

harbours <- data.frame(
  harbour_name = clean_character(harbours_raw$PORT, upper = TRUE),
  longitude = as.numeric(harbours_raw$LON),
  latitude = as.numeric(harbours_raw$LAT),
  stringsAsFactors = FALSE
)

if (anyNA(harbours) ||
    any(harbours$longitude < -180 | harbours$longitude > 180) ||
    any(harbours$latitude < -90 | harbours$latitude > 90)) {
  stop("Dataset 'Harbs' contains missing or invalid geographic coordinates.", call. = FALSE)
}
assert_unique(harbours, "harbour_name", "harbours")
harbours <- harbours[order(harbours$harbour_name), ]
row.names(harbours) <- NULL
harbours_sf <- sf::st_as_sf(
  harbours,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
)

# -----------------------------------------------------------------------------
# LPUE upper-tail thresholds
# -----------------------------------------------------------------------------

threshold_raw <- as_table("Species_LPUE_thrs")
assert_columns(threshold_raw, "Species", "Species_LPUE_thrs")
gear_columns <- setdiff(names(threshold_raw), "Species")
if (length(gear_columns) == 0L) {
  stop("Dataset 'Species_LPUE_thrs' contains no gear columns.", call. = FALSE)
}

lpue_thresholds <- do.call(
  rbind,
  lapply(gear_columns, function(gear) {
    data.frame(
      species_code = clean_character(threshold_raw$Species, upper = TRUE),
      gear_code = toupper(gear),
      upper_quantile_probability = as.numeric(threshold_raw[[gear]]),
      stringsAsFactors = FALSE
    )
  })
)
lpue_thresholds$is_configured <- !is.na(lpue_thresholds$upper_quantile_probability)

configured <- lpue_thresholds$upper_quantile_probability[lpue_thresholds$is_configured]
if (any(configured <= 0 | configured >= 1)) {
  stop("Configured LPUE quantiles must lie strictly between 0 and 1.", call. = FALSE)
}
assert_unique(lpue_thresholds, c("species_code", "gear_code"), "lpue_thresholds")
lpue_thresholds <- lpue_thresholds[
  order(lpue_thresholds$species_code, lpue_thresholds$gear_code),
]
row.names(lpue_thresholds) <- NULL

if ("LLS" %in% lpue_thresholds$gear_code &&
    all(!lpue_thresholds$is_configured[lpue_thresholds$gear_code == "LLS"])) {
  add_issue(
    "warning",
    "lpue_thresholds",
    "all_thresholds_missing_for_gear",
    "All 22 LLS upper-quantile thresholds are missing. The records are retained with is_configured = FALSE.",
    "Confirm that LLS values should remain uncapped, or define and justify LLS thresholds."
  )
}

# -----------------------------------------------------------------------------
# Fuel-consumption parameters
# -----------------------------------------------------------------------------

fuel_raw <- as_table("sala_params")
assert_columns(fuel_raw, c("Gear", "m", "q"), "sala_params")

fuel_consumption_parameters <- data.frame(
  gear_code = clean_character(fuel_raw$Gear, upper = TRUE),
  loa_exponent = as.numeric(fuel_raw$m),
  fuel_coefficient = as.numeric(fuel_raw$q),
  stringsAsFactors = FALSE
)
if (anyNA(fuel_consumption_parameters) ||
    any(fuel_consumption_parameters$loa_exponent <= 0) ||
    any(fuel_consumption_parameters$fuel_coefficient <= 0)) {
  stop("Dataset 'sala_params' contains missing or non-positive parameters.", call. = FALSE)
}
assert_unique(fuel_consumption_parameters, "gear_code", "fuel_consumption_parameters")
fuel_consumption_parameters <- fuel_consumption_parameters[
  order(fuel_consumption_parameters$gear_code),
]
row.names(fuel_consumption_parameters) <- NULL

# -----------------------------------------------------------------------------
# Economic references
# -----------------------------------------------------------------------------

economic_raw <- as_table("EcoRef")
assert_columns(
  economic_raw,
  c("GSA", "Gear", "FS", "OC", "EC", "LC", "FD", "INV", "n", "GVL"),
  "EcoRef"
)

economic_reference <- data.frame(
  gsa = normalize_gsa(economic_raw$GSA),
  fishing_technique_code = clean_character(economic_raw$Gear, upper = TRUE),
  vessel_length_class = clean_character(economic_raw$FS, upper = TRUE),
  operating_cost = as.numeric(economic_raw$OC),
  energy_cost = as.numeric(economic_raw$EC),
  labour_cost = as.numeric(economic_raw$LC),
  fishing_days = as.numeric(economic_raw$FD),
  investment = as.numeric(economic_raw$INV),
  reference_vessel_count = as.numeric(economic_raw$n),
  gross_value_landings = as.numeric(economic_raw$GVL),
  stringsAsFactors = FALSE
)
if (anyNA(economic_reference) ||
    any(economic_reference[c(
      "operating_cost", "energy_cost", "labour_cost", "fishing_days",
      "investment", "reference_vessel_count", "gross_value_landings"
    )] < 0)) {
  stop("Dataset 'EcoRef' contains missing or negative reference values.", call. = FALSE)
}
assert_unique(
  economic_reference,
  c("gsa", "fishing_technique_code", "vessel_length_class"),
  "economic_reference"
)
economic_reference <- economic_reference[
  order(
    economic_reference$gsa,
    economic_reference$fishing_technique_code,
    economic_reference$vessel_length_class
  ),
]
row.names(economic_reference) <- NULL

current_case_study_gsas <- normalize_gsa(case_study_gsas)
if (length(current_case_study_gsas) > 0L &&
    length(intersect(unique(economic_reference$gsa), current_case_study_gsas)) == 0L) {
  add_issue(
    "error",
    "economic_reference",
    "no_coverage_for_current_case_study",
    paste0(
      "Economic references cover ",
      paste(sort(unique(economic_reference$gsa)), collapse = ", "),
      ", while the current Strait of Sicily configuration uses ",
      paste(current_case_study_gsas, collapse = ", "), "."
    ),
    "Provide an economic reference table covering the study GSAs or explicitly document a transferable calibration strategy."
  )
}

nisea_raw <- as_table("mNISEA")
assert_columns(nisea_raw, c("Indicator", "Gear", "value", "source"), "mNISEA")

indicator_names <- c(
  EC = "energy_cost",
  LC = "labour_cost",
  OC = "operating_cost",
  GVL = "gross_value_landings",
  GVA = "gross_value_added"
)

nisea_reference <- data.frame(
  indicator_code = clean_character(nisea_raw$Indicator, upper = TRUE),
  indicator_name = unname(indicator_names[clean_character(nisea_raw$Indicator, upper = TRUE)]),
  gear_code = clean_character(nisea_raw$Gear, upper = TRUE),
  reference_value = as.numeric(nisea_raw$value),
  source = clean_character(nisea_raw$source),
  stringsAsFactors = FALSE
)
if (anyNA(nisea_reference) || any(nisea_reference$reference_value < 0)) {
  stop("Dataset 'mNISEA' contains missing, unknown, or negative values.", call. = FALSE)
}
assert_unique(nisea_reference, c("indicator_code", "gear_code"), "nisea_reference")
nisea_reference <- nisea_reference[
  order(nisea_reference$gear_code, nisea_reference$indicator_code),
]
row.names(nisea_reference) <- NULL

# -----------------------------------------------------------------------------
# Write separate, explicit outputs
# -----------------------------------------------------------------------------

rds_objects <- list(
  species_prices = species_prices,
  species_price_monthly_mean = species_price_monthly_mean,
  fao_species = fao_species,
  fleet_register = fleet_register,
  species_depth_ranges = species_depth_ranges,
  lpue_thresholds = lpue_thresholds,
  fuel_consumption_parameters = fuel_consumption_parameters,
  economic_reference = economic_reference,
  nisea_reference = nisea_reference
)

for (name in names(rds_objects)) {
  saveRDS(
    rds_objects[[name]],
    file = file.path(output_dir, paste0(name, ".rds")),
    compress = "xz"
  )
}

harbour_file <- file.path(output_dir, "harbours.gpkg")
sf::st_write(
  harbours_sf,
  dsn = harbour_file,
  layer = "harbours",
  delete_dsn = TRUE,
  quiet = TRUE
)

write.csv(
  issues,
  file = file.path(output_dir, "validation_issues.csv"),
  row.names = FALSE,
  na = ""
)

publication_status <- c(
  species_prices = "hold_source_and_licence_review",
  species_price_monthly_mean = "derived_follows_species_prices",
  fao_species = "prefer_reproducible_official_download",
  fleet_register = "keep_local_or_retrieve_from_official_source",
  species_depth_ranges = "hold_methodological_and_source_review",
  harbours = "hold_source_and_licence_review",
  lpue_thresholds = "review_then_publish_as_method_configuration",
  fuel_consumption_parameters = "publish_with_complete_citation",
  economic_reference = "do_not_publish_without_permission",
  nisea_reference = "do_not_publish_without_permission"
)

manifest <- data.frame(
  dataset = c(names(rds_objects), "harbours"),
  file = c(paste0(names(rds_objects), ".rds"), "harbours.gpkg"),
  rows = c(vapply(rds_objects, nrow, integer(1L)), nrow(harbours_sf)),
  publication_status = unname(publication_status[c(names(rds_objects), "harbours")]),
  stringsAsFactors = FALSE
)
manifest$size_bytes <- file.info(file.path(output_dir, manifest$file))$size

write.csv(
  manifest,
  file = file.path(output_dir, "reference_data_manifest.csv"),
  row.names = FALSE,
  na = ""
)

message(
  "Prepared ", nrow(manifest), " reference datasets in ", output_dir,
  ". Review validation_issues.csv before using them in SMART3.1."
)
