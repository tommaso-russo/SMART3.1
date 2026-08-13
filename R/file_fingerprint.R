file_fingerprint <- function(paths) {
  paths <- sort(unique(normalizePath(
    paths,
    winslash = "/",
    mustWork = TRUE
  )))
  
  file_information <- file.info(paths)
  
  data.frame(
    path = paths,
    size_bytes = as.numeric(file_information$size),
    modified_utc = format(
      file_information$mtime,
      tz = "UTC",
      usetz = TRUE
    ),
    stringsAsFactors = FALSE
  )
}
