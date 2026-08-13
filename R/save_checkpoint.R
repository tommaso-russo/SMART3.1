save_checkpoint <- function(stage, objects, context = NULL, compress = TRUE) {
  if (is.null(names(objects)) || any(!nzchar(names(objects)))) {
    stop("Checkpoint objects must be supplied as a fully named list.")
  }
  
  checkpoint <- list(
    metadata = list(
      stage = stage,
      created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      run_configuration = run_configuration,
      run_configuration_hash = run_configuration_hash,
      context_hash = object_hash(context),
      object_names = names(objects),
      r_version = R.version.string
    ),
    objects = objects
  )
  
  output_file <- checkpoint_path(stage)
  temporary_file <- paste0(output_file, ".tmp")
  
  saveRDS(
    checkpoint,
    temporary_file,
    version = 3,
    compress = compress
  )
  
  if (!file.rename(temporary_file, output_file)) {
    unlink(temporary_file)
    stop("Unable to finalize checkpoint: ", output_file)
  }
  
  message("Checkpoint saved: ", output_file)
  invisible(output_file)
}
