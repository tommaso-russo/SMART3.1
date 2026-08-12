clean_code <- function(x) {
  original <- x
  out <- toupper(trimws(as.character(x)))
  out[is.na(original) | !nzchar(out)] <- NA_character_
  out
}