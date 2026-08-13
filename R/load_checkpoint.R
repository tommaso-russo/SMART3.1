load_checkpoint <- function(stage, required_objects, context = NULL) {
  if (!isTRUE(reuse_checkpoints)) {
    return(NULL)
  }
  
  input_file <- checkpoint_path(stage)
  
  if (!file.exists(input_file)) {
    return(NULL)
  }
  
  checkpoint <- tryCatch(
    readRDS(input_file),
    error = function(e) NULL
  )
  
  valid_checkpoint <-
    is.list(checkpoint) &&
    is.list(checkpoint$metadata) &&
    is.list(checkpoint$objects) &&
    identical(
      checkpoint$metadata$run_configuration_hash,
      run_configuration_hash
    ) &&
    identical(
      checkpoint$metadata$context_hash,
      object_hash(context)
    ) &&
    all(required_objects %in% names(checkpoint$objects))
  
  if (!valid_checkpoint) {
    warning(
      "Checkpoint ", stage,
      " is incompatible with the current inputs and will be rebuilt."
    )
    return(NULL)
  }
  
  message("Checkpoint reused: ", input_file)
  checkpoint$objects
}
