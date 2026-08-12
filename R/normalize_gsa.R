normalize_gsa <- function(x, strict = TRUE) {
  original <- x
  cleaned <- clean_code(x)
  token <- sub("^GSA[[:space:]_-]*", "", cleaned)
  token <- gsub(",", ".", token, fixed = TRUE)
  token <- gsub("[[:space:]_-]+", "", token)
  
  out <- rep(NA_character_, length(token))
  
  integer_format <- !is.na(token) & grepl("^[0-9]+$", token)
  if (any(integer_format)) {
    value <- suppressWarnings(as.integer(token[integer_format]))
    out[integer_format] <- ifelse(
      value < 100L,
      sprintf("GSA%02d", value),
      paste0("GSA", value)
    )
  }
  
  decimal_format <- !is.na(token) & grepl("^[0-9]+\\.[0-9]+$", token)
  if (any(decimal_format)) {
    parts <- strsplit(token[decimal_format], "\\.")
    out[decimal_format] <- vapply(
      parts,
      function(z) {
        paste0(
          "GSA", sprintf("%02d", as.integer(z[1L])),
          paste0(z[-1L], collapse = "")
        )
      },
      character(1)
    )
  }
  
  missing <- is.na(original) | !nzchar(trimws(as.character(original)))
  invalid <- !missing & is.na(out)
  
  if (strict && any(invalid)) {
    stop(
      "Unrecognised GSA values. Examples: ",
      paste(utils::head(unique(original[invalid]), 10L), collapse = ", "),
      call. = FALSE
    )
  }
  
  out
}