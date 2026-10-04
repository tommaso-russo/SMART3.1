test_that('unreviewed cases and misspelled controls stop before data loading', {
 withr::local_dir(repo_root)
 expect_error(smart31_load_case('config/case_study.example.R'),'configured = TRUE')
 c <- example_case;c$controls$step2$arallel_enabled <- TRUE
 expect_error(smart31_stage_config(c,'step2'),'Unknown step2 controls')
})
test_that('the calendar can move and use a different future interval', {
 withr::local_dir(repo_root)
 c <- example_case;c$configured<-TRUE;c$calendar<-list(anchor=2030L,baseline=2031L,future=2032:2034,calibration=2027:2029)
 c$domain$years_to_submit <- 2025:2030
 x <- smart31_load_case(write_case(c))
 expect_equal(x$periods,list(baseline='2031',future='2032_2034'))
 expect_equal(x$calibration_id,'median_2027_2029_landings_share')
 expect_equal(x$scenario_codes$baseline,'BASELINE_2031')
 c$calendar$future<-c(2032L,2034L)
 expect_error(smart31_load_case(write_case(c)),'consecutive')
})
test_that('scenario closures and bonuses are independent configuration choices', {
 withr::local_dir(repo_root)
 make <- smart31_materialise_scenarios;environment(make)<-engine
 c<-example_case;c$scenarios$season_bonus[c$scenarios$role=='B']<-.1
 s<-make(c,c('cell1','cell2'),character(),list(maximum_sweeps=7L))
 expect_equal(vapply(s,`[[`,character(1),'scenario_id'),c('BASELINE','SCENARIO_A','SCENARIO_B'))
 expect_equal(length(s[[2]]$compensation_mechanisms),0)
 expect_equal(s[[3]]$compensation_mechanisms[[1]]$extra_days_fraction,.1)
 expect_equal(s[[3]]$closures[[2]]$months,10L)
 expect_equal(s[[3]]$parameters$maximum_sweeps,7L)
})
test_that('result metadata must match selected stocks, catch policy and calendar', {
 withr::local_dir(repo_root)
 c<-example_case;c$management$fmsy_stocks<-'HKE_EXAMPLE'
 lim<-data.frame(assessment_stock='HKE_EXAMPLE',YEAR=c$calendar$future)
 result<-list(metadata=list(workflow_schema='SMART31.generic.1',ordinary_catch_quotas_enforced=FALSE,
    enforced_fmsy_stocks='HKE_EXAMPLE',calendar=c$calendar),fmsy_catch_limits=lim)
 expect_true(smart31_validate_step2_policy(result,c))
 c$management$fmsy_stocks<-'NEP_EXAMPLE'
 expect_error(smart31_validate_step2_policy(result,c),'policy mismatch')
 c$management$fmsy_stocks<-'HKE_EXAMPLE';c$management$enforce_catch_quotas<-TRUE
 expect_error(smart31_validate_step2_policy(result,c),'policy mismatch')
 expect_error(smart31_validate_selected_limits(lim[-1,], 'HKE_EXAMPLE',c$calendar$future),'coverage')
})
test_that('all reports contain unique populated and parseable R chunks', {
 withr::local_dir(repo_root)
 for(stage in c('step1','step2','step3','economic_audit')) {
  report<-readLines(file.path('workflows',paste0(stage,'.Rmd')))
  refs<-sub('^```\\{r ([^,}]+).*','\\1',grep('^```\\{r ',report,value=TRUE))
  chunks<-smart31_workflow_chunks(stage)
  expect_identical(names(chunks),refs)
  expect_true(all(vapply(chunks,function(x) any(nzchar(trimws(x))),logical(1))))
  expect_false(any(grepl('knitr::read_chunk',report,fixed=TRUE)))
  for(code in chunks) expect_error(parse(text=code),NA)
 }
})
test_that('commercial age proportions are optional external inputs', {
 withr::local_dir(repo_root)
 expect_equal(nrow(smart31_commercial_age_input('')),0L)
 file <- tempfile(fileext='.csv');on.exit(unlink(file))
 x <- data.frame(Species='TEST',Age=0:2,report_baseline_proportion=c(.2,.5,.3))
 write.csv(x,file,row.names=FALSE)
 expect_equal(sum(smart31_commercial_age_input(file)$report_baseline_proportion),1)
 x$report_baseline_proportion[1]<-.4
 write.csv(x,file,row.names=FALSE)
 expect_error(smart31_commercial_age_input(file),'sum to one')
})
