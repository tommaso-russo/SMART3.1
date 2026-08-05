#' Compute water-constrained distances from harbours to grid cells
#'
#' Distances are shortest paths through grid cells that share an edge, rather
#' than straight lines across land. Corner-only contacts are excluded. Edge
#' weights are centroid-to-centroid distances and the result is expressed in
#' kilometres.
#'
#' @param grid_centroid An `sf` point object with one row per grid cell.
#' @param grid_sf An `sf` polygon object containing a unique `id_grid` column.
#' @param harbs_df_sf An `sf` point object containing harbour names.
#' @param harbour_col Name of the harbour-name column. Defaults to `HARBOUR`.
#'
#' @return An `sf` object containing one copy of each grid cell per harbour.
#'   `layer` is the water-constrained distance in kilometres and `harb` is the
#'   harbour name. Unreachable cells have `NA` distance.
#' @export
gridDistance <- function(grid_centroid,
                         grid_sf,
                         harbs_df_sf,
                         harbour_col = "HARBOUR") {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("Package 'sf' is required by gridDistance().", call. = FALSE)
  }
  if (!requireNamespace("units", quietly = TRUE)) {
    stop("Package 'units' is required by gridDistance().", call. = FALSE)
  }

  objects <- list(
    grid_centroid = grid_centroid,
    grid_sf = grid_sf,
    harbs_df_sf = harbs_df_sf
  )
  invalid <- names(objects)[!vapply(objects, inherits, logical(1), what = "sf")]
  if (length(invalid)) {
    stop(
      sprintf("These inputs must be sf objects: %s.", paste(invalid, collapse = ", ")),
      call. = FALSE
    )
  }
  if (nrow(grid_sf) == 0L || nrow(grid_centroid) == 0L) {
    stop("The grid and its centroids must not be empty.", call. = FALSE)
  }
  if (nrow(grid_sf) != nrow(grid_centroid)) {
    stop("'grid_sf' and 'grid_centroid' must have the same number of rows.", call. = FALSE)
  }
  if (nrow(harbs_df_sf) == 0L) {
    stop("'harbs_df_sf' must contain at least one harbour.", call. = FALSE)
  }
  if (!"id_grid" %in% names(grid_sf)) {
    stop("'grid_sf' must contain an 'id_grid' column.", call. = FALSE)
  }
  if (anyNA(grid_sf$id_grid) || anyDuplicated(grid_sf$id_grid)) {
    stop("'grid_sf$id_grid' must be complete and unique.", call. = FALSE)
  }
  if (!harbour_col %in% names(harbs_df_sf)) {
    stop(sprintf("Harbour column '%s' was not found.", harbour_col), call. = FALSE)
  }
  if (anyNA(harbs_df_sf[[harbour_col]]) || any(!nzchar(as.character(harbs_df_sf[[harbour_col]])))) {
    stop("Harbour names must be complete and non-empty.", call. = FALSE)
  }
  if (any(vapply(objects, function(x) is.na(sf::st_crs(x)), logical(1)))) {
    stop("All spatial inputs must have a valid CRS.", call. = FALSE)
  }
  if (any(sf::st_is_empty(grid_sf)) || any(sf::st_is_empty(grid_centroid)) ||
      any(sf::st_is_empty(harbs_df_sf))) {
    stop("Spatial inputs must not contain empty geometries.", call. = FALSE)
  }

  grid_sf <- sf::st_make_valid(grid_sf)
  if ("id_grid" %in% names(grid_centroid)) {
    centroid_match <- match(grid_sf$id_grid, grid_centroid$id_grid)
    if (anyNA(centroid_match) || anyDuplicated(grid_centroid$id_grid)) {
      stop(
        "'grid_centroid$id_grid' must match the unique IDs in 'grid_sf'.",
        call. = FALSE
      )
    }
    grid_centroid <- grid_centroid[centroid_match, , drop = FALSE]
  }
  grid_centroid <- sf::st_transform(grid_centroid, sf::st_crs(grid_sf))
  harbours <- sf::st_transform(harbs_df_sf, sf::st_crs(grid_sf))

  geometry_types <- unique(as.character(sf::st_geometry_type(grid_centroid)))
  if (!all(geometry_types %in% c("POINT", "MULTIPOINT"))) {
    stop("'grid_centroid' must contain point geometries.", call. = FALSE)
  }

  # Rook contiguity prevents a route from crossing a land barrier through a
  # single corner shared by two otherwise disconnected water cells.
  neighbours <- sf::st_relate(grid_sf, pattern = "F***1****")
  from <- rep.int(seq_along(neighbours), lengths(neighbours))
  to <- unlist(neighbours, use.names = FALSE)
  retain_edge <- from < to
  from <- from[retain_edge]
  to <- to[retain_edge]
  if (!length(from)) {
    stop("The grid contains no adjacent cells.", call. = FALSE)
  }

  edge_distance <- sf::st_distance(
    grid_centroid[from, ],
    grid_centroid[to, ],
    by_element = TRUE
  )
  edge_km <- as.numeric(units::set_units(edge_distance, "km"))
  if (any(!is.finite(edge_km)) || any(edge_km <= 0)) {
    stop("Invalid distances were found between adjacent grid cells.", call. = FALSE)
  }

  adjacency <- vector("list", nrow(grid_sf))
  weights <- vector("list", nrow(grid_sf))
  for (edge in seq_along(from)) {
    i <- from[[edge]]
    j <- to[[edge]]
    adjacency[[i]] <- c(adjacency[[i]], j)
    weights[[i]] <- c(weights[[i]], edge_km[[edge]])
    adjacency[[j]] <- c(adjacency[[j]], i)
    weights[[j]] <- c(weights[[j]], edge_km[[edge]])
  }

  harbour_cells <- sf::st_intersects(harbours, grid_sf)
  source_cell <- integer(length(harbour_cells))
  for (i in seq_along(harbour_cells)) {
    candidates <- harbour_cells[[i]]
    if (!length(candidates)) {
      stop(
        sprintf("Harbour '%s' falls outside the analysis grid.", harbours[[harbour_col]][[i]]),
        call. = FALSE
      )
    }
    if (length(candidates) == 1L) {
      source_cell[[i]] <- candidates
    } else {
      candidate_distance <- sf::st_distance(
        harbours[i, ],
        grid_centroid[candidates, ],
        by_element = FALSE
      )
      source_cell[[i]] <- candidates[[which.min(as.numeric(candidate_distance))]]
    }
  }

  shortest_paths <- function(source, adjacency, weights) {
    n <- length(adjacency)
    distance <- rep(Inf, n)
    visited <- rep(FALSE, n)
    distance[[source]] <- 0

    heap_node <- integer(n)
    heap_value <- numeric(n)
    heap_size <- 1L
    heap_node[[1L]] <- source
    heap_value[[1L]] <- 0

    push <- function(node, value) {
      heap_size <<- heap_size + 1L
      if (heap_size > length(heap_node)) {
        length(heap_node) <<- length(heap_node) * 2L
        length(heap_value) <<- length(heap_value) * 2L
      }
      position <- heap_size
      heap_node[[position]] <<- node
      heap_value[[position]] <<- value
      while (position > 1L) {
        parent <- position %/% 2L
        if (heap_value[[parent]] <= heap_value[[position]]) break
        tmp_node <- heap_node[[parent]]
        tmp_value <- heap_value[[parent]]
        heap_node[[parent]] <<- heap_node[[position]]
        heap_value[[parent]] <<- heap_value[[position]]
        heap_node[[position]] <<- tmp_node
        heap_value[[position]] <<- tmp_value
        position <- parent
      }
    }

    pop <- function() {
      node <- heap_node[[1L]]
      value <- heap_value[[1L]]
      heap_node[[1L]] <<- heap_node[[heap_size]]
      heap_value[[1L]] <<- heap_value[[heap_size]]
      heap_size <<- heap_size - 1L
      position <- 1L
      repeat {
        left <- position * 2L
        right <- left + 1L
        if (left > heap_size) break
        child <- left
        if (right <= heap_size && heap_value[[right]] < heap_value[[left]]) {
          child <- right
        }
        if (heap_value[[position]] <= heap_value[[child]]) break
        tmp_node <- heap_node[[position]]
        tmp_value <- heap_value[[position]]
        heap_node[[position]] <<- heap_node[[child]]
        heap_value[[position]] <<- heap_value[[child]]
        heap_node[[child]] <<- tmp_node
        heap_value[[child]] <<- tmp_value
        position <- child
      }
      c(node = node, value = value)
    }

    # The source is already present in the heap; subsequent entries are added
    # whenever a shorter tentative path is found.
    while (heap_size > 0L) {
      current <- pop()
      node <- as.integer(current[["node"]])
      value <- current[["value"]]
      if (visited[[node]] || value > distance[[node]]) next
      visited[[node]] <- TRUE

      adjacent <- adjacency[[node]]
      if (!length(adjacent)) next
      alternatives <- value + weights[[node]]
      improved <- alternatives < distance[adjacent]
      if (any(improved)) {
        for (k in which(improved)) {
          next_node <- adjacent[[k]]
          distance[[next_node]] <- alternatives[[k]]
          push(next_node, alternatives[[k]])
        }
      }
    }

    distance[is.infinite(distance)] <- NA_real_
    distance
  }

  output <- vector("list", nrow(harbours))
  for (i in seq_len(nrow(harbours))) {
    item <- grid_sf
    item$layer <- shortest_paths(source_cell[[i]], adjacency, weights)
    item$harb <- as.character(harbours[[harbour_col]][[i]])
    output[[i]] <- item
  }

  do.call(rbind, output)
}
