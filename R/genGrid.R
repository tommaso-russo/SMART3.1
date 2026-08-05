#' Generate a regular analysis grid for a case-study area
#'
#' The grid is created in a projected CRS so that `cellsizekm` is interpreted
#' in kilometres. Bathymetry is sampled at cell centroids and cells deeper
#' than `thr_depth` (or on land) are removed.
#'
#' @param cellsizekm Positive grid-cell side length in kilometres.
#' @param CS_buffer An `sf` polygon or multipolygon defining the study area.
#' @param crs CRS of the returned objects. Defaults to EPSG:4326.
#' @param bathy A bathymetric matrix accepted by `marmap::get.depth()`.
#' @param thr_depth Maximum retained depth in metres, expressed as a positive
#'   number. This argument is required to avoid reliance on a global variable.
#' @param grid_crs Optional projected CRS used to construct the grid. If `NULL`,
#'   the CRS of `CS_buffer` is used when projected; otherwise a local UTM CRS is
#'   selected from the study-area centroid.
#' @param bathy_crs CRS used by the bathymetric coordinates. Defaults to
#'   EPSG:4326, as expected by standard `marmap` bathymetry.
#'
#' @return A named list containing `grid_sf`, `grid_centroid`, `bbox_grid`, and
#'   `grid_CS`. `grid_CS` is the intersecting grid before depth filtering.
#' @export
genGrid <- function(cellsizekm,
                    CS_buffer,
                    crs = 4326,
                    bathy,
                    thr_depth = NULL,
                    grid_crs = NULL,
                    bathy_crs = 4326) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("Package 'sf' is required by genGrid().", call. = FALSE)
  }
  if (!requireNamespace("marmap", quietly = TRUE)) {
    stop("Package 'marmap' is required by genGrid().", call. = FALSE)
  }

  if (!inherits(CS_buffer, "sf") || nrow(CS_buffer) == 0L) {
    stop("'CS_buffer' must be a non-empty sf object.", call. = FALSE)
  }
  if (is.na(sf::st_crs(CS_buffer))) {
    stop("'CS_buffer' must have a valid CRS.", call. = FALSE)
  }
  if (!is.numeric(cellsizekm) || length(cellsizekm) != 1L ||
      !is.finite(cellsizekm) || cellsizekm <= 0) {
    stop("'cellsizekm' must be one positive number.", call. = FALSE)
  }
  if (is.null(thr_depth)) {
    stop("'thr_depth' must be supplied explicitly in metres.", call. = FALSE)
  }
  if (!is.numeric(thr_depth) || length(thr_depth) != 1L ||
      !is.finite(thr_depth) || thr_depth < 0) {
    stop("'thr_depth' must be one non-negative finite number.", call. = FALSE)
  }

  output_crs <- sf::st_crs(crs)
  if (is.na(output_crs)) {
    stop("'crs' must identify a valid output CRS.", call. = FALSE)
  }

  area <- sf::st_make_valid(CS_buffer)
  area <- sf::st_collection_extract(area, "POLYGON", warn = FALSE)
  if (nrow(area) == 0L || all(sf::st_is_empty(area))) {
    stop("'CS_buffer' contains no usable polygon geometry.", call. = FALSE)
  }

  if (is.null(grid_crs)) {
    area_crs <- sf::st_crs(area)
    if (!isTRUE(sf::st_is_longlat(area))) {
      working_crs <- area_crs
    } else {
      area_ll <- sf::st_transform(area, 4326)
      centre <- sf::st_coordinates(
        sf::st_centroid(sf::st_union(area_ll))
      )[1L, ]
      utm_zone <- floor((centre[["X"]] + 180) / 6) + 1
      utm_zone <- max(1, min(60, utm_zone))
      epsg <- if (centre[["Y"]] >= 0) 32600 + utm_zone else 32700 + utm_zone
      working_crs <- sf::st_crs(epsg)
    }
  } else {
    working_crs <- sf::st_crs(grid_crs)
    if (is.na(working_crs) || isTRUE(working_crs$IsGeographic)) {
      stop("'grid_crs' must identify a projected CRS.", call. = FALSE)
    }
  }

  area_projected <- sf::st_transform(area, working_crs)
  grid_geometry <- sf::st_make_grid(
    area_projected,
    cellsize = cellsizekm * 1000,
    what = "polygons",
    square = TRUE
  )
  keep <- lengths(sf::st_intersects(grid_geometry, area_projected)) > 0L
  grid_projected <- sf::st_sf(
    id_grid = as.character(seq_len(sum(keep))),
    geometry = grid_geometry[keep]
  )
  if (nrow(grid_projected) == 0L) {
    stop("No grid cells intersect 'CS_buffer'.", call. = FALSE)
  }

  centroids_projected <- sf::st_centroid(grid_projected)
  centroids_bathy <- sf::st_transform(centroids_projected, bathy_crs)
  xy <- sf::st_coordinates(centroids_bathy)[, c("X", "Y"), drop = FALSE]
  sampled <- marmap::get.depth(mat = bathy, x = xy, locator = FALSE)
  if (!"depth" %in% names(sampled) || nrow(sampled) != nrow(grid_projected)) {
    stop("Bathymetry sampling did not return one depth per grid cell.", call. = FALSE)
  }

  grid_projected$depth <- -as.numeric(sampled$depth)
  grid_CS <- sf::st_transform(grid_projected, output_crs)

  retain <- is.finite(grid_projected$depth) &
    grid_projected$depth >= 0 &
    grid_projected$depth <= thr_depth
  grid_projected <- grid_projected[retain, , drop = FALSE]
  if (nrow(grid_projected) == 0L) {
    stop("No grid cells remain after bathymetric filtering.", call. = FALSE)
  }

  grid_sf <- sf::st_transform(grid_projected, output_crs)
  grid_centroid <- sf::st_transform(
    sf::st_centroid(grid_projected),
    output_crs
  )
  bbox_grid <- data.frame(sf::st_bbox(grid_sf))

  list(
    grid_sf = grid_sf,
    grid_centroid = grid_centroid,
    bbox_grid = bbox_grid,
    grid_CS = grid_CS
  )
}
