drop_geometry <- function(x) {
  if (inherits(x, "sf")) sf::st_drop_geometry(x) else as.data.frame(x)
}