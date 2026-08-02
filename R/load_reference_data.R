#' Load standardized SMART3.1 reference data
#'
#' Reads the reference tables without attaching them to the global environment.
#' In strict mode, unresolved validation errors prevent downstream analysis.
#'
#' @param data_dir Directory produced by `data-raw/prepare_reference_data.R`.
#' @param strict If `TRUE`, stop when `validation_issues.csv` contains errors.
#'
#' @return A named list of reference tables. `harbours` is an `sf` object.
#' @export
load_reference_data <- function(data_dir = "data/reference", strict = TRUE) {
  required_rds <- c(
    "species_prices",
    "species_price_monthly_mean",
    "fao_species",
    "fleet_register",
    "species_depth_ranges",
    "lpue_thresholds",
    "fuel_consumption_parameters",
    "economic_reference",
    "nisea_reference"
  )

  required_files <- c(
    file.path(data_dir, paste0(required_rds, ".rds")),
    file.path(data_dir, "harbours.gpkg"),
    file.path(data_dir, "validation_issues.csv")
  )

  missing_files <- required_files[!file.exists(required_files)]
  if (length(missing_files) > 0L) {
    stop(
      "Missing SMART3.1 reference-data files: ",
      paste(missing_files, collapse = ", "),
      call. = FALSE
    )
  }

  issues <- utils::read.csv(
    file.path(data_dir, "validation_issues.csv"),
    stringsAsFactors = FALSE,
    na.strings = ""
  )

  unresolved_errors <- issues[issues$severity == "error", , drop = FALSE]
  if (isTRUE(strict) && nrow(unresolved_errors) > 0L) {
    stop(
      "Reference data contain unresolved validation errors: ",
      paste(
        paste0(unresolved_errors$dataset, " [", unresolved_errors$check, "]"),
        collapse = "; "
      ),
      ". Review validation_issues.csv or use strict = FALSE only for diagnostics.",
      call. = FALSE
    )
  }

  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("Package 'sf' is required to load harbours.gpkg.", call. = FALSE)
  }

  out <- setNames(
    lapply(required_rds, function(name) {
      readRDS(file.path(data_dir, paste0(name, ".rds")))
    }),
    required_rds
  )

  out$harbours <- sf::st_read(
    file.path(data_dir, "harbours.gpkg"),
    layer = "harbours",
    quiet = TRUE
  )
  out$validation_issues <- issues
  out
}
