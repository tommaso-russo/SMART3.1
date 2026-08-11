#' Estimate spatial LPUE with non-negative least squares
#'
#' Estimates one non-negative LPUE coefficient for each retained grid cell.
#' Rows represent vessel-month observations, `Kg` is the landed biomass, and
#' grid-cell columns contain the corresponding fishing effort.
#'
#' @param xy A data frame containing `CFR`, `MONTH`, `Gear`, `Kg`, and one or
#'   more numeric effort columns identified by grid-cell names.
#' @param column_quantile Quantile of positive column totals used to remove
#'   poorly sampled grid cells. Defaults to `0.3`, matching the historical
#'   function. Set to `0` to retain every cell with positive effort.
#' @param min_column_sum Minimum total effort required for a grid cell before
#'   the quantile filter is applied. Defaults to `0`.
#' @param na_effort Either `"zero"` (historical behaviour) or `"error"`.
#'
#' @return A list with `lpue` (`id_grid`, `lpue`) and `df_check` (`obs`,
#'   `fitted`).
#' @export
getLPUE <- function(xy,
                    column_quantile = 0.3,
                    min_column_sum = 0,
                    na_effort = c("zero", "error")) {
  if (!requireNamespace("nnls", quietly = TRUE)) {
    stop("Package 'nnls' is required by getLPUE().", call. = FALSE)
  }
  if (!is.data.frame(xy)) {
    stop("'xy' must be a data frame.", call. = FALSE)
  }

  required <- c("CFR", "MONTH", "Kg", "Gear")
  missing_columns <- setdiff(required, names(xy))
  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "'xy' is missing required columns: %s.",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
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

  na_effort <- match.arg(na_effort)
  effort_names <- setdiff(names(xy), required)
  if (length(effort_names) == 0L) {
    stop("'xy' contains no grid-cell effort columns.", call. = FALSE)
  }
  non_numeric <- effort_names[!vapply(xy[effort_names], is.numeric, logical(1))]
  if (length(non_numeric) > 0L) {
    stop(
      sprintf(
        "Grid-cell effort columns must be numeric: %s.",
        paste(non_numeric, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  if (!is.numeric(xy$Kg) || any(!is.finite(xy$Kg)) || any(xy$Kg < 0)) {
    stop("'Kg' must contain finite, non-negative numeric values.", call. = FALSE)
  }

  nnls_x <- data.matrix(xy[effort_names])
  missing_effort <- !is.finite(nnls_x)
  if (any(missing_effort)) {
    if (identical(na_effort, "error")) {
      stop("Grid-cell effort contains missing or infinite values.", call. = FALSE)
    }
    nnls_x[missing_effort] <- 0
  }
  if (any(nnls_x < 0)) {
    stop("Grid-cell effort cannot contain negative values.", call. = FALSE)
  }

  column_totals <- colSums(nnls_x)
  eligible <- column_totals > min_column_sum
  if (!any(eligible)) {
    stop("No grid cell has enough positive effort for LPUE estimation.", call. = FALSE)
  }

  positive_totals <- column_totals[eligible]
  quantile_threshold <- stats::quantile(
    positive_totals,
    probs = column_quantile,
    names = FALSE,
    type = 7
  )
  keep <- eligible & column_totals >= quantile_threshold
  nnls_x <- nnls_x[, keep, drop = FALSE]

  if (nrow(nnls_x) < 1L || ncol(nnls_x) < 1L) {
    stop("No observations or grid cells remain for LPUE estimation.", call. = FALSE)
  }

  fit <- nnls::nnls(nnls_x, xy$Kg)

  list(
    lpue = data.frame(
      id_grid = colnames(nnls_x),
      lpue = as.numeric(fit$x),
      stringsAsFactors = FALSE
    ),
    df_check = data.frame(
      obs = xy$Kg,
      fitted = as.numeric(fit$fitted)
    )
  )
}
