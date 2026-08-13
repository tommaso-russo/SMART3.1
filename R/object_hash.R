object_hash <- function(x) {
  temporary_file <- tempfile(fileext = ".rds")
  on.exit(unlink(temporary_file), add = TRUE)
  
  saveRDS(
    x,
    temporary_file,
    version = 3,
    compress = FALSE
  )
  
  unname(tools::md5sum(temporary_file))
}