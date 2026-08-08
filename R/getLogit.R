# SMART3.1 definitive function version: 2026-08-08
# Compatible with SMART31_LPUE_estimation_chunk.R.

#' Classify target and non-target fishing observations
#'
#' Classifies fishing observations as target or non-target from their spatial
#' effort distribution. The observed class is defined by whether landed biomass
#' is greater than `thrB`. Model performance is evaluated on a stratified test
#' set, after which the model is refitted to all observations to provide the
#' probabilities and classes used by the LPUE workflow.
#'
#' @param Lit Numeric vector of landed biomass in kilograms.
#' @param X Numeric data frame or matrix containing one row per observation and
#'   one effort predictor per grid cell.
#' @param thrB Single non-negative biomass threshold in kilograms. Observations
#'   with `Lit > thrB` are classified as target observations.
#' @param ptrain Percentage of each observed class assigned to the training set.
#' @param ptest Percentage of each observed class assigned to the test set.
#'   Percentages may sum to less than 100; remaining observations are used only
#'   when the final model is fitted.
#' @param method Classification method. Use `"rpart"` for a classification tree
#'   or `"binomial"` for a binomial GLM. The historical value `"rf"` is accepted
#'   as a deprecated alias for `"rpart"`; it does not fit a random forest.
#' @param lower_value Minimum total effort required for a grid-cell predictor.
#' @param probability_cutoff Probability above which an observation is assigned
#'   to the target class.
#' @param seed Optional integer seed used for the stratified train/test split.
#'
#' @return A list containing:
#' \describe{
#'   \item{confm}{Historical percentage accuracy on the test set.}
#'   \item{CohenK}{Cohen's kappa on the test set.}
#'   \item{logit_f}{Classification model fitted to all observations.}
#'   \item{zeroFG}{Historical vector of excluded predictor names.}
#'   \item{predictions}{Row-level observed classes, fitted probabilities and
#'     predicted classes from the model fitted to all observations.}
#'   \item{test_predictions}{Observed classes, probabilities and predicted
#'     classes for the independent test set.}
#'   \item{confusion_matrix}{Test-set confusion matrix.}
#'   \item{performance}{One-row data frame of test-set performance metrics.}
#'   \item{predictor_map}{Original predictor names, model-safe names, total
#'     effort and retention status.}
#'   \item{training_rows,test_rows,unused_rows}{Row indices for the split.}
#'   \item{settings}{Effective classification settings.}
#' }
#'
#' @examples
#' effort <- data.frame(
#'   cell_1 = c(10, 8, 0, 0, 7, 1, 0, 9),
#'   cell_2 = c(0, 1, 9, 8, 0, 7, 10, 0)
#' )
#' biomass <- c(20, 18, 0, 1, 15, 2, 0, 17)
#' result <- getLogit(
#'   Lit = biomass,
#'   X = effort,
#'   thrB = 5,
#'   ptrain = 75,
#'   ptest = 25,
#'   method = "rpart",
#'   lower_value = 0,
#'   seed = 1
#' )
#' result$predictions
#'
#' @export
getLogit <- function(Lit,
                     X,
                     thrB,
                     ptrain = 80,
                     ptest = 20,
                     method = "rpart",
                     lower_value = 20,
                     probability_cutoff = 0.5,
                     seed = NULL) {
  if (!is.numeric(Lit) || length(Lit) < 1L || any(!is.finite(Lit)) ||
      any(Lit < 0)) {
    stop(
      "'Lit' must contain finite, non-negative numeric values.",
      call. = FALSE
    )
  }

  if (!is.data.frame(X) && !is.matrix(X)) {
    stop("'X' must be a numeric data frame or matrix.", call. = FALSE)
  }

  X <- as.data.frame(X, check.names = FALSE)

  if (nrow(X) != length(Lit)) {
    stop(
      "'Lit' and 'X' must contain the same number of observations.",
      call. = FALSE
    )
  }

  if (ncol(X) < 1L || any(!vapply(X, is.numeric, logical(1)))) {
    stop("Every column of 'X' must be numeric.", call. = FALSE)
  }

  effort_matrix <- data.matrix(X)

  if (any(!is.finite(effort_matrix)) || any(effort_matrix < 0)) {
    stop(
      "'X' must contain finite, non-negative effort values.",
      call. = FALSE
    )
  }

  if (!is.numeric(thrB) || length(thrB) != 1L || !is.finite(thrB) ||
      thrB < 0) {
    stop("'thrB' must be one non-negative finite number.", call. = FALSE)
  }

  percentages <- c(ptrain = ptrain, ptest = ptest)

  if (any(lengths(list(ptrain, ptest)) != 1L) ||
      !is.numeric(percentages) || any(!is.finite(percentages)) ||
      any(percentages <= 0) || sum(percentages) > 100) {
    stop(
      "'ptrain' and 'ptest' must be positive finite percentages whose sum is at most 100.",
      call. = FALSE
    )
  }

  if (!is.numeric(lower_value) || length(lower_value) != 1L ||
      !is.finite(lower_value) || lower_value < 0) {
    stop("'lower_value' must be one non-negative number.", call. = FALSE)
  }

  if (!is.numeric(probability_cutoff) || length(probability_cutoff) != 1L ||
      !is.finite(probability_cutoff) || probability_cutoff <= 0 ||
      probability_cutoff >= 1) {
    stop("'probability_cutoff' must be strictly between 0 and 1.", call. = FALSE)
  }

  if (!is.null(seed) &&
      (!is.numeric(seed) || length(seed) != 1L || !is.finite(seed))) {
    stop("'seed' must be NULL or one finite numeric value.", call. = FALSE)
  }

  method <- match.arg(method, c("rpart", "binomial", "rf"))

  if (identical(method, "rf")) {
    warning(
      "method = \"rf\" is a deprecated alias for \"rpart\"; no random forest is fitted.",
      call. = FALSE
    )
    method <- "rpart"
  }

  observed_class <- as.integer(Lit > thrB)
  class_counts <- table(factor(observed_class, levels = c(0, 1)))

  if (any(class_counts < 2L)) {
    stop(
      paste0(
        "Both observed classes require at least two records. Class counts: ",
        "non-target = ", class_counts[[1L]],
        ", target = ", class_counts[[2L]], "."
      ),
      call. = FALSE
    )
  }

  original_names <- names(X)

  if (is.null(original_names)) {
    original_names <- paste0("predictor_", seq_len(ncol(X)))
  }

  invalid_names <- is.na(original_names) | !nzchar(original_names)
  original_names[invalid_names] <- paste0("predictor_", which(invalid_names))
  original_names <- make.unique(original_names, sep = "_")
  names(X) <- original_names

  column_totals <- colSums(effort_matrix)
  column_variances <- vapply(X, stats::var, numeric(1))
  meets_effort_threshold <- column_totals >= lower_value
  has_variation <- is.finite(column_variances) & column_variances > 0
  retained <- meets_effort_threshold & has_variation

  predictor_map <- data.frame(
    original_name = original_names,
    model_name = make.names(original_names, unique = TRUE),
    total_effort = as.numeric(column_totals),
    variance = as.numeric(column_variances),
    retained = retained,
    exclusion_reason = ifelse(
      retained,
      NA_character_,
      ifelse(
        !meets_effort_threshold,
        "total effort below lower_value",
        "zero variance"
      )
    ),
    stringsAsFactors = FALSE
  )

  if (!any(retained)) {
    stop(
      "No varying effort predictor meets 'lower_value'.",
      call. = FALSE
    )
  }

  X_model <- X[, retained, drop = FALSE]
  names(X_model) <- predictor_map$model_name[retained]
  excluded_predictors <- predictor_map$original_name[!retained]

  split_one_class <- function(indices) {
    shuffled <- sample(indices, length(indices), replace = FALSE)
    n_train <- max(1L, floor(length(indices) * ptrain / 100))
    n_test <- max(1L, floor(length(indices) * ptest / 100))

    if (n_train + n_test > length(indices)) {
      n_train <- length(indices) - n_test
    }

    list(
      train = shuffled[seq_len(n_train)],
      test = shuffled[n_train + seq_len(n_test)]
    )
  }

  if (!is.null(seed)) {
    had_random_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)

    if (had_random_seed) {
      previous_random_seed <- get(".Random.seed", envir = .GlobalEnv)
    }

    on.exit({
      if (had_random_seed) {
        assign(".Random.seed", previous_random_seed, envir = .GlobalEnv)
      } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    }, add = TRUE)

    set.seed(as.integer(seed))
  }

  class_indices <- split(seq_along(observed_class), observed_class)
  split_indices <- lapply(class_indices, split_one_class)
  training_rows <- sort(unlist(
    lapply(split_indices, `[[`, "train"),
    use.names = FALSE
  ))
  test_rows <- sort(unlist(
    lapply(split_indices, `[[`, "test"),
    use.names = FALSE
  ))
  unused_rows <- setdiff(seq_along(observed_class), c(training_rows, test_rows))

  model_data <- X_model
  model_data$target_class <- observed_class

  fit_model <- function(data, rows) {
    if (identical(method, "binomial")) {
      return(stats::glm(
        target_class ~ .,
        family = stats::binomial(),
        data = data[rows, , drop = FALSE]
      ))
    }

    if (!requireNamespace("rpart", quietly = TRUE)) {
      stop(
        "Package 'rpart' is required when method = \"rpart\".",
        call. = FALSE
      )
    }

    tree_data <- data
    tree_data$target_class <- factor(
      tree_data$target_class,
      levels = c(0, 1)
    )

    rpart::rpart(
      target_class ~ .,
      data = tree_data[rows, , drop = FALSE],
      method = "class"
    )
  }

  predict_probability <- function(model, newdata) {
    if (identical(method, "binomial")) {
      return(as.numeric(stats::predict(
        model,
        newdata = newdata,
        type = "response"
      )))
    }

    probabilities <- stats::predict(
      model,
      newdata = newdata,
      type = "prob"
    )

    if ("1" %in% colnames(probabilities)) {
      return(as.numeric(probabilities[, "1"]))
    }

    rep(0, nrow(newdata))
  }

  training_model <- fit_model(model_data, training_rows)
  test_probability <- predict_probability(
    training_model,
    model_data[test_rows, , drop = FALSE]
  )
  test_class <- as.integer(test_probability >= probability_cutoff)
  test_observed <- observed_class[test_rows]

  confusion_matrix <- table(
    predicted = factor(test_class, levels = c(0, 1)),
    observed = factor(test_observed, levels = c(0, 1))
  )

  true_negative <- confusion_matrix["0", "0"]
  false_negative <- confusion_matrix["0", "1"]
  false_positive <- confusion_matrix["1", "0"]
  true_positive <- confusion_matrix["1", "1"]
  n_test <- sum(confusion_matrix)
  accuracy <- (true_positive + true_negative) / n_test
  sensitivity <- true_positive / (true_positive + false_negative)
  specificity <- true_negative / (true_negative + false_positive)
  balanced_accuracy <- mean(c(sensitivity, specificity))
  predicted_positive_rate <- (true_positive + false_positive) / n_test
  observed_positive_rate <- (true_positive + false_negative) / n_test
  expected_agreement <-
    predicted_positive_rate * observed_positive_rate +
    (1 - predicted_positive_rate) * (1 - observed_positive_rate)
  cohen_k <- if (expected_agreement < 1) {
    (accuracy - expected_agreement) / (1 - expected_agreement)
  } else {
    NA_real_
  }

  final_model <- fit_model(model_data, seq_len(nrow(model_data)))
  fitted_probability <- predict_probability(final_model, model_data)
  fitted_class <- as.integer(fitted_probability >= probability_cutoff)
  split_role <- rep("unused", length(Lit))
  split_role[training_rows] <- "training"
  split_role[test_rows] <- "test"

  predictions <- data.frame(
    row_id = seq_along(Lit),
    biomass_kg = as.numeric(Lit),
    observed_class = observed_class,
    predicted_probability = fitted_probability,
    predicted_class = fitted_class,
    split_role = split_role,
    stringsAsFactors = FALSE
  )

  test_predictions <- data.frame(
    row_id = test_rows,
    biomass_kg = as.numeric(Lit[test_rows]),
    observed_class = test_observed,
    predicted_probability = test_probability,
    predicted_class = test_class,
    stringsAsFactors = FALSE
  )

  performance <- data.frame(
    n_observations = length(Lit),
    n_training = length(training_rows),
    n_test = length(test_rows),
    n_unused = length(unused_rows),
    accuracy = as.numeric(accuracy),
    balanced_accuracy = as.numeric(balanced_accuracy),
    sensitivity = as.numeric(sensitivity),
    specificity = as.numeric(specificity),
    CohenK = as.numeric(cohen_k),
    stringsAsFactors = FALSE
  )

  list(
    confm = 100 * as.numeric(accuracy),
    CohenK = as.numeric(cohen_k),
    logit_f = final_model,
    zeroFG = excluded_predictors,
    predictions = predictions,
    test_predictions = test_predictions,
    confusion_matrix = confusion_matrix,
    performance = performance,
    predictor_map = predictor_map,
    training_rows = training_rows,
    test_rows = test_rows,
    unused_rows = unused_rows,
    settings = list(
      biomass_threshold = thrB,
      probability_cutoff = probability_cutoff,
      training_percentage = ptrain,
      test_percentage = ptest,
      method = method,
      lower_value = lower_value,
      seed = seed
    )
  )
}

attr(getLogit, "smart31_version") <- "2026-08-08"
