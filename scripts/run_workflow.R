# Run from the repository root: Rscript scripts/run_workflow.R step1 config/case_study.R
args <- commandArgs(trailingOnly=TRUE)
if (!length(args) || !args[[1L]] %in% c("step1","step2","step3","economic_audit"))
  stop("Usage: Rscript scripts/run_workflow.R <step1|step2|step3|economic_audit> [config/case_study.R]")
stage <- args[[1L]]
case_file <- if(length(args)>1L) args[[2L]] else "config/case_study.R"
source("R/workflow_config.R")
case <- smart31_load_case(case_file)
cfg <- smart31_stage_config(case,stage)
smart31_preflight(case,stage,cfg)
if(!requireNamespace("rmarkdown",quietly=TRUE)) stop("Install dependencies with scripts/install_dependencies.R.")
dir.create(cfg$output_directory,recursive=TRUE,showWarnings=FALSE)
rmarkdown::render(file.path("workflows",paste0(stage,".Rmd")),
  params=list(case_file=normalizePath(case_file)),
  knit_root_dir=getwd(),output_dir=normalizePath(cfg$output_directory),
  envir=globalenv())
