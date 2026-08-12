as_numeric_strict <- function(x, label) {
  original <- if (is.factor(x)) as.character(x) else x
  out <- suppressWarnings(as.numeric(original))
  invalid <- !is.na(original) & nzchar(trimws(as.character(original))) &
    !is.finite(out)
  
  if (any(invalid)) {
    stop(
      "Non-numeric values in ", label, ". Examples: ",
      paste(utils::head(unique(original[invalid]), 10L), collapse = ", "),
      call. = FALSE
    )
  }
  out
}