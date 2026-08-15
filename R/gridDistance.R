#' Compute water-constrained distances from harbours to grid cells
#'
#' Distances are shortest paths through grid cells that share an edge, rather
#' than straight lines across land. By default, corner-only contacts are used
#' only to reconnect very small coastal components to a larger adjacent marine
#' component. Edge weights are centroid-to-centroid distances and the result
#' is expressed in kilometres.
#'
#' @param grid_centroid An `sf` point object with one row per grid cell.
#' @param grid_sf An `sf` polygon object containing a unique `id_grid` column.
#' @param harbs_df_sf An `sf` point object containing harbour names.
#' @param harbour_col Name of the harbour-name column. Defaults to `HARBOUR`.
#' @param connect_small_corner_components Logical. If `TRUE`, a component with
#'   no more than `maximum_corner_component_size` cells may be connected to a
#'   larger component when the two components touch at one or more grid
#'   corners. This repairs coastal raster artefacts without enabling diagonal
#'   movement throughout the grid.
#' @param maximum_corner_component_size Maximum number of cells in a component
#'   eligible for the conservative corner-bridge repair.
#'
#' @return An `sf` object containing one copy of each grid cell per harbour.
#'   `layer` is the water-constrained distance in kilometres and `harb` is the
#'   harbour name. Unreachable cells have `NA` distance. The output attributes
#'   `rook_component_summary` and `corner_bridge_diagnostics` describe the
#'   original edge-connected components and any added corner bridges.
#' @export
gridDistance <- function(grid_centroid,
                         grid_sf,
                         harbs_df_sf,
                         harbour_col = "HARBOUR",
                         connect_small_corner_components = TRUE,
                         maximum_corner_component_size = 3L) {
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
  if (!is.logical(connect_small_corner_components) ||
      length(connect_small_corner_components) != 1L ||
      is.na(connect_small_corner_components)) {
    stop(
      "'connect_small_corner_components' must be TRUE or FALSE.",
      call. = FALSE
    )
  }
  if (!is.numeric(maximum_corner_component_size) ||
      length(maximum_corner_component_size) != 1L ||
      !is.finite(maximum_corner_component_size) ||
      maximum_corner_component_size < 1 ||
      maximum_corner_component_size != as.integer(maximum_corner_component_size)) {
    stop(
      "'maximum_corner_component_size' must be one positive integer.",
      call. = FALSE
    )
  }
  maximum_corner_component_size <- as.integer(
    maximum_corner_component_size
  )
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

  # Label the components obtained using strict edge (rook) contiguity. These
  # are retained for diagnostics even when small coastal components are later
  # reconnected through a corner.
  component_id <- rep.int(NA_integer_, nrow(grid_sf))
  component_counter <- 0L

  for (start_cell in seq_len(nrow(grid_sf))) {
    if (!is.na(component_id[[start_cell]])) next

    component_counter <- component_counter + 1L
    component_id[[start_cell]] <- component_counter
    cell_queue <- start_cell
    queue_position <- 1L

    while (queue_position <= length(cell_queue)) {
      current_cell <- cell_queue[[queue_position]]
      queue_position <- queue_position + 1L
      new_cells <- adjacency[[current_cell]]

      if (length(new_cells)) {
        new_cells <- new_cells[is.na(component_id[new_cells])]
      }
      if (length(new_cells)) {
        component_id[new_cells] <- component_counter
        cell_queue <- c(cell_queue, new_cells)
      }
    }
  }

  component_size <- tabulate(
    component_id,
    nbins = component_counter
  )

  rook_component_summary <- data.frame(
    component = seq_len(component_counter),
    grid_cells = component_size,
    stringsAsFactors = FALSE
  )

  corner_bridge_diagnostics <- data.frame(
    from_id_grid = character(),
    to_id_grid = character(),
    small_component = integer(),
    target_component = integer(),
    small_component_cells = integer(),
    target_component_cells = integer(),
    distance_km = numeric(),
    stringsAsFactors = FALSE
  )

  if (connect_small_corner_components && component_counter > 1L) {
    # Point contacts are considered only across different rook components.
    # A bridge is eligible only when exactly one side is a small component and
    # the other side is larger than the configured threshold.
    corner_neighbours <- sf::st_relate(grid_sf, pattern = "F***0****")
    corner_from <- rep.int(
      seq_along(corner_neighbours),
      lengths(corner_neighbours)
    )
    corner_to <- unlist(corner_neighbours, use.names = FALSE)
    retain_corner <- corner_from < corner_to
    corner_from <- corner_from[retain_corner]
    corner_to <- corner_to[retain_corner]

    if (length(corner_from)) {
      from_component <- component_id[corner_from]
      to_component <- component_id[corner_to]
      from_size <- component_size[from_component]
      to_size <- component_size[to_component]

      from_is_small <-
        from_size <= maximum_corner_component_size &
        to_size > maximum_corner_component_size
      to_is_small <-
        to_size <= maximum_corner_component_size &
        from_size > maximum_corner_component_size

      eligible <-
        from_component != to_component &
        (from_is_small | to_is_small)

      corner_from <- corner_from[eligible]
      corner_to <- corner_to[eligible]
      from_component <- from_component[eligible]
      to_component <- to_component[eligible]
      from_size <- from_size[eligible]
      to_size <- to_size[eligible]
      from_is_small <- from_is_small[eligible]

      if (length(corner_from)) {
        small_component <- ifelse(
          from_is_small,
          from_component,
          to_component
        )
        target_component <- ifelse(
          from_is_small,
          to_component,
          from_component
        )
        small_size <- component_size[small_component]
        target_size <- component_size[target_component]

        corner_distance <- sf::st_distance(
          grid_centroid[corner_from, ],
          grid_centroid[corner_to, ],
          by_element = TRUE
        )
        corner_km <- as.numeric(
          units::set_units(corner_distance, "km")
        )

        bridge_candidates <- data.frame(
          from = corner_from,
          to = corner_to,
          small_component = small_component,
          target_component = target_component,
          small_component_cells = small_size,
          target_component_cells = target_size,
          distance_km = corner_km,
          stringsAsFactors = FALSE
        )

        # When a small component touches several larger components, connect it
        # only to the largest one. Ties are resolved using the shortest corner
        # link and then the component identifier, making the result stable.
        target_options <- stats::aggregate(
          distance_km ~ small_component + target_component +
            target_component_cells,
          data = bridge_candidates,
          FUN = min
        )
        target_options <- target_options[
          order(
            target_options$small_component,
            -target_options$target_component_cells,
            target_options$distance_km,
            target_options$target_component
          ),
          ,
          drop = FALSE
        ]
        selected_targets <- target_options[
          !duplicated(target_options$small_component),
          c("small_component", "target_component"),
          drop = FALSE
        ]

        selected_key <- paste(
          selected_targets$small_component,
          selected_targets$target_component,
          sep = "::"
        )
        candidate_key <- paste(
          bridge_candidates$small_component,
          bridge_candidates$target_component,
          sep = "::"
        )
        bridge_candidates <- bridge_candidates[
          candidate_key %in% selected_key,
          ,
          drop = FALSE
        ]

        if (nrow(bridge_candidates)) {
          for (bridge in seq_len(nrow(bridge_candidates))) {
            i <- bridge_candidates$from[[bridge]]
            j <- bridge_candidates$to[[bridge]]
            bridge_weight <- bridge_candidates$distance_km[[bridge]]

            adjacency[[i]] <- c(adjacency[[i]], j)
            weights[[i]] <- c(weights[[i]], bridge_weight)
            adjacency[[j]] <- c(adjacency[[j]], i)
            weights[[j]] <- c(weights[[j]], bridge_weight)
          }

          corner_bridge_diagnostics <- data.frame(
            from_id_grid = as.character(
              grid_sf$id_grid[bridge_candidates$from]
            ),
            to_id_grid = as.character(
              grid_sf$id_grid[bridge_candidates$to]
            ),
            small_component = bridge_candidates$small_component,
            target_component = bridge_candidates$target_component,
            small_component_cells =
              bridge_candidates$small_component_cells,
            target_component_cells =
              bridge_candidates$target_component_cells,
            distance_km = bridge_candidates$distance_km,
            stringsAsFactors = FALSE
          )
        }
      }
    }
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

  result <- do.call(rbind, output)
  attr(result, "rook_component_summary") <- rook_component_summary
  attr(result, "corner_bridge_diagnostics") <- corner_bridge_diagnostics
  result
}

attr(gridDistance, "SMART31_version") <- "2026-08-15.2"
