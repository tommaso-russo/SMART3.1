empty_status <- function(
    year, gsa, species, gear, month = NA_integer_,
    stage, status, detail
) {
  tibble::tibble(
    YEAR = as.integer(year),
    GSA_code = as.character(gsa),
    Species = as.character(species),
    Gear = as.character(gear),
    MONTH = as.integer(month),
    stage = as.character(stage),
    status = as.character(status),
    detail = as.character(detail)
  )
}