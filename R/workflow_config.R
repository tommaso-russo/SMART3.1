# Case configuration and the interfaces shared by the four reports.
smart31_load_case <- function(file, require_confirmed = TRUE) {
  file <- normalizePath(path.expand(file), mustWork = TRUE)
  env <- new.env(parent = baseenv())
  case <- sys.source(file, envir = env)
  if (!exists("case", env, inherits = FALSE)) stop("The case file must define a list named case.")
  case <- env$case
  required <- c("case_id", "calendar", "domain", "paths", "management", "reporting", "scenarios", "survey", "economics")
  if (!is.list(case) || length(setdiff(required, names(case)))) stop("Incomplete case configuration.")
  if (require_confirmed && !isTRUE(case$configured))
    stop("Copy config/case_study.example.R to config/case_study.R, review its settings and set configured = TRUE.")
  root <- normalizePath(getwd(), mustWork = TRUE)
  if (!file.exists(file.path(root, "R/workflow_config.R"))) stop("Run from the SMART3.1 project root.")
  if (length(case$case_id)!=1L || !grepl("^[A-Za-z0-9][A-Za-z0-9_-]*$",case$case_id)) stop("Use a simple case_id containing letters, digits, underscores or hyphens.")
  case$project_root <- root
  case$config_file <- file
  cal <- case$calendar
  if (any(!is.finite(unlist(cal))) || any(unlist(cal) %% 1 != 0) ||
      length(cal$baseline) != 1L || length(cal$anchor) != 1L ||
      !length(cal$future) || !identical(as.integer(cal$future), seq.int(min(cal$future), max(cal$future))) ||
      cal$anchor >= cal$baseline || cal$baseline >= min(cal$future) ||
      max(cal$calibration) >= cal$anchor || max(case$domain$years_to_submit) != cal$anchor)
    stop("Require integer years: historical endpoint = anchor < baseline < consecutive future years; calibration before anchor.")
  case$periods <- list(baseline = as.character(cal$baseline), future = paste(range(cal$future), collapse = "_"))
  sc <- case$scenarios
  cols <- c("role", "scenario_id", "cm_status", "method", "depth_closure", "closed_months", "depth_bonus", "season_bonus", "cessation_bonus")
  if (length(setdiff(cols, names(sc))) || !setequal(sc$role, c("baseline", "A", "B")) ||
      anyDuplicated(sc$role) || anyDuplicated(sc$scenario_id) || anyNA(sc[setdiff(cols,"closed_months")]))
    stop("Define exactly one baseline and two management alternatives A/B with unique identifiers.")
  sc$representative_period <- ifelse(sc$role == "baseline", case$periods$baseline, case$periods$future)
  sc$scenario_year <- ifelse(sc$role == "baseline", cal$baseline, min(cal$future))
  if (any(!sc$cm_status %in% c("with_cm","without_cm")) ||
      any(!sc$method %in% c("both","bayesian_dirichlet","stochastic_optimizer")) ||
      !is.logical(sc$depth_closure) || any(vapply(sc$closed_months, function(m)
        anyNA(m) || any(!m %in% 1:12) || anyDuplicated(m)>0L, logical(1))))
    stop("Invalid scenario status, method, closure flag or months.")
  if (any(as.matrix(sc[c("depth_bonus","season_bonus","cessation_bonus")])<0) ||
      any(!is.finite(as.matrix(sc[c("depth_bonus","season_bonus","cessation_bonus")])))) stop("Invalid compensation fractions.")
  if (any(sc$cm_status=="without_cm" & rowSums(sc[c("depth_bonus","season_bonus","cessation_bonus")])>0))
    stop("A without_cm scenario cannot award compensation days.")
  if (sc$cm_status[sc$role=="A"]!="without_cm" || sc$cm_status[sc$role=="B"]!="with_cm")
    stop("The current report adapter requires A without CM and B with CM.")
  if (length(case$management$effort_length_classes)!=4L) stop("Supply four effort length classes for the current adapter.")
  if (length(case$reporting$effort_groups)!=2 || anyDuplicated(case$reporting$effort_groups) ||
      length(case$reporting$effort_group_codes)!=2 || anyDuplicated(case$reporting$effort_group_codes))
    stop("The effort-report adapter requires two distinct group labels and codes.")
  if (length(case$management$fmsy_stocks) && (!nzchar(case$paths$fmsy_limits) || !nzchar(case$paths$constraint_scope)))
    stop("Selected FMSY stocks require a limits file and species-area constraint scope.")
  if (!identical(case$management$regulated_gear,"OTB"))
    stop("The current compensation and effort-report adapter supports OTB; another gear requires an adapter.")
  if (!length(case$survey$areas) || !length(case$survey$years)) stop("Define survey areas and years.")
  if (length(case$reporting$cfr_prefix)!=1L || !grepl("^[A-Z]{3}$",case$reporting$cfr_prefix) ||
      length(case$reporting$cfr_numeric_width)!=1L || !is.finite(case$reporting$cfr_numeric_width) ||
      case$reporting$cfr_numeric_width<1 || case$reporting$cfr_numeric_width%%1!=0) stop("Invalid CFR format.")
  case$step1_controls$economic_country_code <- case$domain$country
  case$survey$cache_scope <- paste("MEDITS", paste(sort(case$domain$country_aliases),collapse=":"),
    paste(sort(case$survey$areas),collapse=":"), paste(sort(case$survey$years),collapse=":"), sep="|")
  case$scenarios <- sc
  case$scenario_ids <- as.list(stats::setNames(sc$scenario_id, sc$role))
  case$scenario_codes <- list(baseline = paste0("BASELINE_", cal$baseline), A = "A", B = "B")
  case$calibration_id <- paste0("median_", min(cal$calibration), "_", max(cal$calibration), "_landings_share")
  case$sensitivity_id <- paste0("q_", max(cal$calibration), "_landings_share_sensitivity")
  if (length(case$management$enforce_catch_quotas) != 1L || !is.logical(case$management$enforce_catch_quotas) ||
      is.na(case$management$enforce_catch_quotas)) stop("Choose enforce_catch_quotas = TRUE or FALSE explicitly.")
  if (anyNA(case$management$fmsy_stocks) || anyDuplicated(case$management$fmsy_stocks)) stop("FMSY stock IDs must be unique and non-missing.")
  if (!is.null(case$management$fuel_price_eur_l) &&
      (length(case$management$fuel_price_eur_l) != 1 || !is.finite(case$management$fuel_price_eur_l) || case$management$fuel_price_eur_l <= 0))
    stop("fuel_price_eur_l must be NULL or one positive EUR/l value.")
  case
}
smart31_year_values <- function(case) {
  c <- case$calendar
  list(history_start = min(case$domain$years_to_submit), calibration_start = min(c$calibration),
       calibration_end = max(c$calibration), anchor = c$anchor, baseline = c$baseline,
       future = c$future, future_start = min(c$future), future_end = max(c$future))
}
smart31_case_fingerprint <- function(case) {
  x <- case
  x$config_file <- x$project_root <- NULL
  path <- tempfile(); on.exit(unlink(path), add=TRUE)
  saveRDS(x, path, version=2)
  unname(tools::md5sum(path))
}
smart31_code_fingerprint <- function() {
  files <- sort(c(list.files("R", "[.]R$", full.names=TRUE, recursive=TRUE),
                  list.files("workflows", "[.]Rmd$", full.names=TRUE)))
  path <- tempfile(); on.exit(unlink(path), add=TRUE)
  writeLines(paste(files, unname(tools::md5sum(files))), path)
  unname(tools::md5sum(path))
}
smart31_stage_config <- function(case, stage) {
  env <- new.env(parent=baseenv()); sys.source("R/workflow_defaults.R", env)
  cfg <- env$smart31_workflow_defaults[[stage]]
  if (is.null(cfg)) stop("Unknown workflow: ", stage)
  overrides <- case$controls[[stage]] %||% list()
  if (length(setdiff(names(overrides),names(cfg)))) stop("Unknown ",stage," controls: ",paste(setdiff(names(overrides),names(cfg)),collapse=", "))
  cfg <- utils::modifyList(cfg, overrides, keep.null=TRUE)
  p <- case$paths; y <- smart31_year_values(case)
  cfg$step1_bundle_file <- p$step1_bundle
  cfg$step2_result_file <- p$step2_result
  cfg$expected_step1_bundle_md5 <- case$expected_step1_md5 %||% ""
  cfg$expected_step1_md5 <- case$expected_step1_md5 %||% ""
  cfg$project_root <- case$project_root
  cfg$output_directory <- file.path("outputs", case$case_id, stage)
  if (stage == "step2") {
    cfg$italian_cessation_file <- p$cessation_file
    cfg$italian_cessation_cfr <- character()
    cfg$italian_catch_quota_file <- p$catch_quotas
    cfg$italian_effort_quota_file <- p$effort_quotas
    cfg$fmsy_limits_file <- p$fmsy_limits
    cfg$fmsy_assessment_crosswalk_file <- p$constraint_scope
    cfg$enforce_fmsy <- length(case$management$fmsy_stocks)>0L
    cfg$map_gsa_file <- p$gsa_file; cfg$map_land_file <- p$land_file
  }
  if (stage == "step3") {
    cfg <- utils::modifyList(cfg, p$step3, keep.null=TRUE)
    cfg$step2_search_directories <- character()
    cfg$calibration_year_min <- y$calibration_start; cfg$calibration_year_max <- y$calibration_end
    cfg$calibration_anchor_year <- y$anchor
    cfg$expected_fdi_table_a_md5 <- case$expected_fdi_md5 %||% ""
    cfg$economic_impact_audit_file <- p$economic_audit
    cfg$expected_economic_impact_audit_version <- "SMART31.economic.audit.1"
    cfg$annex_individual_xlsx_directory <- file.path(cfg$output_directory, "tables")
    cfg$fmsy_limits_export_file <- file.path(cfg$output_directory, "SMART31_recomputed_fmsy_limits.csv")
    cfg$ara_ars_authorized_vessels_year <- y$baseline
    cfg$ara_ars_authorized_vessels_sheet <- case$reporting$authorization_sheet
    cfg$expected_ara_ars_authorized_vessels_n <- case$reporting$expected_authorized_vessels
  }
  if (stage == "economic_audit") {
    cfg$new_economic_file <- p$economic_reference
    cfg$recent_year_min <- y$calibration_start; cfg$recent_year_max <- y$calibration_end
    cfg$benchmark_year <- y$calibration_end
  }
  cfg
}
`%||%` <- function(x,y) if(is.null(x)) y else x
smart31_validate_selected_limits <- function(limits, stocks, years) {
  if (!setequal(unique(limits$assessment_stock), stocks) ||
      nrow(limits) != length(stocks)*length(years) ||
      anyDuplicated(limits[c("assessment_stock","YEAR")])) stop("Incomplete selected FMSY stock/year coverage.")
  if (length(stocks)) for (stock in stocks)
    if (!setequal(limits$YEAR[limits$assessment_stock==stock],years)) stop("Missing FMSY year for ",stock)
  invisible(TRUE)
}
smart31_validate_step2_policy <- function(result, case) {
  m <- result$metadata
  if (!identical(m$workflow_schema,"SMART31.generic.1"))
    stop("Step 3 requires a result produced by this generic workflow, with explicit constraint metadata.")
  if (!identical(m$ordinary_catch_quotas_enforced,case$management$enforce_catch_quotas) ||
      !setequal(m$enforced_fmsy_stocks,case$management$fmsy_stocks))
    stop("Step 2 / Step 3 catch or FMSY constraint policy mismatch.")
  if (!identical(m$calendar,case$calendar)) stop("Step 2 / Step 3 calendar mismatch.")
  smart31_validate_selected_limits(result$fmsy_catch_limits, m$enforced_fmsy_stocks, case$calendar$future)
  invisible(TRUE)
}
smart31_preflight <- function(case, stage, cfg) {
  p <- case$paths
  required <- character()
  if (stage == "step1") required <- c(p$gsa_file, p$bathymetry_file, unlist(p$fdi), p$fuel_prices_file,
    sprintf(p$effort_pattern,case$domain$years_to_submit), sprintf(p$landings_pattern,case$domain$years_to_submit))
  if (stage == "step1" && isTRUE(case$step1_controls$run_age_module))
    required <- c(required,p$medits_ta,p$medits_tb,p$medits_tc,p$stock_parameters_file,p$commercial_age_baseline, file.path(p$survey_cache,paste0(c("TA","TB","TC"),"_age_cache.rds")))
  if (stage == "step2") required <- c(p$step1_bundle,p$effort_quotas,p$catch_quotas,p$fmsy_limits,p$constraint_scope,p$cessation_file)
  if (stage %in% c("step3","economic_audit")) required <- c(p$step1_bundle,p$step2_result)
  if (stage == "economic_audit") required <- c(required,p$economic_reference)
  if (stage == "step3") {
    if (!nzchar(p$economic_audit)) stop("Pin paths$economic_audit explicitly.")
    if (is.null(case$reporting$expected_authorized_vessels) || case$reporting$expected_authorized_vessels <= 0)
      stop("Set reporting$expected_authorized_vessels to the verified count for the authorization workbook.")
    required <- c(required,p$economic_audit,unlist(p$step3[setdiff(names(p$step3),"single_stock_advice_file")]))
  }
  required <- unique(required[!is.na(required) & nzchar(required)])
  missing <- required[!file.exists(path.expand(required))]
  if(length(missing)) stop("Missing local inputs for ",stage,":\n",paste(missing,collapse="\n"),call.=FALSE)
  if(stage %in% c("step2","step3","economic_audit") && !nzchar(p$step1_bundle)) stop("Pin paths$step1_bundle explicitly.")
  if(stage %in% c("step3","economic_audit") && !nzchar(p$step2_result)) stop("Pin paths$step2_result explicitly.")
  invisible(TRUE)
}
# Scenario construction uses the existing closure, compensation and search APIs.
smart31_materialise_scenarios <- function(case, depth_cells, cessation, controls) {
  lapply(seq_len(nrow(case$scenarios)), function(i) {
    row <- case$scenarios[i,,drop=FALSE]; id <- row$scenario_id
    closures <- list(); rules <- list()
    if (row$depth_closure) closures[[length(closures)+1L]] <- new_closure(
      paste0(id,"_depth"), id_grid=depth_cells, gears=case$management$regulated_gear,
      source_note=case$management$source)
    months <- row$closed_months[[1L]]
    if (length(months)) closures[[length(closures)+1L]] <- new_closure(
      paste0(id,"_season"), id_grid=NULL, months=months, gears=case$management$regulated_gear,
      source_note=case$management$source)
    for (kind in c("depth","season","cessation")) {
      rate <- row[[paste0(kind,"_bonus")]]
      if (!is.finite(rate) || rate < 0) stop("Invalid compensation fraction in ",id)
      if (rate > 0) {
        if (kind=="depth" && !row$depth_closure || kind=="season" && !length(months)) stop("Bonus without associated measure: ",id)
        rules[[length(rules)+1L]] <- new_cm_rule(paste0(id,"_",kind,"_bonus"),
          associated_measure_id=if(kind=="cessation") "PERMANENT_CESSATION" else paste0(id,"_",kind),
          extra_days_fraction=rate,eligible_gears=case$management$regulated_gear,
          member_state=case$domain$country,rate_status=case$management$source)
      }
    }
    new_smart31_scenario(id,scenario_year=row$scenario_year,representative_period=row$representative_period,
      cm_status=row$cm_status,method=row$method,closures=closures,compensation_mechanisms=rules,
      permanent_cessation_cfr=cessation,parameters=controls)
  })
}

# Human-readable labels use the configured calendar; machine-readable compatibility fields do not.
smart31_report_label <- function(x, case=get(".smart31_case",envir=parent.frame(),inherits=TRUE)) {
  values <- c('2020'=min(case$domain$years_to_submit),'2022'=min(case$calendar$calibration),
    '2024'=max(case$calendar$calibration),'2025'=case$calendar$anchor,'2026'=case$calendar$baseline,
    '2027'=min(case$calendar$future),'2030'=max(case$calendar$future))
  for (year in names(values)) x <- gsub(paste0('(?<![0-9])',year,'(?![0-9])'),paste0('@Y',year,'@'),x,perl=TRUE)
  for (year in names(values)) x <- gsub(paste0('@Y',year,'@'),as.character(values[[year]]),x,fixed=TRUE)
  x <- gsub('Italian',paste0(case$domain$country,' fleet'),x,fixed=TRUE)
  x <- gsub('Italy',case$domain$country,x,fixed=TRUE)
  gsub('EMU2',case$reporting$emu,x,fixed=TRUE)
}
smart31_kable <- function(x, ..., caption=NULL) {
  case <- get(".smart31_case",envir=parent.frame(),inherits=TRUE)
  if (is.data.frame(x) && length(names(x))) names(x) <- smart31_report_label(names(x),case)
  knitr::kable(x,...,caption=if(is.null(caption)) NULL else smart31_report_label(caption,case))
}

# Optional external commercial biomass-at-age proportions; no case values are embedded in source.
smart31_commercial_age_input <- function(path) {
  if (is.null(path) || !nzchar(path)) return(tibble::tibble(Species=character(),Age=integer(),report_baseline_proportion=numeric()))
  x <- utils::read.csv(path,stringsAsFactors=FALSE)
  cols <- c("Species","Age","report_baseline_proportion")
  if (!all(cols %in% names(x))) stop("Commercial age input needs: ",paste(cols,collapse=", "))
  x <- x[cols]
  if (anyNA(x) || anyDuplicated(x[c("Species","Age")]) ||
      !is.numeric(x$Age) || any(x$Age<0 | x$Age%%1!=0) ||
      !is.numeric(x$report_baseline_proportion) || any(!is.finite(x$report_baseline_proportion)) ||
      any(x$report_baseline_proportion<=0 | x$report_baseline_proportion>1)) stop("Invalid commercial age proportions.")
  if (any(abs(tapply(x$report_baseline_proportion,x$Species,sum)-1)>1e-8)) stop("Commercial age proportions must sum to one by species.")
  tibble::as_tibble(x)
}
