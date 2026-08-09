# Estimate modelled landings weight and gross value of landings.
#
# Expected units:
#   effort = fishing hours x vessel length overall in metres
#   lpue   = kg / (fishing hour x metre)
#   Price  = EUR / kg
#
# A zero price is retained as a valid observation. Only NA denotes an
# unavailable price.
add_WLV <- function(x) {
  if (!is.data.frame(x)) {
    stop(
      "'x' must be a data frame.",
      call. = FALSE
    )
  }

  required_columns <- c(
    "effort",
    "lpue",
    "Price"
  )

  missing_columns <- setdiff(
    required_columns,
    names(x)
  )

  if (length(missing_columns) > 0L) {
    stop(
      "Missing columns in 'x': ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  for (field in required_columns) {
    values <- x[[field]]

    if (!is.numeric(values)) {
      stop(
        "Column '",
        field,
        "' must be numeric.",
        call. = FALSE
      )
    }

    observed_values <- values[!is.na(values)]

    if (
      any(!is.finite(observed_values)) ||
        any(observed_values < 0)
    ) {
      stop(
        "Column '",
        field,
        "' contains non-finite or negative values.",
        call. = FALSE
      )
    }
  }

  x %>%
    dplyr::mutate(
      W = dplyr::if_else(
        !is.na(.data$effort) & !is.na(.data$lpue),
        .data$effort * .data$lpue,
        NA_real_
      ),

      price_available = !is.na(.data$Price),

      GVL = dplyr::if_else(
        !is.na(.data$W) & .data$price_available,
        .data$W * .data$Price,
        NA_real_
      )
    )
}
