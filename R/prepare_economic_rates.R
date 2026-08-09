# Prepare segment-specific economic ratios from the economic reference table.
#
# EcoRef normally contains annual totals for each
# GSA x fishing-technique x vessel-length segment. With
# reference_values = "segment_total", monetary values are pooled directly
# across the selected GSAs. reference_vessel_count is used only to derive
# diagnostic values per vessel and never as an expansion weight.
prepare_economic_rates <- function(
    economic_reference,
    case_study_gsas = NULL,
    reference_values = c("segment_total", "per_vessel")
) {
  reference_values <- match.arg(reference_values)

  required_columns <- c(
    "gsa",
    "fishing_technique_code",
    "vessel_length_class",
    "operating_cost",
    "energy_cost",
    "labour_cost",
    "investment",
    "reference_vessel_count",
    "gross_value_landings"
  )

  missing_columns <- setdiff(
    required_columns,
    names(economic_reference)
  )

  if (length(missing_columns) > 0L) {
    stop(
      "Missing columns in 'economic_reference': ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  reference_prepared <- economic_reference %>%
    dplyr::transmute(
      GSA = toupper(trimws(as.character(.data$gsa))),
      Gear = toupper(
        trimws(as.character(.data$fishing_technique_code))
      ),
      VL = toupper(trimws(as.character(.data$vessel_length_class))),
      OC_reference = as.numeric(.data$operating_cost),
      EC_reference = as.numeric(.data$energy_cost),
      LC_reference = as.numeric(.data$labour_cost),
      INV_reference = as.numeric(.data$investment),
      n_reference_vessels = as.numeric(.data$reference_vessel_count),
      GVL_reference = as.numeric(.data$gross_value_landings)
    )

  identifier_fields <- c(
    "GSA",
    "Gear",
    "VL"
  )

  numeric_fields <- c(
    "OC_reference",
    "EC_reference",
    "LC_reference",
    "INV_reference",
    "n_reference_vessels",
    "GVL_reference"
  )

  empty_identifier <- vapply(
    reference_prepared[identifier_fields],
    function(values) any(!nzchar(values)),
    logical(1)
  )

  numeric_matrix <- as.matrix(
    reference_prepared[numeric_fields]
  )

  if (
    anyNA(reference_prepared) ||
      any(empty_identifier) ||
      any(!is.finite(numeric_matrix)) ||
      any(numeric_matrix < 0)
  ) {
    stop(
      paste0(
        "The economic reference contains missing, empty, non-finite ",
        "or negative values."
      ),
      call. = FALSE
    )
  }

  if (!is.null(case_study_gsas)) {
    selected_gsas <- toupper(
      trimws(as.character(case_study_gsas))
    )

    reference_prepared <- reference_prepared %>%
      dplyr::filter(.data$GSA %in% selected_gsas)
  }

  if (nrow(reference_prepared) == 0L) {
    stop(
      "No economic references remain for the selected GSAs.",
      call. = FALSE
    )
  }

  segment_key <- c(
    "GSA",
    "Gear",
    "VL"
  )

  if (anyDuplicated(reference_prepared[segment_key])) {
    stop(
      paste0(
        "The economic reference must contain one row per ",
        "GSA-Gear-VL segment."
      ),
      call. = FALSE
    )
  }

  if (any(reference_prepared$n_reference_vessels <= 0)) {
    stop(
      paste0(
        "Each economic segment must have a positive ",
        "reference_vessel_count."
      ),
      call. = FALSE
    )
  }

  if (reference_values == "per_vessel") {
    reference_prepared <- reference_prepared %>%
      dplyr::mutate(
        exposure = .data$n_reference_vessels
      )
  } else {
    reference_prepared <- reference_prepared %>%
      dplyr::mutate(
        exposure = 1
      )
  }

  economic_rates <- reference_prepared %>%
    dplyr::group_by(
      .data$Gear,
      .data$VL
    ) %>%
    dplyr::summarise(
      reference_value_type = reference_values,
      n_reference_rows = dplyr::n(),
      n_reference_vessels = sum(.data$n_reference_vessels),
      reference_GVL = sum(.data$GVL_reference * .data$exposure),
      reference_EC = sum(.data$EC_reference * .data$exposure),
      reference_OC = sum(.data$OC_reference * .data$exposure),
      reference_LC = sum(.data$LC_reference * .data$exposure),
      reference_INV = sum(.data$INV_reference * .data$exposure),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      EC_share = .data$reference_EC / .data$reference_GVL,
      OC_share = .data$reference_OC / .data$reference_GVL,
      LC_share = .data$reference_LC / .data$reference_GVL,
      INV_to_GVL = .data$reference_INV / .data$reference_GVL,

      reference_GVL_per_vessel =
        .data$reference_GVL / .data$n_reference_vessels,

      reference_EC_per_vessel =
        .data$reference_EC / .data$n_reference_vessels,

      reference_OC_per_vessel =
        .data$reference_OC / .data$n_reference_vessels,

      reference_LC_per_vessel =
        .data$reference_LC / .data$n_reference_vessels,

      reference_INV_per_vessel =
        .data$reference_INV / .data$n_reference_vessels
    ) %>%
    dplyr::arrange(
      .data$Gear,
      .data$VL
    )

  invalid_rates <- economic_rates %>%
    dplyr::filter(
      !is.finite(.data$reference_GVL) |
        .data$reference_GVL <= 0 |
        !is.finite(.data$EC_share) |
        !is.finite(.data$OC_share) |
        !is.finite(.data$LC_share) |
        !is.finite(.data$INV_to_GVL) |
        .data$EC_share < 0 |
        .data$OC_share < 0 |
        .data$LC_share < 0 |
        .data$INV_to_GVL < 0
    )

  if (nrow(invalid_rates) > 0L) {
    stop(
      nrow(invalid_rates),
      paste0(
        " economic Gear-VL groups produced invalid ratios. ",
        "Inspect 'invalid_rates'."
      ),
      call. = FALSE
    )
  }

  economic_rates
}
