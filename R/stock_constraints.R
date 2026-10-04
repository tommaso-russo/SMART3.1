smart31_stock_parent <- function(x) {
  z <- toupper(trimws(as.character(x)))
  z <- gsub("[[:space:]_-]", "", sub("^GSA", "", z))
  z <- gsub(",", ".", z, fixed=TRUE)
  z[z %in% c("111","112","11.1","11.2")] <- "11"
  n <- suppressWarnings(as.integer(z))
  ifelse(is.na(n),NA_character_,sprintf("GSA%02d",n))
}
smart31_quota_species_code <- function(keys) {
  out <- as.character(keys); use <- startsWith(out,"STOCK::")
  if(any(use)) {
    stocks <- sub("^STOCK::","",out[use])
    m <- unique(stock_constraint_scope[c("assessment_stock","Species")])
    out[use] <- m$Species[match(stocks,m$assessment_stock)]
    if(anyNA(out)) stop("Unknown assessment constraint key.")
  }
  out
}
smart31_build_quota_rate <- function(catch_rate, gsa, keys) {
  out <- matrix(0,nrow=nrow(catch_rate),ncol=length(keys),dimnames=list(NULL,keys))
  if(!length(keys)) return(out)
  sp <- smart31_quota_species_code(keys)
  for(i in seq_along(keys)) {
    if(!sp[i] %in% colnames(catch_rate)) next
    v <- catch_rate[,sp[i]]
    if(startsWith(keys[i],"STOCK::")) {
      st <- sub("^STOCK::","",keys[i])
      areas <- stock_constraint_scope$GSA_code[stock_constraint_scope$assessment_stock==st]
      if(length(gsa)!=length(v)) stop("Missing area index for stock quota rates.")
      v[!smart31_stock_parent(gsa) %in% areas] <- 0
    }
    out[,i] <- v
  }
  out
}
smart31_context_quota_rate <- function(context) {
  if(!is.null(context$quota_rate)) return(context$quota_rate)

  if(any(startsWith(context$quota_species,"STOCK::"))) stop("Stock quota rate cache missing.")
  smart31_build_quota_rate(context$catch_rate,NULL,context$quota_species)
}
smart31_quota_exposure <- function(context, ids, effort) {
  stats::setNames(colSums(smart31_context_quota_rate(context)[ids,,drop=FALSE]*as.numeric(effort)),context$quota_species)
}
smart31_quota_catches <- function(catches, keys) {
  out <- stats::setNames(numeric(length(keys)),keys)
  if(!length(keys) || !nrow(catches)) return(out)
  if(!all(c("Species","W") %in% names(catches)) || any(!is.finite(catches$W)) || any(catches$W < -1e-8))
    stop("Invalid full catches in quota accounting.")
  sp <- smart31_quota_species_code(keys)
  for(i in seq_along(keys)) {
    keep <- as.character(catches$Species)==sp[i]
    if(startsWith(keys[i],"STOCK::")) {
      if(!"GSA_code" %in% names(catches)) stop("Full catches lack GSA_code for stock quotas.")
      st <- sub("^STOCK::","",keys[i])
      areas <- stock_constraint_scope$GSA_code[stock_constraint_scope$assessment_stock==st]
      keep <- keep & smart31_stock_parent(catches$GSA_code) %in% areas
    }
    if(anyNA(keep)) stop("Incomplete species/GSA in quota accounting.")
    out[i] <- sum(catches$W[keep])
  }
  out
}
smart31_validate_stock_inputs <- function(limits, scope) {
  if(!all(c("Species","GSA_code","assessment_stock") %in% names(scope))) stop("Stock scope schema incomplete.")
  if(anyNA(scope[c("Species","GSA_code","assessment_stock")]) || anyDuplicated(scope[c("Species","GSA_code")]))
    stop("Missing or ambiguous species-area stock scope.")
  if(!all(scope$GSA_code==smart31_stock_parent(scope$GSA_code))) stop("Scope must use parent GSA codes.")
  for(st in unique(limits$assessment_stock)) {
    x <- limits[limits$assessment_stock==st,,drop=FALSE]
    if(!setequal(x$YEAR,.smart31_years$future) || nrow(x)!=length(.smart31_years$future) || length(unique(x$Species))!=1 ||
       !all(x$Species==scope$Species[match(st,scope$assessment_stock)])) stop("Invalid stock/year mapping: ",st)
    for(nm in setdiff(names(x),"YEAR")) if(length(unique(x[[nm]]))!=1) stop("Representative annual constraint varies across years: ",st)
    q <- x[1,,drop=FALSE]
    if(!is.finite(q$anchor_2025_t) || q$anchor_2025_t<=0 || q$Fmsy<=0) stop("Invalid F anchor for ",st)
    f0 <- smart31_monitor_f_at_catch(0,q)
    fa <- smart31_monitor_f_at_catch(q$anchor_2025_t*1000,q)
    fc <- smart31_monitor_f_at_catch(q$quota_kg,q)
    af <- as.numeric(strsplit(q$age_F_ITA_anchor,";",fixed=TRUE)[[1]])
    ef <- as.numeric(strsplit(q$age_F_external,";",fixed=TRUE)[[1]])
    if(abs(f0-q$F_external_floor)>1e-8 || abs(fa-mean(af+ef))>1e-8 ||
       !is.finite(fc) || fc>q$Fmsy+1e-9 || abs(fc-q$Fmsy)>1e-4 ||
       abs(q$quota_kg/(q$anchor_2025_t*1000)-q$maximum_future_to_anchor_ratio)>1e-10)
      stop("FMSY inverse metadata failed validation: ",st)
  }
  invisible(TRUE)
}
smart31_final_stock_audit <- function(catches, runs, limits) {
  if(!nrow(limits)) return(tibble::tibble())
  ids <- c("scenario_id","method","replicate")
  runs <- unique(runs[runs$representative_period==.smart31_case$periods$future & runs$feasible,ids,drop=FALSE])
  lim <- limits[limits$YEAR==.smart31_years$future_start,,drop=FALSE]
  result <- list()
  for(i in seq_len(nrow(runs))) {
    keep <- catches$representative_period==.smart31_case$periods$future
    for(nm in ids) keep <- keep & catches[[nm]]==runs[[nm]][i]
    kg <- smart31_quota_catches(catches[keep,,drop=FALSE],paste0("STOCK::",lim$assessment_stock))
    z <- data.frame(runs[rep(i,nrow(lim)),,drop=FALSE],assessment_stock=lim$assessment_stock,
      Species=lim$Species,scenario_catch_kg=unname(kg),fmsy_catch_limit_kg=lim$quota_kg)
    z$F_calibrated <- vapply(seq_len(nrow(lim)),function(j)smart31_monitor_f_at_catch(kg[j],lim[j,,drop=FALSE]),numeric(1))
    z$Fmsy <- lim$Fmsy;z$F_over_Fmsy<-z$F_calibrated/z$Fmsy
    z$bound_respected <- z$scenario_catch_kg<=z$fmsy_catch_limit_kg*(1+quota_tolerance_fraction)+1e-6
    z$F_bound_respected <- is.finite(z$F_calibrated) & z$F_calibrated<=z$Fmsy+1e-8
    result[[i]] <- z
  }
  out <- dplyr::bind_rows(result)
  if(nrow(out)!=nrow(runs)*nrow(lim) || !nrow(out) || !all(out$bound_respected & out$F_bound_respected)) {
    print(out);stop("Independent final stock/F audit failed.")
  }
  out
}

smart31_stock_accounting_tests <- function() {
  fixture <- new.env(parent = environment())
  fixture$stock_constraint_scope <- data.frame(Species = "NEP", GSA_code = c("GSA09", "GSA11"),
    assessment_stock = c("NEP_GSA09", "NEP_GSA11"))
  for (nm in c("smart31_quota_species_code", "smart31_build_quota_rate", "smart31_quota_catches")) {
    fun <- get(nm, envir = parent.env(fixture)); environment(fun) <- fixture
    assign(nm, fun, envir = fixture)
    assign(nm, fun, envir = environment())
  }


  keys<-c("NEP","STOCK::NEP_GSA09","STOCK::NEP_GSA11")
  cr<-matrix(c(2,3,5,7),ncol=1,dimnames=list(NULL,"NEP"))
  gsa<-c("GSA09","GSA10","GSA111","GSA112")
  qr<-smart31_build_quota_rate(cr,gsa,keys)
  stopifnot(identical(unname(qr),matrix(c(2,3,5,7,2,0,0,0,0,0,5,7),nrow=4)))
  ctx<-list(catch_rate=cr,quota_rate=qr,quota_species=keys)
  E<-c(10,20,30,40)
  full<-data.frame(Species="NEP",GSA_code=gsa,W=as.numeric(cr)*E)
  expected<-c(510,20,430)
  stopifnot(isTRUE(all.equal(unname(smart31_quota_catches(full,keys)),expected)),
    isTRUE(all.equal(unname(smart31_quota_exposure(ctx,1:4,E)),expected)),sum(full$W)==510)

  newE<-c(12,20,28,40);oldm<-c(.8,1,.7,.9);newm<-c(.75,1,.73,.9)
  delta<-colSums(qr*as.numeric(newE*newm-E*oldm))
  old<-smart31_quota_catches(transform(full,W=as.numeric(cr)*E*oldm),keys)
  new<-smart31_quota_catches(transform(full,W=as.numeric(cr)*newE*newm),keys)
  stopifnot(isTRUE(all.equal(unname(old+delta),unname(new),tolerance=1e-12)))
  fixed<-data.frame(Species=c("NEP","NEP"),GSA_code=c("GSA09","GSA112"),W=c(4,6))
  stopifnot(isTRUE(all.equal(unname(smart31_quota_catches(rbind(full,fixed),keys)),expected+c(10,4,6))))
  message("Stock accounting checks passed: NEP09/11 separation, GSA111/112 pooling, NEP10 exclusion, fixed catches, coupled deltas, unchanged physical total.")
  invisible(TRUE)
}
