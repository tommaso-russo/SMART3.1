# Extract the single finite numeric value occurring within a group.
one_numeric_value <- function(x, field_name) {
  values <- unique(x[!is.na(x)])

  if (
    length(values) != 1L ||
      !is.numeric(values) ||
      !is.finite(values)
  ) {
    stop(
      "Field '",
      field_name,
      "' is not constant and finite within an economic aggregation group.",
      call. = FALSE
    )
  }

  as.numeric(values)
}
