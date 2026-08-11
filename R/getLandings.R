# SMART3.1 definitive function version: 2026-08-11

#' Calculate landings from annual GSA-specific effort and LPUE
#'
#' `getLandings()` joins a year-specific, GSA-specific LPUE surface to gridded
#' fishing effort and calculates `landings = effort * lpue`. Its strict defaults
#' prevent the historical SMART3.1 failure in which a multi-year climatology was
#' joined by only month, gear and cell and unmatched records were silently lost.
#'
#' @param df_effort Data frame containing one effort record per join key.
#' @param df_lpue Data frame containing LPUE records. When `Species` is present,
#'   one record is allowed per join key and species.
#' @param join_keys Complete spatiotemporal join key. Defaults to `YEAR`,
#'   `MONTH`, `GSA_code`, `Gear` and `id_grid`.
#' @param effort_column Name of the non-negative effort column.
#' @param lpue_column Name of the non-negative LPUE column.
#' @param landings_column Name assigned to calculated landings.
#' @param allow_missing Whether missing effort or LPUE values are allowed.
#' @param require_all_lpue_matches If `TRUE`, stop when an LPUE row has no
#'   matching effort record. This avoids silent loss through an inner join.
#'
#' @return A data frame containing LPUE, matched effort and calculated landings.
#'   Attributes `landing_join_keys` and `landing_join_diagnostics` document the
#'   join. Unmatched effort is reported but is not an error because a cell can
#'   legitimately lack an LPUE for a particular species.
#'
#' @details
#' This function does not calibrate or normalise landings. In the definitive
#' mass-conserving workflow, spatial weights are normalised to calibrated
#' landings before `df_prod` is built. Annual-proxy fallback rows contain their
#' own explicit effort basis and are therefore built directly from the
#' allocation table rather than passed through this function.
#'
#' @export
getLandings <- function(
  df_effort,
  df_lpue,
  join_keys = c("YEAR", "MONTH", "GSA_code", "Gear", "id_grid"),
  effort_column = "effort",
  lpue_column = "lpue",
  landings_column = "landings",
  allow_missing = FALSE,
  require_all_lpue_matches = TRUE
) {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required by getLandings().", call. = FALSE)
  }

  if (!is.data.frame(df_effort) || nrow(df_effort) == 0L) {
    stop("'df_effort' must be a non-empty data frame.", call. = FALSE)
  }

  if (!is.data.frame(df_lpue) || nrow(df_lpue) == 0L) {
    stop("'df_lpue' must be a non-empty data frame.", call. = FALSE)
  }

  validate_name <- function(value, argument) {
    if (!is.character(value) || length(value) != 1L ||
        is.na(value) || !nzchar(value)) {
      stop("'", argument, "' must be one non-empty column name.", call. = FALSE)
    }
  }

  validate_name(effort_column, "effort_column")
  validate_name(lpue_column, "lpue_column")
  validate_name(landings_column, "landings_column")

  if (!is.character(join_keys) || length(join_keys) == 0L ||
      anyNA(join_keys) || any(!nzchar(join_keys)) || anyDuplicated(join_keys)) {
    stop("'join_keys' must contain unique non-empty names.", call. = FALSE)
  }

  for (argument in c("allow_missing", "require_all_lpue_matches")) {
    value <- get(argument)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("'", argument, "' must be TRUE or FALSE.", call. = FALSE)
    }
  }

  required_effort <- unique(c(join_keys, effort_column))
  required_lpue <- unique(c(join_keys, lpue_column))
  missing_effort <- setdiff(required_effort, names(df_effort))
  missing_lpue <- setdiff(required_lpue, names(df_lpue))

  if (length(missing_effort) > 0L) {
    stop(
      "Missing columns in 'df_effort': ",
      paste(missing_effort, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(missing_lpue) > 0L) {
    stop(
      "Missing columns in 'df_lpue': ",
      paste(missing_lpue, collapse = ", "),
      call. = FALSE
    )
  }

  if (landings_column %in% union(names(df_effort), names(df_lpue))) {
    stop("The requested landings column already exists.", call. = FALSE)
  }

  if (effort_column %in% names(df_lpue)) {
    stop(
      "The LPUE table already contains the effort column; use a distinct name ",
      "or build production directly from the allocation table.",
      call. = FALSE
    )
  }

  if (lpue_column %in% names(df_effort)) {
    stop("The effort table already contains the LPUE column.", call. = FALSE)
  }

  validate_keys <- function(data, label) {
    for (key in join_keys) {
      values <- data[[key]]
      invalid <- is.na(values)
      if (is.character(values) || is.factor(values)) {
        invalid <- invalid | !nzchar(trimws(as.character(values)))
      }
      if (any(invalid)) {
        stop(
          "Join key '", key, "' contains ", sum(invalid),
          " missing or empty values in ", label, ".",
          call. = FALSE
        )
      }
    }
  }

  validate_measure <- function(values, column, label) {
    if (!is.numeric(values)) {
      stop("Column '", column, "' in ", label, " must be numeric.", call. = FALSE)
    }
    if (!allow_missing && anyNA(values)) {
      stop("Column '", column, "' in ", label, " contains NA.", call. = FALSE)
    }
    observed <- values[!is.na(values)]
    if (any(!is.finite(observed)) || any(observed < 0)) {
      stop(
        "Column '", column, "' in ", label,
        " must contain finite non-negative values.",
        call. = FALSE
      )
    }
  }

  validate_keys(df_effort, "'df_effort'")
  validate_keys(df_lpue, "'df_lpue'")
  validate_measure(df_effort[[effort_column]], effort_column, "'df_effort'")
  validate_measure(df_lpue[[lpue_column]], lpue_column, "'df_lpue'")

  if ("YEAR" %in% join_keys) {
    normalize_year <- function(values, label) {
      out <- suppressWarnings(as.numeric(as.character(values)))
      invalid <- is.na(out) | !is.finite(out) | out != floor(out)
      if (any(invalid)) {
        stop(label, " must contain finite integer years.", call. = FALSE)
      }
      as.integer(out)
    }
    df_effort$YEAR <- normalize_year(df_effort$YEAR, "df_effort$YEAR")
    df_lpue$YEAR <- normalize_year(df_lpue$YEAR, "df_lpue$YEAR")
  }

  if (anyDuplicated(df_effort[join_keys])) {
    stop(
      "'df_effort' must contain one row per complete join key. Aggregate ",
      "effort before calling getLandings().",
      call. = FALSE
    )
  }

  lpue_identity <- unique(c(join_keys, intersect("Species", names(df_lpue))))
  if (anyDuplicated(df_lpue[lpue_identity])) {
    stop(
      "'df_lpue' contains duplicated records for: ",
      paste(lpue_identity, collapse = ", "),
      call. = FALSE
    )
  }

  effort_keys <- dplyr::distinct(
    df_effort,
    dplyr::across(dplyr::all_of(join_keys))
  )
  lpue_keys <- dplyr::distinct(
    df_lpue,
    dplyr::across(dplyr::all_of(join_keys))
  )

  unmatched_lpue_rows <- dplyr::anti_join(df_lpue, effort_keys, by = join_keys)
  unmatched_effort_rows <- dplyr::anti_join(df_effort, lpue_keys, by = join_keys)

  diagnostics <- data.frame(
    metric = c(
      "effort_input_rows", "lpue_input_rows", "unmatched_effort_rows",
      "unmatched_lpue_rows"
    ),
    value = c(
      nrow(df_effort), nrow(df_lpue),
      nrow(unmatched_effort_rows), nrow(unmatched_lpue_rows)
    ),
    stringsAsFactors = FALSE
  )

  if (require_all_lpue_matches && nrow(unmatched_lpue_rows) > 0L) {
    stop(
      nrow(unmatched_lpue_rows),
      " LPUE row(s) have no matching effort on the complete key: ",
      paste(join_keys, collapse = ", "),
      ". No rows were silently discarded.",
      call. = FALSE
    )
  }

  result <- dplyr::left_join(
    df_lpue,
    df_effort,
    by = join_keys,
    relationship = "many-to-one"
  )

  result[[landings_column]] <-
    result[[effort_column]] * result[[lpue_column]]

  diagnostics <- rbind(
    diagnostics,
    data.frame(
      metric = "output_rows",
      value = nrow(result),
      stringsAsFactors = FALSE
    )
  )

  attr(result, "landing_join_keys") <- join_keys
  attr(result, "landing_join_diagnostics") <- diagnostics
  attr(result, "smart31_version") <- "2026-08-11"
  result
}

attr(getLandings, "smart31_version") <- "2026-08-11"
