# Usage: Rscript scripts/export_f.R input.csv output.xlsx [case_file] [replicate]
args <- commandArgs(trailingOnly=TRUE)
if (length(args)<2L) stop("Supply the exact calibrated CSV and output XLSX paths.")
source("R/workflow_config.R")
source("R/f_export.R")
case <- smart31_load_case(if(length(args)>2L) args[[3L]] else "config/case_study.R")
replicate_id <- if(length(args)>3L) as.integer(args[[4L]]) else 1L
smart31_export_f(args[[1L]],args[[2L]],case,replicate_id)
