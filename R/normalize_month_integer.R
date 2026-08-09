# Convert numeric, full-name or abbreviated months to integers from 1 to 12.
normalize_month_integer <- function(x) {
  raw <- trimws(as.character(x))
  out <- suppressWarnings(as.integer(raw))

  full_name_match <- match(
    tolower(raw),
    tolower(month.name)
  )

  abbreviation_match <- match(
    tolower(raw),
    tolower(month.abb)
  )

  out[is.na(out)] <- full_name_match[is.na(out)]
  out[is.na(out)] <- abbreviation_match[is.na(out)]

  if (anyNA(out) || any(out < 1L | out > 12L)) {
    stop(
      "Invalid month values were found.",
      call. = FALSE
    )
  }

  out
}
