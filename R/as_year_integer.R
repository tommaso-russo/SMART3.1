as_year_integer <- function(x, label) {
  out <- as_numeric_strict(x, label)
  invalid <- !is.na(out) & out != floor(out)
  
  if (any(invalid)) {
    stop("Non-integer years in ", label, ".", call. = FALSE)
  }
  
  as.integer(out)
}