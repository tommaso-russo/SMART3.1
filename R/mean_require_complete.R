# Return a mean only when every value is observed and finite.
#
# This internal helper is used for comparisons based on complete vessel-year
# records and deliberately does not remove missing values.
mean_require_complete <- function(x) {
  if (length(x) == 0L || anyNA(x) || any(!is.finite(x))) {
    return(NA_real_)
  }

  mean(x)
}
