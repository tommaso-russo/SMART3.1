restore_checkpoint <- function(objects, envir = knitr::knit_global()) {
  list2env(objects, envir = envir)
  invisible(names(objects))
}
