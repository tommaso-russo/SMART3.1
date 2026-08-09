# Return a sum only when every value is observed and finite.
#
# This internal helper prevents partial totals from being silently interpreted
# as complete economic quantities.
sum_require_complete <- function(x) {
  if (length(x) == 0L || anyNA(x) || any(!is.finite(x))) {
    return(NA_real_)
  }

  sum(x)
}
