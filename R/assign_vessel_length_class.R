# Assign EU vessel-length classes from length overall in metres.
assign_vessel_length_class <- function(loa_m) {
  if (
    !is.numeric(loa_m) ||
      anyNA(loa_m) ||
      any(!is.finite(loa_m)) ||
      any(loa_m <= 0)
  ) {
    stop(
      "'loa_m' must contain finite positive values.",
      call. = FALSE
    )
  }

  vessel_length_levels <- c(
    "VL0006",
    "VL0612",
    "VL1215",
    "VL1518",
    "VL1824",
    "VL2440",
    "VL40XX"
  )

  factor(
    cut(
      loa_m,
      breaks = c(0, 6, 12, 15, 18, 24, 40, Inf),
      labels = vessel_length_levels,
      right = FALSE,
      include.lowest = TRUE
    ),
    levels = vessel_length_levels
  )
}
