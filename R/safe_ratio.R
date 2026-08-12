safe_ratio <- function(numerator, denominator) {
  out <- rep(NA_real_, max(length(numerator), length(denominator)))
  numerator <- rep(numerator, length.out = length(out))
  denominator <- rep(denominator, length.out = length(out))
  valid <- is.finite(numerator) & is.finite(denominator) & denominator > 0
  out[valid] <- numerator[valid] / denominator[valid]
  out
}