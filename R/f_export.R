# Expand representative annual F vectors without averaging methods or replicates.
smart31_expand_f <- function(x, calibration, replicate_id, scenario_codes, periods) {
  required <- c("contract_scenario_code","method","replicate","assessment_stock",
    "Age","F_total","calibration","calibration_valid","representative_year_start","representative_year_end")
  if (length(setdiff(required,names(x)))) stop("Incomplete calibrated F schema.")
  if (length(replicate_id)!=1L || !is.finite(replicate_id) || replicate_id<1 || replicate_id%%1!=0)
    stop("Choose one positive integer replicate.")
  x <- x[x$calibration %in% calibration & x$replicate %in% replicate_id,,drop=FALSE]
  if (!nrow(x) || length(calibration)!=1L) stop("No rows for the selected calibration and replicate.")
  if (anyNA(x[required]) || any(!tolower(as.character(x$calibration_valid)) %in% c("true","1")) ||
      !is.numeric(x$F_total) || any(!is.finite(x$F_total) | x$F_total<0))
    stop("Invalid calibration or F_total; inspect the Step 3 biological audit.")
  key <- c("contract_scenario_code","method","assessment_stock","Age")
  if (anyDuplicated(x[key])) stop("Duplicate F vectors: no automatic averaging is allowed.")
  if (!setequal(unique(x$contract_scenario_code),scenario_codes)) stop("Unexpected scenario coverage.")
  groups <- split(x$contract_scenario_code, interaction(x$method,x$assessment_stock,x$Age,drop=TRUE))
  if (any(!vapply(groups,function(z)setequal(z,scenario_codes),logical(1))))
    stop("Unequal method/stock/age coverage across scenarios.")
  idx <- match(x$contract_scenario_code,periods$scenario)
  if (anyNA(idx) || any(x$representative_year_start!=periods$start[idx]) ||
      any(x$representative_year_end!=periods$end[idx])) stop("Unexpected representative periods.")
  if (any(!is.finite(x$Age) | x$Age<0 | x$Age%%1!=0)) stop("Invalid age index.")
  out <- do.call(rbind,lapply(seq_len(nrow(x)),function(i) data.frame(
    scenario=x$contract_scenario_code[i], YEAR=seq.int(x$representative_year_start[i],x$representative_year_end[i]),
    method=x$method[i],Stock=x$assessment_stock[i],Age=x$Age[i],F=x$F_total[i])))
  out <- out[order(match(out$scenario,scenario_codes),out$YEAR,out$method,out$Stock,out$Age),]
  rownames(out) <- NULL
  out
}

smart31_export_f <- function(input_file, output_file, case, replicate_id=1L) {
  if (!requireNamespace("openxlsx",quietly=TRUE)) stop("Install openxlsx first.")
  x <- utils::read.csv(input_file,check.names=FALSE,stringsAsFactors=FALSE)
  sc <- unlist(case$scenario_codes,use.names=FALSE)
  periods <- data.frame(scenario=sc,start=c(case$calendar$baseline,rep(min(case$calendar$future),2)),
    end=c(case$calendar$baseline,rep(max(case$calendar$future),2)))
  out <- smart31_expand_f(x,case$calibration_id,replicate_id,sc,periods)
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb,"F_at_age")
  openxlsx::writeData(wb,"F_at_age",out,withFilter=TRUE)
  openxlsx::freezePane(wb,"F_at_age",firstRow=TRUE)
  openxlsx::setColWidths(wb,"F_at_age",1:6,c(22,10,26,24,10,22))
  openxlsx::addStyle(wb,"F_at_age",openxlsx::createStyle(numFmt="0.000000000"),
    rows=seq_len(nrow(out))+1L,cols=6,gridExpand=TRUE)
  openxlsx::addWorksheet(wb,"Provenance")
  notes <- data.frame(item=c("Source","Source MD5","Calibration","Replicate","Meaning","Annual assumption","Audit"),
    value=c(normalizePath(input_file),unname(tools::md5sum(input_file)),case$calibration_id,replicate_id,
      "F_total is fishing mortality (modelled fleet + fixed external fleets); it is not Z = F + M.",
      "Each representative annual vector is repeated across its declared years, without population projection.",
      "Use only after the Step 3 ready_for_downstream gate passes; this exporter does not replace that gate."))
  openxlsx::writeData(wb,"Provenance",notes)
  openxlsx::setColWidths(wb,"Provenance",1:2,c(20,110))
  dir.create(dirname(output_file),recursive=TRUE,showWarnings=FALSE)
  openxlsx::saveWorkbook(wb,output_file,overwrite=TRUE)
  message("Saved ",nrow(out)," rows to ",normalizePath(output_file))
  invisible(out)
}
