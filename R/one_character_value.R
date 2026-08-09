# Extract the single non-empty character value occurring within a group.
one_character_value <- function(x, field_name) {
  values <- unique(trimws(as.character(x[!is.na(x)])))
  values <- values[nzchar(values)]

  if (length(values) != 1L) {
    stop(
      "Field '",
      field_name,
      "' is not constant within an economic aggregation group.",
      call. = FALSE
    )
  }

  values
}
