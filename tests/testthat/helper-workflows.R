suppressPackageStartupMessages({library(dplyr);library(tidyr);library(tibble);library(purrr)})
repo_root <- normalizePath(file.path(getwd(),"../.."),mustWork=TRUE)
setwd(repo_root)
source('R/workflow_config.R')
source('R/workflow_functions.R')
source('R/f_export.R')
example_case <- smart31_load_case('config/case_study.example.R',FALSE)
engine <- smart31_workflow_functions('step2')
engine$.smart31_case <- example_case
engine$.smart31_years <- smart31_year_values(example_case)
engine$cfg <- smart31_stage_config(example_case,'step2')
list2env(engine$cfg,engine)
source('R/stock_constraints.R',local=engine)
engine$quota_tolerance_fraction <- 1e-8
engine$simulation_output_directory <- tempdir()
engine$monitor_enabled <- FALSE
engine$monitor_update_every_units <- 10000L
engine$default_simulation_parameters <- list(max_days_per_month=25)
engine$management_member_state <- example_case$domain$country
engine$smart31_monitor_event <- function(...) invisible(NULL)
biology <- smart31_workflow_functions('step3')
biology$.smart31_case <- example_case
biology$.smart31_years <- smart31_year_values(example_case)
write_case <- function(case) {
  path <- tempfile(fileext='.R'); dput(case,file=path)
  txt <- readLines(path); writeLines(c(paste0('case <- ',txt[1]),txt[-1]),path)
  path
}
