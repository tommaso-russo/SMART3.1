#' Assign fishing-effort points to grid cells
#'
#' Assigns each effort point to one cell of an analysis grid. Points outside the
#' grid are removed, matching the behaviour of the legacy SMART workflow. If a
#' point intersects more than one cell because it lies exactly on a shared
#' boundary, the cell with the first alphanumeric `id_grid` is selected. This
#' makes the result deterministic and prevents duplicated effort records.
#'
#' @param effort_sf An `sf` object containing point geometries.
#' @param grid_sf An `sf` polygon grid containing a unique, non-missing
#'   `id_grid` column.
#'
#' @return The retained rows of `effort_sf`, in their original order, with a
#'   character `id_grid` column. The output uses the CRS of `grid_sf`.
#' @export
griddingEffort <- function(effort_sf, grid_sf) {
  if (!inherits(effort_sf, "sf")) {
    stop("`effort_sf` must be an sf object.", call. = FALSE)
  }

  if (!inherits(grid_sf, "sf")) {
    stop("`grid_sf` must be an sf object.", call. = FALSE)
  }

  if (!"id_grid" %in% names(grid_sf)) {
    stop("`grid_sf` must contain an `id_grid` column.", call. = FALSE)
  }

  if (is.na(sf::st_crs(effort_sf))) {
    stop("`effort_sf` must have a defined CRS.", call. = FALSE)
  }

  if (is.na(sf::st_crs(grid_sf))) {
    stop("`grid_sf` must have a defined CRS.", call. = FALSE)
  }

  grid_ids <- as.character(grid_sf$id_grid)
  if (anyNA(grid_ids) || any(!nzchar(grid_ids))) {
    stop("`grid_sf$id_grid` must not contain missing or empty values.", call. = FALSE)
  }

  if (anyDuplicated(grid_ids)) {
    stop("`grid_sf$id_grid` must contain unique values.", call. = FALSE)
  }

  effort_geometry_type <- as.character(sf::st_geometry_type(effort_sf))
  if (length(effort_geometry_type) && any(effort_geometry_type != "POINT")) {
    stop("`effort_sf` must contain only POINT geometries.", call. = FALSE)
  }

  grid_geometry_type <- as.character(sf::st_geometry_type(grid_sf))
  valid_grid_types <- c("POLYGON", "MULTIPOLYGON")
  if (length(grid_geometry_type) &&
      any(!grid_geometry_type %in% valid_grid_types)) {
    stop(
      "`grid_sf` must contain only POLYGON or MULTIPOLYGON geometries.",
      call. = FALSE
    )
  }

  if (any(sf::st_is_empty(effort_sf))) {
    stop("`effort_sf` contains empty geometries.", call. = FALSE)
  }

  if (any(sf::st_is_empty(grid_sf))) {
    stop("`grid_sf` contains empty geometries.", call. = FALSE)
  }

  if (!isTRUE(sf::st_crs(effort_sf) == sf::st_crs(grid_sf))) {
    effort_sf <- sf::st_transform(effort_sf, sf::st_crs(grid_sf))
  }

  intersections <- sf::st_intersects(effort_sf, grid_sf, sparse = TRUE)

  assigned_id <- vapply(
    intersections,
    function(cell_index) {
      if (!length(cell_index)) {
        return(NA_character_)
      }

      candidate_ids <- grid_ids[cell_index]
      sort(candidate_ids, method = "radix")[1L]
    },
    character(1L)
  )

  effort_sf$id_grid <- assigned_id
  effort_sf[!is.na(effort_sf$id_grid), , drop = FALSE]
}
