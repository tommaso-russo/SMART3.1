checkpoint_path <- function(stage) {
  file.path(
    checkpoint_dir,
    paste0(stage, ".rds")
  )
}
