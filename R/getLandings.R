#' Estimate landings from gridded fishing effort and LPUE
#'
#' `getLandings()` combines fishing effort with monthly, gear-specific and
#' spatially explicit LPUE estimates, then calculates landings as
#' `effort * lpue`.
#'
#' The default join keys reflect the SMART3.1 data structure:
#' `MONTH`, `Gear`, and `id_grid`. `YEAR` is intentionally not a default key
#' because LPUE is currently estimated as a monthly climatology, whereas
#' `Species` occurs only in the LPUE table. Consequently, each effort record
#' is matched to all species for which an LPUE estimate exists for the same
#' month, gear and grid cell.
#'
#' Only matched records are returned. Counts of unmatched effort and LPUE rows
#' are stored in the `landing_join_diagnostics` attribute of the result.
#'
#' @param df_effort A data frame containing fishing effort. It must include the
#'   join keys and a numeric effort column.
#' @param df_lpue A data frame containing LPUE estimates. It must include the
#'   join keys and a numeric LPUE column.
#' @param join_keys Character vector with the columns used to join effort and
#'   LPUE. Defaults to `c("MONTH", "Gear", "id_grid")`.
#' @param effort_column Name of the effort column. Defaults to `"effort"`.
#' @param lpue_column Name of the LPUE column. Defaults to `"lpue"`.
#' @param landings_column Name assigned to the calculated landings column.
#'   Defaults to `"landings"`.
#' @param allow_missing Logical. If `FALSE` (default), missing values in effort
#'   or LPUE cause an error. If `TRUE`, they are retained and generate missing
#'   landings.
#'
#' @return A data frame containing the matched effort and LPUE records plus the
#'   calculated landings column. The result has a `landing_join_diagnostics`
#'   attribute reporting input, matched and unmatched row counts.
#'
#' @details
#' Effort and LPUE must be finite and non-negative. Join-key columns cannot
#' contain missing or empty values. The function uses an explicit inner join:
#' combinations lacking either effort or LPUE cannot produce a landing estimate
#' and are therefore excluded from the returned table, but are counted in the
#' diagnostic attribute.
#'
#' The function requires `dplyr` but does not require it to be attached with
#' `library(dplyr)`.
#'
#' @examples
#' effort_data <- data.frame(
#'   YEAR = c(2024L, 2025L),
#'   MONTH = c(1L, 1L),
#'   Gear = c("OTB", "OTB"),
#'   id_grid = c("cell_1", "cell_1"),
#'   effort = c(100, 120)
#' )
#'
#' lpue_data <- data.frame(
#'   MONTH = c(1L, 1L),
#'   Gear = c("OTB", "OTB"),
#'   Species = c("HKE", "MUT"),
#'   id_grid = c("cell_1", "cell_1"),
#'   lpue = c(0.5, 0.2)
#' )
#'
#' landings_data <- getLandings(effort_data, lpue_data)
#' attr(landings_data, "landing_join_diagnostics")
#'
#' @export
getLandings <- function(
  df_effort,
  df_lpue,
  join_keys = c("MONTH", "Gear", "id_grid"),
  effort_column = "effort",
  lpue_column = "lpue",
  landings_column = "landings",
  allow_missing = FALSE
) {

  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop(
      "Package 'dplyr' is required by getLandings().",
      call. = FALSE
    )
  }

  if (!is.data.frame(df_effort)) {
    stop("'df_effort' must be a data frame.", call. = FALSE)
  }

  if (!is.data.frame(df_lpue)) {
    stop("'df_lpue' must be a data frame.", call. = FALSE)
  }

  if (nrow(df_effort) == 0L) {
    stop("'df_effort' contains no rows.", call. = FALSE)
  }

  if (nrow(df_lpue) == 0L) {
    stop("'df_lpue' contains no rows.", call. = FALSE)
  }

  validate_single_column_name <- function(x, argument_name) {
    if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
      stop(
        "'", argument_name, "' must be one non-empty column name.",
        call. = FALSE
      )
    }
  }

  validate_single_column_name(effort_column, "effort_column")
  validate_single_column_name(lpue_column, "lpue_column")
  validate_single_column_name(landings_column, "landings_column")

  if (
    !is.character(join_keys) ||
      length(join_keys) == 0L ||
      anyNA(join_keys) ||
      any(!nzchar(join_keys)) ||
      anyDuplicated(join_keys) > 0L
  ) {
    stop(
      "'join_keys' must contain unique, non-empty column names.",
      call. = FALSE
    )
  }

  if (!is.logical(allow_missing) || length(allow_missing) != 1L || is.na(allow_missing)) {
    stop("'allow_missing' must be TRUE or FALSE.", call. = FALSE)
  }

  required_effort_columns <- unique(c(join_keys, effort_column))
  required_lpue_columns <- unique(c(join_keys, lpue_column))

  missing_effort_columns <- setdiff(required_effort_columns, names(df_effort))
  missing_lpue_columns <- setdiff(required_lpue_columns, names(df_lpue))

  if (length(missing_effort_columns) > 0L) {
    stop(
      "Missing columns in 'df_effort': ",
      paste(missing_effort_columns, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(missing_lpue_columns) > 0L) {
    stop(
      "Missing columns in 'df_lpue': ",
      paste(missing_lpue_columns, collapse = ", "),
      call. = FALSE
    )
  }

  if (landings_column %in% c(names(df_effort), names(df_lpue))) {
    stop(
      "The requested landings column already exists in an input table: ",
      landings_column,
      call. = FALSE
    )
  }

  validate_join_keys <- function(data, data_name) {
    for (key in join_keys) {
      key_values <- data[[key]]
      invalid_key <- is.na(key_values)

      if (is.character(key_values) || is.factor(key_values)) {
        invalid_key <- invalid_key | !nzchar(trimws(as.character(key_values)))
      }

      if (any(invalid_key)) {
        stop(
          "Join key '", key, "' contains ", sum(invalid_key),
          " missing or empty values in '", data_name, "'.",
          call. = FALSE
        )
      }
    }
  }

  validate_measure <- function(x, column_name, data_name) {
    if (!is.numeric(x)) {
      stop(
        "Column '", column_name, "' in '", data_name,
        "' must be numeric.",
        call. = FALSE
      )
    }

    if (!allow_missing && anyNA(x)) {
      stop(
        "Column '", column_name, "' in '", data_name,
        "' contains missing values.",
        call. = FALSE
      )
    }

    observed_values <- x[!is.na(x)]

    if (any(!is.finite(observed_values))) {
      stop(
        "Column '", column_name, "' in '", data_name,
        "' contains non-finite values.",
        call. = FALSE
      )
    }

    if (any(observed_values < 0)) {
      stop(
        "Column '", column_name, "' in '", data_name,
        "' contains negative values.",
        call. = FALSE
      )
    }
  }

  validate_join_keys(df_effort, "df_effort")
  validate_join_keys(df_lpue, "df_lpue")
  validate_measure(df_effort[[effort_column]], effort_column, "df_effort")
  validate_measure(df_lpue[[lpue_column]], lpue_column, "df_lpue")

  # YEAR belongs to the effort table in the current SMART3.1 workflow. Keep it
  # as an integer when it is present and can be converted without information
  # loss. This preserves compatibility with downstream annual aggregations.
  if ("YEAR" %in% names(df_effort)) {
    year_numeric <- suppressWarnings(as.numeric(as.character(df_effort$YEAR)))

    invalid_year <- is.na(year_numeric) | !is.finite(year_numeric) |
      year_numeric != floor(year_numeric)

    if (any(invalid_year)) {
      stop(
        "'df_effort$YEAR' must contain finite integer years.",
        call. = FALSE
      )
    }

    df_effort$YEAR <- as.integer(year_numeric)
  }

  effort_key_combinations <- dplyr::distinct(
    df_effort,
    dplyr::across(dplyr::all_of(join_keys))
  )

  lpue_key_combinations <- dplyr::distinct(
    df_lpue,
    dplyr::across(dplyr::all_of(join_keys))
  )

  unmatched_effort_rows <- dplyr::anti_join(
    df_effort,
    lpue_key_combinations,
    by = join_keys
  )

  unmatched_lpue_rows <- dplyr::anti_join(
    df_lpue,
    effort_key_combinations,
    by = join_keys
  )

  result <- dplyr::inner_join(
    df_effort,
    df_lpue,
    by = join_keys,
    relationship = "many-to-many"
  )

  if (nrow(result) == 0L) {
    stop(
      "Effort and LPUE have no matching combinations for join keys: ",
      paste(join_keys, collapse = ", "),
      call. = FALSE
    )
  }

  result[[landings_column]] <-
    result[[effort_column]] * result[[lpue_column]]

  diagnostics <- data.frame(
    metric = c(
      "effort_input_rows",
      "lpue_input_rows",
      "matched_output_rows",
      "unmatched_effort_rows",
      "unmatched_lpue_rows"
    ),
    value = c(
      nrow(df_effort),
      nrow(df_lpue),
      nrow(result),
      nrow(unmatched_effort_rows),
      nrow(unmatched_lpue_rows)
    ),
    stringsAsFactors = FALSE
  )

  attr(result, "landing_join_keys") <- join_keys
  attr(result, "landing_join_diagnostics") <- diagnostics

  result
}
