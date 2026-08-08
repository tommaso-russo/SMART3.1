#' Classify target and non-target vessel-month observations
#'
#' Fits either a binomial GLM or a classification tree to distinguish target
#' observations (`Lit > thrB`) from non-target observations using spatial
#' effort predictors. The historical value `method = "rf"` is retained as an
#' alias for `"rpart"`; it does not fit a random forest.
#'
#' @param Lit Numeric vector of landed biomass in kilograms.
#' @param X Numeric data frame or matrix of effort by grid cell.
#' @param thrB Biomass threshold separating target from non-target records.
#' @param ptrain Percentage of each class assigned to training.
#' @param ptest Percentage of each class assigned to testing.
#' @param method One of `"binomial"`, `"rpart"`, or the legacy alias `"rf"`.
#' @param lower_value Minimum total effort required for a predictor cell.
#' @param seed Optional integer random seed for a reproducible split.
#'
#' @return A list compatible with the historical function: classification
#'   accuracy (`confm`), Cohen's kappa (`CohenK`), the model refitted to all
#'   observations (`logit_f`), and excluded predictor names (`zeroFG`).
#' @export
getLogit <- function(Lit,
                     X,
                     thrB,
                     ptrain = 80,
                     ptest = 20,
                     method = "rf",
                     lower_value = 20,
                     seed = NULL) {
  if (!is.numeric(Lit) || length(Lit) < 1L || any(!is.finite(Lit)) ||
      any(Lit < 0)) {
    stop("'Lit' must contain finite, non-negative numeric values.", call. = FALSE)
  }
  if (!is.data.frame(X) && !is.matrix(X)) {
    stop("'X' must be a numeric data frame or matrix.", call. = FALSE)
  }
  X <- as.data.frame(X, check.names = FALSE)
  if (nrow(X) != length(Lit)) {
    stop("'Lit' and 'X' must contain the same number of observations.", call. = FALSE)
  }
  if (ncol(X) < 1L || any(!vapply(X, is.numeric, logical(1)))) {
    stop("Every column of 'X' must be numeric.", call. = FALSE)
  }
  if (any(!is.finite(as.matrix(X))) || any(as.matrix(X) < 0)) {
    stop("'X' must contain finite, non-negative effort values.", call. = FALSE)
  }
  if (!is.numeric(thrB) || length(thrB) != 1L || !is.finite(thrB) ||
      thrB < 0) {
    stop("'thrB' must be one non-negative finite number.", call. = FALSE)
  }
  percentages <- c(ptrain = ptrain, ptest = ptest)
  if (any(!is.finite(percentages)) || any(percentages <= 0) ||
      sum(percentages) > 100) {
    stop("'ptrain' and 'ptest' must be positive and sum to at most 100.",
         call. = FALSE)
  }
  if (!is.numeric(lower_value) || length(lower_value) != 1L ||
      !is.finite(lower_value) || lower_value < 0) {
    stop("'lower_value' must be one non-negative number.", call. = FALSE)
  }
  if (!is.null(seed)) {
    if (length(seed) != 1L || !is.numeric(seed) || !is.finite(seed)) {
      stop("'seed' must be NULL or one finite number.", call. = FALSE)
    }
    set.seed(as.integer(seed))
  }

  method <- match.arg(method, c("rf", "rpart", "binomial"))
  model_method <- if (identical(method, "rf")) "rpart" else method

  Litb <- as.integer(Lit > thrB)
  class_indices <- split(seq_along(Litb), Litb)
  if (length(class_indices) != 2L || any(lengths(class_indices) < 2L)) {
    stop(
      "Both target classes need at least two observations for train/test evaluation.",
      call. = FALSE
    )
  }

  column_totals <- colSums(X)
  zeroFG <- names(X)[column_totals < lower_value]
  keep <- column_totals >= lower_value
  X <- X[, keep, drop = FALSE]
  if (ncol(X) < 1L) {
    stop("No effort predictor meets 'lower_value'.", call. = FALSE)
  }

  # Formula-based models require syntactically valid, unique predictor names.
  names(X) <- make.names(names(X), unique = TRUE)

  split_one_class <- function(index) {
    shuffled <- sample(index, length(index), replace = FALSE)
    n_train <- max(1L, floor(length(index) * ptrain / 100))
    n_test <- max(1L, floor(length(index) * ptest / 100))
    if (n_train + n_test > length(index)) {
      n_train <- length(index) - n_test
    }
    list(
      train = shuffled[seq_len(n_train)],
      test = shuffled[n_train + seq_len(n_test)]
    )
  }

  split_indices <- lapply(class_indices, split_one_class)
  itrain <- unlist(lapply(split_indices, `[[`, "train"), use.names = FALSE)
  itest <- unlist(lapply(split_indices, `[[`, "test"), use.names = FALSE)

  model_data <- X
  model_data$Litb <- Litb

  if (identical(model_method, "binomial")) {
    training_fit <- stats::glm(
      Litb ~ .,
      family = stats::binomial(),
      data = model_data[itrain, , drop = FALSE]
    )
    probabilities <- stats::predict(
      training_fit,
      newdata = model_data[itest, , drop = FALSE],
      type = "response"
    )
    predicted <- as.integer(probabilities > 0.5)
    logit_f <- stats::glm(
      Litb ~ .,
      family = stats::binomial(),
      data = model_data
    )
  } else {
    if (!requireNamespace("rpart", quietly = TRUE)) {
      stop("Package 'rpart' is required for tree classification.", call. = FALSE)
    }
    tree_data <- model_data
    tree_data$Litb <- factor(tree_data$Litb, levels = c(0, 1))
    training_fit <- rpart::rpart(
      Litb ~ .,
      data = tree_data[itrain, , drop = FALSE],
      method = "class"
    )
    predicted <- as.integer(as.character(stats::predict(
      training_fit,
      newdata = tree_data[itest, , drop = FALSE],
      type = "class"
    )))
    logit_f <- rpart::rpart(
      Litb ~ .,
      data = tree_data,
      method = "class"
    )
  }

  observed <- Litb[itest]
  confusion <- table(
    predicted = factor(predicted, levels = c(0, 1)),
    observed = factor(observed, levels = c(0, 1))
  )
  agreement <- sum(diag(confusion)) / sum(confusion)
  row_margins <- rowSums(confusion) / sum(confusion)
  column_margins <- colSums(confusion) / sum(confusion)
  expected_agreement <- sum(row_margins * column_margins)
  cohen_k <- if (expected_agreement < 1) {
    (agreement - expected_agreement) / (1 - expected_agreement)
  } else {
    NA_real_
  }

  list(
    confm = 100 * agreement,
    CohenK = unname(cohen_k),
    logit_f = logit_f,
    zeroFG = zeroFG
  )
}
