# SMART3.1 definitive function version: 2026-08-08
# Compatible with SMART31_LPUE_estimation_chunk.R.

#' Estimate spatial LPUE with non-negative least squares
#'
#' Estimates one non-negative LPUE coefficient for each retained grid cell.
#' Rows represent fishing observations, `Kg` is landed biomass, and grid-cell
#' columns contain the corresponding fishing effort. Poorly sampled cells are
#' filtered before fitting and observations with no retained effort can either
#' be removed or treated as an error.
#'
#' @param xy Data frame containing `CFR`, `MONTH`, `Gear`, `Kg`, and one or more
#'   numeric effort columns identified by grid-cell names. An optional `YEAR`
#'   column is treated as an observation identifier rather than as effort.
#' @param column_quantile Quantile of positive eligible column totals used to
#'   remove poorly sampled grid cells. Defaults to `0.3`, matching the
#'   historical function. Set to `0` to retain all otherwise eligible cells.
#' @param min_column_sum Minimum positive total effort required for a grid cell.
#' @param na_effort How missing or infinite effort values are handled: replace
#'   them with zero (`"zero"`) or stop (`"error"`).
#' @param zero_effort How observations with no effort in the retained cells are
#'   handled: remove them (`"remove"`) or stop (`"error"`).
#' @param check_duplicates If `TRUE`, duplicated observation identifiers cause
#'   an error. Records should be aggregated before calling this function.
#'
#' @return A list containing:
#' \describe{
#'   \item{lpue}{Data frame with `id_grid` and the estimated non-negative
#'     `lpue`.}
#'   \item{df_check}{Observed biomass, fitted biomass and residuals for the
#'     observations used in the model.}
#'   \item{fit}{The fitted `nnls` object.}
#'   \item{performance}{One-row data frame with sample size, number of retained
#'     cells, matrix rank, RMSE, MAE and R-squared.}
#'   \item{cell_diagnostics}{Total effort, filtering threshold, retention status
#'     and exclusion reason for every candidate grid cell.}
#'   \item{observation_diagnostics}{Input row, total retained effort and whether
#'     each observation was used.}
#'   \item{settings}{Effective filtering settings.}
#' }
#'
#' @examples
#' xy <- data.frame(
#'   CFR = paste0("v", 1:4),
#'   MONTH = 1,
#'   Gear = "OTB",
#'   Kg = c(10, 5, 3, 8),
#'   cell_1 = c(2, 1, 0, 1),
#'   cell_2 = c(0, 1, 2, 1)
#' )
#' result <- getLPUE(xy, column_quantile = 0)
#' result$lpue
#'
#' @export
getLPUE <- function(xy,
                    column_quantile = 0.3,
                    min_column_sum = 0,
                    na_effort = c("zero", "error"),
                    zero_effort = c("remove", "error"),
                    check_duplicates = TRUE) {
  if (!requireNamespace("nnls", quietly = TRUE)) {
    stop("Package 'nnls' is required by getLPUE().", call. = FALSE)
  }

  if (!is.data.frame(xy)) {
    stop("'xy' must be a data frame.", call. = FALSE)
  }

  required_columns <- c("CFR", "MONTH", "Gear", "Kg")
  missing_columns <- setdiff(required_columns, names(xy))

  if (length(missing_columns) > 0L) {
    stop(
      paste0(
        "'xy' is missing required columns: ",
        paste(missing_columns, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  if (anyDuplicated(names(xy))) {
    stop("'xy' must have unique column names.", call. = FALSE)
  }

  if (!is.numeric(column_quantile) || length(column_quantile) != 1L ||
      !is.finite(column_quantile) || column_quantile < 0 ||
      column_quantile >= 1) {
    stop("'column_quantile' must be in [0, 1).", call. = FALSE)
  }

  if (!is.numeric(min_column_sum) || length(min_column_sum) != 1L ||
      !is.finite(min_column_sum) || min_column_sum < 0) {
    stop("'min_column_sum' must be one non-negative number.", call. = FALSE)
  }

  if (!is.logical(check_duplicates) || length(check_duplicates) != 1L ||
      is.na(check_duplicates)) {
    stop("'check_duplicates' must be TRUE or FALSE.", call. = FALSE)
  }

  na_effort <- match.arg(na_effort)
  zero_effort <- match.arg(zero_effort)

  identifier_columns <- intersect(
    c("CFR", "YEAR", "MONTH", "Gear"),
    names(xy)
  )
  non_effort_columns <- unique(c(identifier_columns, "Kg"))
  effort_names <- setdiff(names(xy), non_effort_columns)

  if (length(effort_names) == 0L) {
    stop("'xy' contains no grid-cell effort columns.", call. = FALSE)
  }

  non_numeric_effort <- effort_names[
    !vapply(xy[effort_names], is.numeric, logical(1))
  ]

  if (length(non_numeric_effort) > 0L) {
    stop(
      paste0(
        "Grid-cell effort columns must be numeric: ",
        paste(non_numeric_effort, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  if (!is.numeric(xy$Kg) || any(!is.finite(xy$Kg)) || any(xy$Kg < 0)) {
    stop(
      "'Kg' must contain finite, non-negative numeric values.",
      call. = FALSE
    )
  }

  if (nrow(xy) < 2L) {
    stop("At least two observations are required for LPUE estimation.", call. = FALSE)
  }

  missing_identifiers <- vapply(
    xy[identifier_columns],
    function(x) any(is.na(x) | trimws(as.character(x)) == ""),
    logical(1)
  )

  if (any(missing_identifiers)) {
    stop(
      paste0(
        "Missing values were found in identifier columns: ",
        paste(names(missing_identifiers)[missing_identifiers], collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  if (check_duplicates) {
    duplicated_observations <- duplicated(xy[identifier_columns]) |
      duplicated(xy[identifier_columns], fromLast = TRUE)

    if (any(duplicated_observations)) {
      stop(
        paste0(
          "Duplicated fishing observations were found for ",
          paste(identifier_columns, collapse = ", "),
          ". Aggregate records before calling getLPUE()."
        ),
        call. = FALSE
      )
    }
  }

  effort_matrix <- data.matrix(xy[effort_names])
  invalid_effort <- !is.finite(effort_matrix)
  n_effort_values_replaced <- sum(invalid_effort)

  if (n_effort_values_replaced > 0L) {
    if (identical(na_effort, "error")) {
      stop(
        "Grid-cell effort contains missing or infinite values.",
        call. = FALSE
      )
    }

    effort_matrix[invalid_effort] <- 0
  }

  if (any(effort_matrix < 0)) {
    stop("Grid-cell effort cannot contain negative values.", call. = FALSE)
  }

  column_totals <- colSums(effort_matrix)
  eligible <- column_totals > 0 & column_totals >= min_column_sum

  if (!any(eligible)) {
    stop(
      "No grid cell has enough positive effort for LPUE estimation.",
      call. = FALSE
    )
  }

  quantile_threshold <- as.numeric(stats::quantile(
    column_totals[eligible],
    probs = column_quantile,
    names = FALSE,
    type = 7
  ))
  retained_cells <- eligible & column_totals >= quantile_threshold

  cell_diagnostics <- data.frame(
    id_grid = effort_names,
    total_effort = as.numeric(column_totals),
    eligible_before_quantile = eligible,
    quantile_threshold = quantile_threshold,
    retained = retained_cells,
    exclusion_reason = ifelse(
      retained_cells,
      NA_character_,
      ifelse(
        column_totals <= 0,
        "no positive effort",
        ifelse(
          column_totals < min_column_sum,
          "total effort below min_column_sum",
          "total effort below quantile threshold"
        )
      )
    ),
    stringsAsFactors = FALSE
  )

  model_matrix_all_rows <- effort_matrix[, retained_cells, drop = FALSE]
  retained_effort_by_row <- rowSums(model_matrix_all_rows)
  usable_observations <- retained_effort_by_row > 0

  observation_diagnostics <- data.frame(
    input_row = seq_len(nrow(xy)),
    total_retained_effort = retained_effort_by_row,
    used = usable_observations,
    exclusion_reason = ifelse(
      usable_observations,
      NA_character_,
      "no effort in retained cells"
    ),
    stringsAsFactors = FALSE
  )

  if (any(!usable_observations) && identical(zero_effort, "error")) {
    stop(
      paste0(
        sum(!usable_observations),
        " observation(s) have no effort in retained cells."
      ),
      call. = FALSE
    )
  }

  model_matrix <- model_matrix_all_rows[usable_observations, , drop = FALSE]
  response <- xy$Kg[usable_observations]

  if (nrow(model_matrix) < 2L) {
    stop(
      "Fewer than two observations remain after effort filtering.",
      call. = FALSE
    )
  }

  matrix_rank <- qr(model_matrix)$rank

  if (matrix_rank < ncol(model_matrix)) {
    warning(
      paste0(
        "The retained effort matrix is rank deficient (rank ",
        matrix_rank,
        " for ",
        ncol(model_matrix),
        " cells); individual LPUE coefficients may not be uniquely identifiable."
      ),
      call. = FALSE
    )
  }

  fit <- nnls::nnls(model_matrix, response)
  fitted_values <- as.numeric(model_matrix %*% fit$x)
  residuals <- response - fitted_values
  rmse <- sqrt(mean(residuals^2))
  mae <- mean(abs(residuals))
  total_sum_squares <- sum((response - mean(response))^2)
  r_squared <- if (total_sum_squares > 0) {
    1 - sum(residuals^2) / total_sum_squares
  } else {
    NA_real_
  }

  performance <- data.frame(
    n_input_observations = nrow(xy),
    n_used_observations = nrow(model_matrix),
    n_removed_observations = sum(!usable_observations),
    n_candidate_cells = length(effort_names),
    n_retained_cells = ncol(model_matrix),
    matrix_rank = matrix_rank,
    rmse = rmse,
    mae = mae,
    r_squared = r_squared,
    stringsAsFactors = FALSE
  )

  list(
    lpue = data.frame(
      id_grid = colnames(model_matrix),
      lpue = as.numeric(fit$x),
      stringsAsFactors = FALSE
    ),
    df_check = data.frame(
      input_row = which(usable_observations),
      obs = response,
      fitted = fitted_values,
      residual = residuals,
      stringsAsFactors = FALSE
    ),
    fit = fit,
    performance = performance,
    cell_diagnostics = cell_diagnostics,
    observation_diagnostics = observation_diagnostics,
    settings = list(
      column_quantile = column_quantile,
      min_column_sum = min_column_sum,
      quantile_threshold = quantile_threshold,
      na_effort = na_effort,
      zero_effort = zero_effort,
      check_duplicates = check_duplicates,
      n_effort_values_replaced = n_effort_values_replaced
    )
  )
}

attr(getLPUE, "smart31_version") <- "2026-08-08"
