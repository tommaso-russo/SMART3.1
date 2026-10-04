# Run once in a separate R process before Step 1; source workbooks remain unchanged.
args <- commandArgs(trailingOnly=TRUE)
source("R/workflow_config.R")
case <- smart31_load_case(if(length(args)) args[[1L]] else "config/case_study.R")
if (!requireNamespace("readxl",quietly=TRUE)) stop("Install readxl first.")
clean <- function(x) tolower(gsub("^_+|_+$","",gsub("[^A-Za-z0-9]+","_",trimws(x))))
keys <- c("country","area","vessel","year","haul_number","codend_closing","name_of_survey")
required <- list(
  TA=c(keys,"validity","shooting_quadrant","shooting_latitude","shooting_longitude","shooting_depth",
    "hauling_quadrant","hauling_latitude","hauling_longitude","hauling_depth","distance","wing_opening"),
  TB=c(keys,"partit","catfau","genus","species","ptot","nbtot"),
  TC=c(keys,"partit","catfau","genus","species","codlon","pfrac","pechan","nblon","length_class"))
dir.create(case$paths$survey_cache,recursive=TRUE,showWarnings=FALSE)
for (type in names(required)) {
  path <- normalizePath(case$paths[[paste0("medits_",tolower(type))]],mustWork=TRUE)
  x <- as.data.frame(readxl::read_excel(path,sheet=case$survey$sheet,col_types="text",.name_repair="minimal"))
  names(x) <- clean(names(x))
  if (anyDuplicated(names(x)) || length(setdiff(required[[type]],names(x))))
    stop("Missing or ambiguous ",type," headers: ",paste(setdiff(required[[type]],names(x)),collapse=", "))
  keep <- toupper(trimws(x$country)) %in% case$domain$country_aliases &
    suppressWarnings(as.integer(x$area)) %in% case$survey$areas &
    suppressWarnings(as.integer(x$year)) %in% case$survey$years &
    toupper(trimws(x$name_of_survey))=="MEDITS"
  x <- x[which(keep),required[[type]],drop=FALSE]
  if (!nrow(x)) stop("No ",type," survey rows match the configured country, areas and years.")
  info <- file.info(path)
  payload <- list(cache_version="SMART31.medits.cache.1",source_file=path,source_size=info$size,
    source_mtime=info$mtime,source_md5=unname(tools::md5sum(path)),required_columns=required[[type]],
    filter_scope=case$survey$cache_scope,n_rows=nrow(x),data=x)
  output <- file.path(case$paths$survey_cache,paste0(type,"_age_cache.rds"))
  saveRDS(payload,output)
  message(type,": ",nrow(x)," rows; ",output)
  rm(x,payload);invisible(gc())
}
