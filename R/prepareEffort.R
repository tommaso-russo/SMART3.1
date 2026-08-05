#' Prepare fishing-effort records for spatial processing
#'
#' Filters effort records to the requested GSAs and gears, standardises key
#' fields, converts longitude/latitude coordinates to an `sf` point layer, and
#' transforms the points to the CRS used by the analysis grid.
#'
#' @param effort A data frame containing at least `Metier`, `MONTH`, `YEAR`,
#'   `CFR`, `GSA`, `LON`, and `LAT`.
#' @param grid_sf An `sf` grid with a defined coordinate reference system.
#' @param CS_gsas Character vector of GSAs to retain.
#' @param gears_to_submit Character vector of three-letter gear codes to retain.
#' @param input_crs CRS of the input `LON`/`LAT` coordinates. Defaults to EPSG
#'   4326 (WGS 84).
#'
#' @return An `sf` point object in the CRS of `grid_sf`. `MONTH` is an ordered
#'   factor with English month names; `YEAR` and `CFR` are character vectors.
#' @export
prepareEffort <- function(
    effort,
    grid_sf,
    CS_gsas,
    gears_to_submit,
    input_crs = 4326
) {
  required_columns <- c(
    "Metier", "MONTH", "YEAR", "CFR", "GSA", "LON", "LAT"
  )

  if (!is.data.frame(effort)) {
    stop("`effort` must be a data frame.", call. = FALSE)
  }

  if (!inherits(grid_sf, "sf")) {
    stop("`grid_sf` must be an sf object.", call. = FALSE)
  }

  missing_columns <- setdiff(required_columns, names(effort))
  if (length(missing_columns)) {
    stop(
      "`effort` is missing required columns: ",
      paste(missing_columns, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  if (is.na(sf::st_crs(grid_sf))) {
    stop("`grid_sf` must have a defined CRS.", call. = FALSE)
  }

  input_crs <- sf::st_crs(input_crs)
  if (is.na(input_crs)) {
    stop("`input_crs` must identify a valid CRS.", call. = FALSE)
  }

  if (!is.character(CS_gsas) || !length(CS_gsas) || anyNA(CS_gsas)) {
    stop("`CS_gsas` must be a non-empty character vector without NA.", call. = FALSE)
  }

  if (!is.character(gears_to_submit) ||
      !length(gears_to_submit) ||
      anyNA(gears_to_submit)) {
    stop(
      "`gears_to_submit` must be a non-empty character vector without NA.",
      call. = FALSE
    )
  }

  effort <- as.data.frame(effort)
  effort$Gear <- substr(as.character(effort$Metier), 1L, 3L)

  keep <- !is.na(effort$GSA) &
    !is.na(effort$Gear) &
    effort$GSA %in% CS_gsas &
    effort$Gear %in% gears_to_submit
  effort <- effort[keep, , drop = FALSE]

  month_number <- suppressWarnings(as.integer(as.character(effort$MONTH)))
  invalid_month <- is.na(month_number) | month_number < 1L | month_number > 12L
  if (any(invalid_month)) {
    bad_values <- unique(as.character(effort$MONTH[invalid_month]))
    stop(
      "Retained effort records contain invalid `MONTH` values: ",
      paste(utils::head(bad_values, 10L), collapse = ", "),
      ". Expected integers from 1 to 12.",
      call. = FALSE
    )
  }

  longitude <- suppressWarnings(as.numeric(as.character(effort$LON)))
  latitude <- suppressWarnings(as.numeric(as.character(effort$LAT)))
  invalid_coordinates <- !is.finite(longitude) | !is.finite(latitude)
  if (any(invalid_coordinates)) {
    stop(
      sum(invalid_coordinates),
      " retained effort record(s) have missing or non-finite coordinates.",
      call. = FALSE
    )
  }

  effort$LON <- longitude
  effort$LAT <- latitude
  effort$MONTH <- factor(
    month.name[month_number],
    levels = month.name,
    ordered = TRUE
  )
  effort$YEAR <- as.character(effort$YEAR)
  effort$CFR <- as.character(effort$CFR)

  effort_sf <- sf::st_as_sf(
    effort,
    coords = c("LON", "LAT"),
    crs = input_crs,
    remove = TRUE
  )

  sf::st_transform(effort_sf, sf::st_crs(grid_sf))
}
