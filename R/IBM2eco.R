# Calculate monthly and annual economic indicators for the SMART IBM.
#
# SMART31 version 2026-08-15.1.
#
# The function keeps activity and species production separate until the
# appropriate aggregation level. Fuel use is calculated from full vessel
# activity, whereas production and GVL are obtained from the species-expanded
# table. Production is assigned to the observed activity month through
# activity_MONTH. This distinction is essential for annual LPUE proxy rows,
# whose production target month can differ from the month of the activity that
# supports the allocation. Investment is treated as an estimated capital stock
# and is not subtracted from GVA or gross profit.
#
# Internal dependencies:
#   assign_vessel_length_class()
#   one_character_value()
#   one_numeric_value()
#   sum_require_complete()
IBM2eco <- function(
    activity_data,
    production_data,
    fuel_parameters,
    fuel_activity_reference,
    distance_data,
    fuel_price,
    economic_rates,
    steaming_speed_kmh,
    round_trip_factor = 2,
    unsupported_fuel_method = c(
      "error",
      "reference_energy_share"
    )
) {
  unsupported_fuel_method <- match.arg(
    unsupported_fuel_method
  )

  if (
    !is.numeric(steaming_speed_kmh) ||
      length(steaming_speed_kmh) != 1L ||
      !is.finite(steaming_speed_kmh) ||
      steaming_speed_kmh <= 0
  ) {
    stop(
      "'steaming_speed_kmh' must be one positive number.",
      call. = FALSE
    )
  }

  if (
    !is.numeric(round_trip_factor) ||
      length(round_trip_factor) != 1L ||
      !is.finite(round_trip_factor) ||
      round_trip_factor <= 0
  ) {
    stop(
      "'round_trip_factor' must be one positive number.",
      call. = FALSE
    )
  }

  required_activity_columns <- c(
    "activity_id",
    "CFR",
    "YEAR",
    "MONTH",
    "Gear",
    "id_grid",
    "harbour",
    "loa",
    "ntrip",
    "fishing_time",
    "effort",
    "lpue_model_available"
  )

  required_production_columns <- c(
    "activity_id",
    "CFR",
    "YEAR",
    "activity_MONTH",
    "production_MONTH",
    "Gear",
    "harbour",
    "loa",
    "W",
    "GVL",
    "price_available",
    "effort_basis"
  )

  missing_activity_columns <- setdiff(
    required_activity_columns,
    names(activity_data)
  )

  missing_production_columns <- setdiff(
    required_production_columns,
    names(production_data)
  )

  if (length(missing_activity_columns) > 0L) {
    stop(
      "Missing columns in 'activity_data': ",
      paste(missing_activity_columns, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(missing_production_columns) > 0L) {
    stop(
      "Missing columns in 'production_data': ",
      paste(missing_production_columns, collapse = ", "),
      call. = FALSE
    )
  }

  activity <- activity_data %>%
    dplyr::transmute(
      activity_id = as.character(.data$activity_id),
      CFR = as.character(.data$CFR),
      YEAR = as.integer(.data$YEAR),
      MONTH = as.integer(.data$MONTH),
      Gear = toupper(trimws(as.character(.data$Gear))),
      id_grid = as.character(.data$id_grid),
      harbour = toupper(trimws(as.character(.data$harbour))),
      loa = as.numeric(.data$loa),
      ntrip = as.numeric(.data$ntrip),
      fishing_time = as.numeric(.data$fishing_time),
      effort = as.numeric(.data$effort),
      lpue_model_available = as.logical(.data$lpue_model_available)
    )

  if (anyDuplicated(activity$activity_id)) {
    stop(
      "'activity_data$activity_id' must be unique.",
      call. = FALSE
    )
  }

  distance_lookup <- distance_data %>%
    dplyr::transmute(
      id_grid = as.character(.data$id_grid),
      harbour = toupper(trimws(as.character(.data$harbour))),
      distance_km = as.numeric(.data$distance)
    ) %>%
    dplyr::distinct()

  if (anyDuplicated(distance_lookup[c("id_grid", "harbour")])) {
    stop(
      "'distance_data' must be unique by id_grid and harbour.",
      call. = FALSE
    )
  }

  activity <- activity %>%
    dplyr::left_join(
      distance_lookup,
      by = c("id_grid", "harbour"),
      relationship = "many-to-one"
    ) %>%
    dplyr::mutate(
      has_lpue = .data$lpue_model_available,
      has_distance =
        is.finite(.data$distance_km) &
        .data$distance_km >= 0
    )

  activity_monthly <- activity %>%
    dplyr::group_by(
      .data$CFR,
      .data$YEAR,
      .data$MONTH,
      .data$Gear,
      .data$harbour
    ) %>%
    dplyr::summarise(
      loa = one_numeric_value(.data$loa, "loa"),
      ntrip = one_numeric_value(.data$ntrip, "ntrip"),

      # Use temporary output names here. In dplyr::summarise(), a name created
      # earlier in the same call can mask the corresponding input column. If
      # this were called "fishing_time", the expressions below would see the
      # single monthly total instead of the original vector of cell values.
      fishing_time_total = sum_require_complete(.data$fishing_time),
      effort_total = sum_require_complete(.data$effort),

      fishing_time_with_lpue = sum(
        .data$fishing_time[.data$has_lpue]
      ),

      fishing_time_with_distance = sum(
        .data$fishing_time[.data$has_distance]
      ),

      weighted_distance_km = if (
        all(.data$has_distance) && sum(.data$fishing_time) > 0
      ) {
        stats::weighted.mean(
          .data$distance_km,
          .data$fishing_time
        )
      } else if (
        all(.data$has_distance) && all(.data$fishing_time == 0)
      ) {
        0
      } else {
        NA_real_
      },

      .groups = "drop"
    ) %>%
    dplyr::rename(
      fishing_time = fishing_time_total,
      effort = effort_total
    ) %>%
    dplyr::mutate(
      lpue_effort_coverage = dplyr::if_else(
        .data$fishing_time > 0,
        .data$fishing_time_with_lpue / .data$fishing_time,
        1
      ),

      distance_effort_coverage = dplyr::if_else(
        .data$fishing_time > 0,
        .data$fishing_time_with_distance / .data$fishing_time,
        1
      ),

      steaming_time = dplyr::if_else(
        .data$distance_effort_coverage == 1,
        round_trip_factor *
          (.data$weighted_distance_km / steaming_speed_kmh) *
          .data$ntrip,
        NA_real_
      ),

      total_activity_hours =
        .data$fishing_time + .data$steaming_time,

      VL = assign_vessel_length_class(.data$loa)
    )

  production_activity_keys <- production_data %>%
    dplyr::transmute(
      activity_id = as.character(.data$activity_id),
      production_CFR = as.character(.data$CFR),
      production_YEAR = as.integer(.data$YEAR),
      production_activity_MONTH = as.integer(.data$activity_MONTH),
      production_Gear = toupper(trimws(as.character(.data$Gear))),
      production_harbour = toupper(
        trimws(as.character(.data$harbour))
      ),
      production_loa = as.numeric(.data$loa)
    ) %>%
    dplyr::distinct()

  inconsistent_production_activity_keys <- production_activity_keys %>%
    dplyr::count(.data$activity_id, name = "n_distinct_activity_keys") %>%
    dplyr::filter(.data$n_distinct_activity_keys != 1L)

  if (nrow(inconsistent_production_activity_keys) > 0L) {
    stop(
      "Production metadata are inconsistent within activity_id.",
      call. = FALSE
    )
  }

  production_activity_key_mismatches <- production_activity_keys %>%
    dplyr::left_join(
      activity %>%
        dplyr::select(
          .data$activity_id,
          activity_CFR = .data$CFR,
          activity_YEAR = .data$YEAR,
          activity_MONTH = .data$MONTH,
          activity_Gear = .data$Gear,
          activity_harbour = .data$harbour,
          activity_loa = .data$loa
        ),
      by = "activity_id",
      relationship = "one-to-one"
    ) %>%
    dplyr::filter(
      is.na(.data$activity_CFR) |
        .data$production_CFR != .data$activity_CFR |
        .data$production_YEAR != .data$activity_YEAR |
        .data$production_activity_MONTH != .data$activity_MONTH |
        .data$production_Gear != .data$activity_Gear |
        .data$production_harbour != .data$activity_harbour |
        abs(.data$production_loa - .data$activity_loa) >
          sqrt(.Machine$double.eps) *
          pmax(1, abs(.data$activity_loa))
    )

  if (nrow(production_activity_key_mismatches) > 0L) {
    stop(
      "Production metadata do not match IBM_effort for some activity_id ",
      "values.",
      call. = FALSE
    )
  }

  production_monthly <- production_data %>%
    dplyr::transmute(
      activity_id = as.character(.data$activity_id),
      CFR = as.character(.data$CFR),
      YEAR = as.integer(.data$YEAR),
      # Costs belong to the month in which the activity occurred. For annual
      # proxy allocations this can differ from production_MONTH.
      MONTH = as.integer(.data$activity_MONTH),
      production_MONTH = as.integer(.data$production_MONTH),
      Gear = toupper(trimws(as.character(.data$Gear))),
      harbour = toupper(trimws(as.character(.data$harbour))),
      W = as.numeric(.data$W),
      GVL = as.numeric(.data$GVL),
      price_available = as.logical(.data$price_available),
      effort_basis = as.character(.data$effort_basis)
    ) %>%
    dplyr::group_by(
      .data$CFR,
      .data$YEAR,
      .data$MONTH,
      .data$Gear,
      .data$harbour
    ) %>%
    dplyr::summarise(
      W_modelled = sum_require_complete(.data$W),
      GVL_available = sum(.data$GVL, na.rm = TRUE),

      positive_unpriced_weight = sum(
        .data$W[
          !.data$price_available &
            !is.na(.data$W) &
            .data$W > 0
        ],
        na.rm = TRUE
      ),

      production_values_complete =
        !anyNA(.data$W) &
        !any(.data$W > 0 & !.data$price_available),

      annual_proxy_W = sum(
        .data$W[
          .data$effort_basis == "annual_same_year_proxy"
        ],
        na.rm = TRUE
      ),

      n_production_records = dplyr::n(),

      n_proxy_production_records = sum(
        .data$effort_basis == "annual_same_year_proxy"
      ),

      .groups = "drop"
    )

  monthly_keys <- c(
    "CFR",
    "YEAR",
    "MONTH",
    "Gear",
    "harbour"
  )

  monthly <- activity_monthly %>%
    dplyr::left_join(
      production_monthly,
      by = monthly_keys,
      relationship = "one-to-one"
    ) %>%
    dplyr::mutate(
      # A completely modelled activity group can legitimately have no
      # positive LPUE records. Its modelled weight and value are then zero.
      W_modelled = dplyr::if_else(
        is.na(.data$W_modelled) &
          .data$lpue_effort_coverage == 1,
        0,
        .data$W_modelled
      ),

      GVL_available = dplyr::if_else(
        is.na(.data$GVL_available) &
          .data$lpue_effort_coverage == 1,
        0,
        .data$GVL_available
      ),

      production_values_complete = dplyr::coalesce(
        .data$production_values_complete,
        .data$lpue_effort_coverage == 1
      ),

      annual_proxy_W = dplyr::coalesce(
        .data$annual_proxy_W,
        0
      ),

      n_production_records = dplyr::coalesce(
        .data$n_production_records,
        0L
      ),

      n_proxy_production_records = dplyr::coalesce(
        .data$n_proxy_production_records,
        0L
      ),

      revenue_complete =
        .data$lpue_effort_coverage == 1 &
        .data$production_values_complete %in% TRUE,

      W = dplyr::if_else(
        .data$revenue_complete,
        .data$W_modelled,
        NA_real_
      ),

      GVL = dplyr::if_else(
        .data$revenue_complete,
        .data$GVL_available,
        NA_real_
      )
    )

  fuel_models <- fuel_parameters %>%
    dplyr::transmute(
      Gear = toupper(trimws(as.character(.data$gear_code))),
      loa_exponent = as.numeric(.data$loa_exponent),
      fuel_coefficient = as.numeric(.data$fuel_coefficient)
    )

  if (anyDuplicated(fuel_models$Gear)) {
    stop(
      "'fuel_parameters' must be unique by gear_code.",
      call. = FALSE
    )
  }

  activity_reference <- fuel_activity_reference %>%
    dplyr::transmute(
      Gear = toupper(trimws(as.character(.data$Gear))),
      reference_hours_per_day = as.numeric(
        .data$reference_hours_per_day
      )
    )

  if (anyDuplicated(activity_reference$Gear)) {
    stop(
      paste0(
        "'fuel_activity_reference' must be unique by Gear."
      ),
      call. = FALSE
    )
  }

  fuel_price_prepared <- fuel_price %>%
    dplyr::transmute(
      YEAR = as.integer(.data$YEAR),
      fuel_price_eur_per_l = as.numeric(.data$fuel_cost)
    )

  if (anyDuplicated(fuel_price_prepared$YEAR)) {
    stop(
      "'fuel_price' must be unique by YEAR.",
      call. = FALSE
    )
  }

  required_economic_rate_columns <- c(
    "Gear",
    "VL",
    "EC_share",
    "OC_share",
    "LC_share",
    "INV_to_GVL"
  )

  missing_economic_rate_columns <- setdiff(
    required_economic_rate_columns,
    names(economic_rates)
  )

  if (length(missing_economic_rate_columns) > 0L) {
    stop(
      "Missing columns in 'economic_rates': ",
      paste(missing_economic_rate_columns, collapse = ", "),
      call. = FALSE
    )
  }

  economic_rate_lookup <- economic_rates

  if (!("economic_rate_source" %in% names(economic_rate_lookup))) {
    economic_rate_lookup$economic_rate_source <- "unspecified"
  }

  if (!("reference_Gear" %in% names(economic_rate_lookup))) {
    economic_rate_lookup$reference_Gear <- economic_rate_lookup$Gear
  }

  if (!("requested_reference_VL" %in% names(economic_rate_lookup))) {
    economic_rate_lookup$requested_reference_VL <- economic_rate_lookup$VL
  }

  if (!("reference_VL_used" %in% names(economic_rate_lookup))) {
    economic_rate_lookup$reference_VL_used <- economic_rate_lookup$VL
  }

  economic_rate_lookup <- economic_rate_lookup %>%
    dplyr::transmute(
      Gear = toupper(trimws(as.character(.data$Gear))),
      VL = toupper(trimws(as.character(.data$VL))),
      reference_Gear = toupper(
        trimws(as.character(.data$reference_Gear))
      ),
      requested_reference_VL = toupper(
        trimws(as.character(.data$requested_reference_VL))
      ),
      reference_VL_used = toupper(
        trimws(as.character(.data$reference_VL_used))
      ),
      economic_rate_source = as.character(.data$economic_rate_source),
      EC_share = as.numeric(.data$EC_share),
      OC_share = as.numeric(.data$OC_share),
      LC_share = as.numeric(.data$LC_share),
      INV_to_GVL = as.numeric(.data$INV_to_GVL)
    )

  economic_rate_values <- as.matrix(
    economic_rate_lookup[
      c("EC_share", "OC_share", "LC_share", "INV_to_GVL")
    ]
  )

  if (
    anyNA(economic_rate_lookup) ||
      any(!is.finite(economic_rate_values)) ||
      any(economic_rate_values < 0) ||
      anyDuplicated(economic_rate_lookup[c("Gear", "VL")])
  ) {
    stop(
      paste0(
        "'economic_rates' must contain complete, finite, non-negative ",
        "values and be unique by Gear and VL."
      ),
      call. = FALSE
    )
  }

  monthly <- monthly %>%
    dplyr::left_join(
      fuel_models,
      by = "Gear",
      relationship = "many-to-one"
    ) %>%
    dplyr::left_join(
      activity_reference,
      by = "Gear",
      relationship = "many-to-one"
    ) %>%
    dplyr::left_join(
      fuel_price_prepared,
      by = "YEAR",
      relationship = "many-to-one"
    ) %>%
    dplyr::left_join(
      economic_rate_lookup %>%
        dplyr::select(
          .data$Gear,
          .data$VL,
          .data$reference_Gear,
          .data$requested_reference_VL,
          .data$reference_VL_used,
          .data$economic_rate_source,
          .data$EC_share,
          .data$OC_share,
          .data$LC_share,
          .data$INV_to_GVL
        ),
      by = c("Gear", "VL"),
      relationship = "many-to-one"
    ) %>%
    dplyr::mutate(
      sala_model_available =
        !is.na(.data$fuel_coefficient) &
        !is.na(.data$loa_exponent) &
        !is.na(.data$reference_hours_per_day),

      daily_fuel_l = dplyr::if_else(
        .data$sala_model_available,
        .data$fuel_coefficient *
          .data$loa ^ .data$loa_exponent,
        NA_real_
      ),

      equivalent_active_days = dplyr::if_else(
        .data$sala_model_available &
          !is.na(.data$total_activity_hours),
        .data$total_activity_hours /
          .data$reference_hours_per_day,
        NA_real_
      ),

      FC = dplyr::case_when(
        .data$sala_model_available ~
          .data$daily_fuel_l * .data$equivalent_active_days,

        unsupported_fuel_method == "reference_energy_share" &
          !is.na(.data$GVL) &
          !is.na(.data$EC_share) &
          !is.na(.data$fuel_price_eur_per_l) &
          .data$fuel_price_eur_per_l > 0 ~
          (.data$GVL * .data$EC_share) /
            .data$fuel_price_eur_per_l,

        TRUE ~ NA_real_
      ),

      EC = dplyr::case_when(
        .data$sala_model_available ~
          .data$FC * .data$fuel_price_eur_per_l,

        unsupported_fuel_method == "reference_energy_share" ~
          .data$GVL * .data$EC_share,

        TRUE ~ NA_real_
      ),

      fuel_method = dplyr::case_when(
        .data$sala_model_available ~
          "sala_daily_equivalent_hours",

        unsupported_fuel_method == "reference_energy_share" ~
          "reference_energy_share",

        TRUE ~ "unavailable"
      ),

      # OC must exclude energy, labour and capital costs.
      OC = .data$GVL * .data$OC_share,
      LC = .data$GVL * .data$LC_share,
      GVA = .data$GVL - .data$EC - .data$OC,
      GP = .data$GVA - .data$LC,

      GPM = dplyr::if_else(
        !is.na(.data$GVL) & .data$GVL > 0,
        .data$GP / .data$GVL,
        NA_real_
      )
    )

  missing_economic_rates <- monthly %>%
    dplyr::filter(
      is.na(.data$EC_share) |
        is.na(.data$OC_share) |
        is.na(.data$LC_share) |
        is.na(.data$INV_to_GVL)
    ) %>%
    dplyr::distinct(
      .data$Gear,
      .data$VL
    )

  unsupported_fuel_gears <- monthly %>%
    dplyr::filter(!.data$sala_model_available) %>%
    dplyr::distinct(.data$Gear)

  if (nrow(missing_economic_rates) > 0L) {
    missing_labels <- paste0(
      missing_economic_rates$Gear,
      "-",
      missing_economic_rates$VL
    )

    stop(
      "Economic rates are unavailable for: ",
      paste(missing_labels, collapse = ", "),
      ". Rebuild 'economic_rates' with explicit crosswalks.",
      call. = FALSE
    )
  }

  if (
    unsupported_fuel_method == "error" &&
      nrow(unsupported_fuel_gears) > 0L
  ) {
    stop(
      "No validated daily fuel model is available for: ",
      paste(unsupported_fuel_gears$Gear, collapse = ", "),
      ". Inspect 'unsupported_fuel_gears'.",
      call. = FALSE
    )
  }

  annual <- monthly %>%
    dplyr::group_by(
      .data$CFR,
      .data$YEAR,
      .data$Gear,
      .data$harbour,
      .data$VL
    ) %>%
    dplyr::summarise(
      n_active_months = dplyr::n_distinct(.data$MONTH),
      n_production_records = sum(.data$n_production_records),
      n_proxy_production_records = sum(
        .data$n_proxy_production_records
      ),
      loa = one_numeric_value(.data$loa, "loa"),
      fishing_time = sum_require_complete(.data$fishing_time),
      steaming_time = sum_require_complete(.data$steaming_time),
      FC = sum_require_complete(.data$FC),
      W = sum_require_complete(.data$W),
      annual_proxy_W = sum_require_complete(.data$annual_proxy_W),
      GVL = sum_require_complete(.data$GVL),
      EC = sum_require_complete(.data$EC),
      OC = sum_require_complete(.data$OC),
      LC = sum_require_complete(.data$LC),
      GVA = sum_require_complete(.data$GVA),
      GP = sum_require_complete(.data$GP),

      INV_to_GVL = one_numeric_value(
        .data$INV_to_GVL,
        "INV_to_GVL"
      ),

      reference_Gear = one_character_value(
        .data$reference_Gear,
        "reference_Gear"
      ),

      requested_reference_VL = one_character_value(
        .data$requested_reference_VL,
        "requested_reference_VL"
      ),

      reference_VL_used = one_character_value(
        .data$reference_VL_used,
        "reference_VL_used"
      ),

      economic_rate_source = one_character_value(
        .data$economic_rate_source,
        "economic_rate_source"
      ),

      minimum_lpue_effort_coverage = min(
        .data$lpue_effort_coverage
      ),

      minimum_distance_effort_coverage = min(
        .data$distance_effort_coverage
      ),

      fuel_method = paste(
        sort(unique(.data$fuel_method)),
        collapse = "+"
      ),

      .groups = "drop"
    ) %>%
    dplyr::mutate(
      # INV is an estimated capital stock. It is not summed over months and
      # is not subtracted from GVA or gross profit.
      INV = .data$GVL * .data$INV_to_GVL,

      GPM = dplyr::if_else(
        !is.na(.data$GVL) & .data$GVL > 0,
        .data$GP / .data$GVL,
        NA_real_
      )
    )

  accounting_tolerance <- sqrt(
    .Machine$double.eps
  )

  inconsistent_monthly_accounting <- monthly %>%
    dplyr::filter(
      (
        !is.na(.data$GVA) &
          abs(
            .data$GVA -
              (.data$GVL - .data$EC - .data$OC)
          ) >
          accounting_tolerance * pmax(1, abs(.data$GVL))
      ) |
        (
          !is.na(.data$GP) &
            abs(.data$GP - (.data$GVA - .data$LC)) >
            accounting_tolerance * pmax(1, abs(.data$GVA))
        )
    )

  if (nrow(inconsistent_monthly_accounting) > 0L) {
    stop(
      "Internal inconsistency in economic accounting.",
      call. = FALSE
    )
  }

  production_mass_reconciliation <- tibble::tibble(
    quantity = c("W_kg", "GVL_eur"),
    production_input = c(
      sum_require_complete(as.numeric(production_data$W)),
      sum_require_complete(as.numeric(production_data$GVL))
    ),
    monthly_economic_output = c(
      sum_require_complete(monthly$W),
      sum_require_complete(monthly$GVL)
    )
  ) %>%
    dplyr::mutate(
      difference = .data$monthly_economic_output -
        .data$production_input,
      tolerance = sqrt(.Machine$double.eps) *
        pmax(1, abs(.data$production_input)),
      reconciled =
        is.finite(.data$difference) &
        abs(.data$difference) <= .data$tolerance
    )

  if (any(!production_mass_reconciliation$reconciled)) {
    stop(
      "Economic aggregation does not reproduce IBM production mass/value. ",
      "Inspect 'production_mass_reconciliation' inside IBM2eco().",
      call. = FALSE
    )
  }

  proxy_month_alignment <- production_data %>%
    dplyr::transmute(
      activity_MONTH = as.integer(.data$activity_MONTH),
      production_MONTH = as.integer(.data$production_MONTH),
      effort_basis = as.character(.data$effort_basis),
      W = as.numeric(.data$W)
    ) %>%
    dplyr::summarise(
      production_records = dplyr::n(),
      production_kg = sum_require_complete(.data$W),
      records_with_different_activity_and_production_month = sum(
        .data$activity_MONTH != .data$production_MONTH
      ),
      kg_with_different_activity_and_production_month = sum(
        .data$W[
          .data$activity_MONTH != .data$production_MONTH
        ]
      ),
      .by = .data$effort_basis
    )

  diagnostics <- list(
    unsupported_fuel_gears = unsupported_fuel_gears,

    fuel_method_usage = monthly %>%
      dplyr::count(
        .data$Gear,
        .data$fuel_method,
        name = "n_vessel_months"
      ),

    production_mass_reconciliation =
      production_mass_reconciliation,

    proxy_month_alignment = proxy_month_alignment,

    production_activity_key_mismatches =
      production_activity_key_mismatches,

    economic_rate_usage = monthly %>%
      dplyr::count(
        .data$Gear,
        .data$VL,
        .data$reference_Gear,
        .data$requested_reference_VL,
        .data$reference_VL_used,
        .data$economic_rate_source,
        name = "n_vessel_months"
      ),

    economic_rate_fallbacks = monthly %>%
      dplyr::filter(
        .data$economic_rate_source != "exact_reference_segment"
      ) %>%
      dplyr::distinct(
        .data$Gear,
        .data$VL,
        .data$reference_Gear,
        .data$requested_reference_VL,
        .data$reference_VL_used,
        .data$economic_rate_source
      ),

    incomplete_lpue_coverage = monthly %>%
      dplyr::filter(.data$lpue_effort_coverage < 1),

    incomplete_allocation_coverage = monthly %>%
      dplyr::filter(.data$lpue_effort_coverage < 1),

    incomplete_distance_coverage = monthly %>%
      dplyr::filter(.data$distance_effort_coverage < 1),

    incomplete_revenue = monthly %>%
      dplyr::filter(!(.data$revenue_complete %in% TRUE)),

    annual_incomplete = annual %>%
      dplyr::filter(
        !is.finite(.data$steaming_time) |
          !is.finite(.data$FC) |
          !is.finite(.data$W) |
          !is.finite(.data$GVL) |
          !is.finite(.data$EC) |
          !is.finite(.data$OC) |
          !is.finite(.data$LC)
      )
  )

  list(
    monthly = monthly,
    annual = annual,
    diagnostics = diagnostics
  )
}

attr(IBM2eco, "SMART31_version") <- "2026-08-15.1"
