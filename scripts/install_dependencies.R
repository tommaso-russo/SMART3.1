# Usage: Rscript scripts/install_dependencies.R [all|step1|step2|step3|tests]
source("config/dependencies.R")
args <- commandArgs(trailingOnly=TRUE)
selection <- if(length(args)) args[[1L]] else "all"
if(!selection %in% c("all",names(smart31_dependencies))) stop("Unknown dependency group.")
if(getRversion()<smart31_minimum_R) stop("R >= ",smart31_minimum_R," is required.")
packages <- unique(c(smart31_dependencies$common,unlist(if(selection=="all")
  smart31_dependencies else smart31_dependencies[selection],use.names=FALSE)))
missing <- packages[!vapply(packages,requireNamespace,logical(1),quietly=TRUE)]
old <- names(smart31_minimum_versions)[vapply(names(smart31_minimum_versions),function(p)
  p %in% packages && requireNamespace(p,quietly=TRUE) && packageVersion(p)<smart31_minimum_versions[[p]],logical(1))]
if(length(c(missing,old))) install.packages(unique(c(missing,old)),repos="https://cloud.r-project.org")
missing <- packages[!vapply(packages,requireNamespace,logical(1),quietly=TRUE)]
if(length(missing)) stop("Installation incomplete: ",paste(missing,collapse=", "),". Check system libraries in docs/workflows.md.")
message("Dependencies available for ",selection,". Save a renv lockfile after validating your local environment.")
