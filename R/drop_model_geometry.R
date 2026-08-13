drop_model_geometry <- function(x) {
  
  if (inherits(x, "sf")) {
    return(sf::st_drop_geometry(x))
  }
  
  as.data.frame(x)
}
