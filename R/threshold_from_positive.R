threshold_from_positive <- function(x) {
  positive <- x[is.finite(x) & x > 0]
  if (length(positive) < 2L) return(NA_real_)
  
  10 ^ as.numeric(stats::quantile(
    log10(positive),
    probs = quantile_Logit,
    names = FALSE,
    type = 7
  ))
}