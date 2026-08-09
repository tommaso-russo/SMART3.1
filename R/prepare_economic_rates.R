# Prepare economic ratios and align their segment keys with SMART activity.
#
# EcoRef normally contains annual totals for each
# GSA x fishing-technique x vessel-length segment. With
# reference_values = "segment_total", monetary values are pooled directly
# across the selected GSAs. reference_vessel_count is used only to derive
# diagnostic values per vessel and never as an expansion weight.
#
# The economic reference and the activity data may use different coding
# systems. For example, EcoRef uses DTS/HOK and VL1218, whereas SMART activity
# can use OTB/LLS and the separate VL1215/VL1518 classes. Explicit crosswalks
# are therefore required whenever target_groups is supplied.
prepare_economic_rates <- function(
    economic_reference,
    case_study_gsas = NULL,
    reference_values = c("segment_total", "per_vessel"),
    target_groups = NULL,
    gear_crosswalk = NULL,
    vessel_length_crosswalk = NULL,
    segment_crosswalk = NULL,
    missing_segment_method = c("error", "gear_pooled")
) {
  reference_values <- match.arg(reference_values)
  missing_segment_method <- match.arg(missing_segment_method)

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
      reference_Gear = toupper(
        trimws(as.character(.data$fishing_technique_code))
      ),
      reference_VL = toupper(
        trimws(as.character(.data$vessel_length_class))
      ),
      OC_reference = as.numeric(.data$operating_cost),
      EC_reference = as.numeric(.data$energy_cost),
      LC_reference = as.numeric(.data$labour_cost),
      INV_reference = as.numeric(.data$investment),
      n_reference_vessels = as.numeric(.data$reference_vessel_count),
      GVL_reference = as.numeric(.data$gross_value_landings)
    )

  identifier_fields <- c(
    "GSA",
    "reference_Gear",
    "reference_VL"
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
    selected_gsas <- unique(
      toupper(trimws(as.character(case_study_gsas)))
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
    "reference_Gear",
    "reference_VL"
  )

  if (anyDuplicated(reference_prepared[segment_key])) {
    stop(
      paste0(
        "The economic reference must contain one row per ",
        "GSA-reference_Gear-reference_VL segment."
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

  reference_prepared <- reference_prepared %>%
    dplyr::mutate(
      exposure = if (reference_values == "per_vessel") {
        .data$n_reference_vessels
      } else {
        1
      }
    )

  # Exact economic-reference segments.
  rates_by_segment <- reference_prepared %>%
    dplyr::group_by(
      .data$reference_Gear,
      .data$reference_VL
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
    )

  invalid_rates <- rates_by_segment %>%
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
    invalid_labels <- paste0(
      invalid_rates$reference_Gear,
      "-",
      invalid_rates$reference_VL
    )

    stop(
      "Invalid economic ratios were produced for: ",
      paste(invalid_labels, collapse = ", "),
      call. = FALSE
    )
  }

  # Without target groups, retain the native economic-reference keys. This
  # keeps the function useful for inspecting EcoRef independently of the IBM.
  if (is.null(target_groups)) {
    return(
      rates_by_segment %>%
        dplyr::transmute(
          Gear = .data$reference_Gear,
          VL = .data$reference_VL,
          reference_Gear = .data$reference_Gear,
          requested_reference_VL = .data$reference_VL,
          reference_VL_used = .data$reference_VL,
          economic_rate_source = "exact_reference_segment",
          dplyr::across(
            dplyr::all_of(
              c(
                "reference_value_type",
                "n_reference_rows",
                "n_reference_vessels",
                "reference_GVL",
                "reference_EC",
                "reference_OC",
                "reference_LC",
                "reference_INV",
                "EC_share",
                "OC_share",
                "LC_share",
                "INV_to_GVL",
                "reference_GVL_per_vessel",
                "reference_EC_per_vessel",
                "reference_OC_per_vessel",
                "reference_LC_per_vessel",
                "reference_INV_per_vessel"
              )
            )
          )
        ) %>%
        dplyr::arrange(.data$Gear, .data$VL)
    )
  }

  if (is.null(gear_crosswalk) || is.null(vessel_length_crosswalk)) {
    stop(
      paste0(
        "When 'target_groups' is supplied, both 'gear_crosswalk' and ",
        "'vessel_length_crosswalk' must be supplied."
      ),
      call. = FALSE
    )
  }

  target_required <- c("Gear", "VL")
  missing_target_columns <- setdiff(
    target_required,
    names(target_groups)
  )

  gear_crosswalk_required <- c(
    "Gear",
    "reference_fishing_technique_code"
  )
  missing_gear_crosswalk_columns <- setdiff(
    gear_crosswalk_required,
    names(gear_crosswalk)
  )

  vl_crosswalk_required <- c(
    "VL",
    "reference_vessel_length_class"
  )
  missing_vl_crosswalk_columns <- setdiff(
    vl_crosswalk_required,
    names(vessel_length_crosswalk)
  )

  if (length(missing_target_columns) > 0L) {
    stop(
      "Missing columns in 'target_groups': ",
      paste(missing_target_columns, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(missing_gear_crosswalk_columns) > 0L) {
    stop(
      "Missing columns in 'gear_crosswalk': ",
      paste(missing_gear_crosswalk_columns, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(missing_vl_crosswalk_columns) > 0L) {
    stop(
      "Missing columns in 'vessel_length_crosswalk': ",
      paste(missing_vl_crosswalk_columns, collapse = ", "),
      call. = FALSE
    )
  }

  targets_prepared <- target_groups %>%
    dplyr::transmute(
      Gear = toupper(trimws(as.character(.data$Gear))),
      VL = toupper(trimws(as.character(.data$VL)))
    ) %>%
    dplyr::distinct()

  gear_crosswalk_prepared <- gear_crosswalk %>%
    dplyr::transmute(
      Gear = toupper(trimws(as.character(.data$Gear))),
      reference_Gear = toupper(
        trimws(as.character(.data$reference_fishing_technique_code))
      )
    ) %>%
    dplyr::distinct()

  vl_crosswalk_prepared <- vessel_length_crosswalk %>%
    dplyr::transmute(
      VL = toupper(trimws(as.character(.data$VL))),
      requested_reference_VL = toupper(
        trimws(as.character(.data$reference_vessel_length_class))
      )
    ) %>%
    dplyr::distinct()

  if (
    anyNA(targets_prepared) ||
      any(!nzchar(targets_prepared$Gear)) ||
      any(!nzchar(targets_prepared$VL))
  ) {
    stop(
      "'target_groups' contains missing or empty Gear/VL values.",
      call. = FALSE
    )
  }

  if (anyDuplicated(gear_crosswalk_prepared$Gear)) {
    stop(
      "'gear_crosswalk' must contain one reference code per Gear.",
      call. = FALSE
    )
  }

  if (anyDuplicated(vl_crosswalk_prepared$VL)) {
    stop(
      paste0(
        "'vessel_length_crosswalk' must contain one reference class ",
        "per VL."
      ),
      call. = FALSE
    )
  }

  mapped_targets <- targets_prepared %>%
    dplyr::left_join(
      gear_crosswalk_prepared,
      by = "Gear",
      relationship = "many-to-one"
    ) %>%
    dplyr::left_join(
      vl_crosswalk_prepared,
      by = "VL",
      relationship = "many-to-one"
    )

  missing_crosswalks <- mapped_targets %>%
    dplyr::filter(
      is.na(.data$reference_Gear) |
        is.na(.data$requested_reference_VL)
    )

  if (nrow(missing_crosswalks) > 0L) {
    missing_labels <- paste0(
      missing_crosswalks$Gear,
      "-",
      missing_crosswalks$VL
    )

    stop(
      "Economic crosswalks are missing for: ",
      paste(missing_labels, collapse = ", "),
      call. = FALSE
    )
  }

  exact_targets <- mapped_targets %>%
    dplyr::inner_join(
      rates_by_segment,
      by = c(
        "reference_Gear",
        "requested_reference_VL" = "reference_VL"
      ),
      relationship = "many-to-one"
    ) %>%
    dplyr::mutate(
      reference_VL_used = .data$requested_reference_VL,
      economic_rate_source = "exact_reference_segment"
    )

  unmatched_targets <- mapped_targets %>%
    dplyr::anti_join(
      rates_by_segment,
      by = c(
        "reference_Gear",
        "requested_reference_VL" = "reference_VL"
      )
    )

  # Optional, explicitly documented substitutions for target Gear-VL pairs
  # whose exact reference segment is unavailable. Exact matches always retain
  # priority; this table is consulted only for unmatched targets.
  explicit_fallback_targets <- rates_by_segment[0, ] %>%
    dplyr::mutate(
      Gear = character(),
      VL = character(),
      requested_reference_VL = character(),
      reference_VL_used = character(),
      economic_rate_source = character(),
      .before = 1
    )

  if (!is.null(segment_crosswalk) && nrow(unmatched_targets) > 0L) {
    segment_crosswalk_required <- c(
      "Gear",
      "VL",
      "fallback_fishing_technique_code",
      "fallback_vessel_length_class"
    )

    missing_segment_crosswalk_columns <- setdiff(
      segment_crosswalk_required,
      names(segment_crosswalk)
    )

    if (length(missing_segment_crosswalk_columns) > 0L) {
      stop(
        "Missing columns in 'segment_crosswalk': ",
        paste(missing_segment_crosswalk_columns, collapse = ", "),
        call. = FALSE
      )
    }

    segment_crosswalk_prepared <- segment_crosswalk %>%
      dplyr::transmute(
        Gear = toupper(trimws(as.character(.data$Gear))),
        VL = toupper(trimws(as.character(.data$VL))),
        fallback_reference_Gear = toupper(trimws(as.character(
          .data$fallback_fishing_technique_code
        ))),
        fallback_reference_VL = toupper(trimws(as.character(
          .data$fallback_vessel_length_class
        )))
      ) %>%
      dplyr::distinct()

    if (
      anyNA(segment_crosswalk_prepared) ||
        any(!nzchar(segment_crosswalk_prepared$Gear)) ||
        any(!nzchar(segment_crosswalk_prepared$VL)) ||
        any(!nzchar(segment_crosswalk_prepared$fallback_reference_Gear)) ||
        any(!nzchar(segment_crosswalk_prepared$fallback_reference_VL))
    ) {
      stop(
        "'segment_crosswalk' contains missing or empty values.",
        call. = FALSE
      )
    }

    if (anyDuplicated(segment_crosswalk_prepared[c("Gear", "VL")])) {
      stop(
        "'segment_crosswalk' must contain at most one fallback per Gear-VL pair.",
        call. = FALSE
      )
    }

    explicit_fallback_candidates <- unmatched_targets %>%
      dplyr::inner_join(
        segment_crosswalk_prepared,
        by = c("Gear", "VL"),
        relationship = "many-to-one"
      )

    invalid_explicit_fallbacks <- explicit_fallback_candidates %>%
      dplyr::anti_join(
        rates_by_segment,
        by = c(
          "fallback_reference_Gear" = "reference_Gear",
          "fallback_reference_VL" = "reference_VL"
        )
      )

    if (nrow(invalid_explicit_fallbacks) > 0L) {
      invalid_labels <- paste0(
        invalid_explicit_fallbacks$Gear,
        "-",
        invalid_explicit_fallbacks$VL,
        " -> ",
        invalid_explicit_fallbacks$fallback_reference_Gear,
        "-",
        invalid_explicit_fallbacks$fallback_reference_VL
      )

      stop(
        "An explicit economic fallback is unavailable in EcoRef for: ",
        paste(invalid_labels, collapse = ", "),
        call. = FALSE
      )
    }

    explicit_fallback_targets <- explicit_fallback_candidates %>%
      dplyr::select(-.data$reference_Gear) %>%
      dplyr::inner_join(
        rates_by_segment,
        by = c(
          "fallback_reference_Gear" = "reference_Gear",
          "fallback_reference_VL" = "reference_VL"
        ),
        relationship = "many-to-one"
      ) %>%
      dplyr::mutate(
        reference_Gear = .data$fallback_reference_Gear,
        reference_VL_used = .data$fallback_reference_VL,
        economic_rate_source = "explicit_adjacent_segment"
      ) %>%
      dplyr::select(
        -.data$fallback_reference_Gear,
        -.data$fallback_reference_VL
      )

    unmatched_targets <- unmatched_targets %>%
      dplyr::anti_join(
        segment_crosswalk_prepared,
        by = c("Gear", "VL")
      )
  }

  if (
    nrow(unmatched_targets) > 0L &&
      missing_segment_method == "error"
  ) {
    missing_labels <- paste0(
      unmatched_targets$Gear,
      "-",
      unmatched_targets$VL,
      " -> ",
      unmatched_targets$reference_Gear,
      "-",
      unmatched_targets$requested_reference_VL
    )

    stop(
      "No exact economic reference is available for: ",
      paste(missing_labels, collapse = ", "),
      call. = FALSE
    )
  }

  fallback_targets <- rates_by_segment[0, ] %>%
    dplyr::mutate(
      Gear = character(),
      VL = character(),
      requested_reference_VL = character(),
      reference_VL_used = character(),
      economic_rate_source = character(),
      .before = 1
    )

  if (
    nrow(unmatched_targets) > 0L &&
      missing_segment_method == "gear_pooled"
  ) {
    rates_by_gear <- reference_prepared %>%
      dplyr::group_by(.data$reference_Gear) %>%
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
      )

    fallback_targets <- unmatched_targets %>%
      dplyr::left_join(
        rates_by_gear,
        by = "reference_Gear",
        relationship = "many-to-one"
      ) %>%
      dplyr::mutate(
        reference_VL_used = "ALL_AVAILABLE_VL",
        economic_rate_source = "gear_pooled_across_vl"
      )

    missing_fallbacks <- fallback_targets %>%
      dplyr::filter(
        is.na(.data$EC_share) |
          is.na(.data$OC_share) |
          is.na(.data$LC_share) |
          is.na(.data$INV_to_GVL)
      )

    if (nrow(missing_fallbacks) > 0L) {
      missing_labels <- paste0(
        missing_fallbacks$Gear,
        "-",
        missing_fallbacks$VL,
        " -> ",
        missing_fallbacks$reference_Gear
      )

      stop(
        "No gear-level economic fallback is available for: ",
        paste(missing_labels, collapse = ", "),
        call. = FALSE
      )
    }
  }

  output_columns <- c(
    "Gear",
    "VL",
    "reference_Gear",
    "requested_reference_VL",
    "reference_VL_used",
    "economic_rate_source",
    "reference_value_type",
    "n_reference_rows",
    "n_reference_vessels",
    "reference_GVL",
    "reference_EC",
    "reference_OC",
    "reference_LC",
    "reference_INV",
    "EC_share",
    "OC_share",
    "LC_share",
    "INV_to_GVL",
    "reference_GVL_per_vessel",
    "reference_EC_per_vessel",
    "reference_OC_per_vessel",
    "reference_LC_per_vessel",
    "reference_INV_per_vessel"
  )

  dplyr::bind_rows(
    exact_targets,
    explicit_fallback_targets,
    fallback_targets
  ) %>%
    dplyr::select(dplyr::all_of(output_columns)) %>%
    dplyr::arrange(.data$Gear, .data$VL)
}
