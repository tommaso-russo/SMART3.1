as_month_integer <- function(x, label) {
  original <- if (is.factor(x)) as.character(x) else x
  raw <- trimws(as.character(original))
  missing <- is.na(original) | !nzchar(raw)
  out <- suppressWarnings(as.integer(raw))
  
  unresolved <- !missing & (is.na(out) | !out %in% seq_len(12L))
  
  if (any(unresolved)) {
    labels <- tolower(raw[unresolved])
    labels[labels == "sept"] <- "sep"
    full_match <- match(labels, tolower(month.name))
    short_match <- match(labels, tolower(month.abb))
    full_match[is.na(full_match)] <- short_match[is.na(full_match)]
    out[unresolved] <- full_match
  }
  
  out[missing] <- NA_integer_
  invalid <- !missing & (is.na(out) | !out %in% seq_len(12L))
  
  if (any(invalid)) {
    stop(
      "Invalid months in ", label, ". Examples: ",
      paste(utils::head(unique(raw[invalid]), 10L), collapse = ", "),
      call. = FALSE
    )
  }
  out
}