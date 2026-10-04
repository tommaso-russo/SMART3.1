test_that('inherited synthetic regression gates remain active', {
 withr::local_dir(repo_root)
 for(nm in c('smart31_stock_accounting_tests','smart31_monitor_detail_regression_tests',
   'smart31_internal_tests','smart31_response_regression_tests',
   'smart31_repair_regression_tests')) {
  expect_error(suppressMessages(suppressWarnings(capture.output(get(nm,engine)()))),NA,info=nm)
 }
})
test_that('initial conditioning tests run before the coupled and LP wrappers', {
 withr::local_dir(repo_root)
 early <- smart31_workflow_functions('step2',before_chunk='step2-24-coupled-engine')
 for(nm in c('.smart31_case','.smart31_years','cfg','quota_tolerance_fraction','simulation_output_directory',
             'monitor_enabled','monitor_update_every_units','smart31_monitor_event'))
   assign(nm,get(nm,engine),early)
 source('R/stock_constraints.R',local=early)
 expect_error(suppressMessages(suppressWarnings(capture.output(early$smart31_initial_regression_tests()))),NA)
 # Internal fixtures must also work for a shifted, single-year planning horizon.
 shifted <- example_case
 shifted$calendar <- list(anchor=2030L,baseline=2031L,future=2032L,calibration=2027:2029)
 shifted$domain$years_to_submit <- 2025:2030
 shifted$configured <- TRUE
 shifted <- smart31_load_case(write_case(shifted))
 early$.smart31_case <- shifted
 early$.smart31_years <- smart31_year_values(shifted)
 expect_error(suppressMessages(suppressWarnings(capture.output(early$smart31_initial_regression_tests()))),NA)
 expect_error(suppressMessages(suppressWarnings(capture.output(early$smart31_monitor_detail_regression_tests()))),NA)
})
test_that('partitioned archives preserve detail and reject compact substitutes', {
 withr::local_dir(repo_root)
 expect_error(suppressMessages(suppressWarnings(capture.output(engine$smart31_archive_regression_tests(FALSE)))),NA)
})
test_that('ordinary quota and stock FMSY controls can be selected independently', {
 withr::local_dir(repo_root)
 engine$italian_catch_quotas <- tibble(Species='HKE',YEAR=2027:2030,quota_kg=10)
 engine$fmsy_catch_limits <- tibble(Species='HKE',assessment_stock='HKE_GSA09',YEAR=2027:2030,quota_kg=20,source='synthetic')
 engine$stock_constraint_scope <- data.frame(Species='HKE',assessment_stock='HKE_GSA09',GSA_code='GSA09')
 scenario<-list(representative_period=example_case$periods$future)
 fixed<-data.frame(Species='HKE',GSA_code='GSA09',W=2)
 engine$.smart31_case$management$enforce_catch_quotas<-FALSE
 q<-engine$build_catch_quota_limits(scenario,fixed)
 expect_equal(unique(q$limits$Species),'STOCK::HKE_GSA09')
 expect_equal(unique(q$reporting_limits$quota_kg),10)
 engine$.smart31_case$management$enforce_catch_quotas<-TRUE
 q<-engine$build_catch_quota_limits(scenario,fixed)
 expect_setequal(unique(q$limits$Species),c('STOCK::HKE_GSA09','HKE'))
 expect_true(q$feasible)
 fixed$W<-11
 expect_false(engine$build_catch_quota_limits(scenario,fixed)$feasible)
 engine$.smart31_case$management$enforce_catch_quotas<-FALSE
 engine$fmsy_catch_limits<-engine$fmsy_catch_limits[0,]
 q<-engine$build_catch_quota_limits(scenario,fixed)
 expect_true(q$feasible);expect_equal(nrow(q$limits),0)
})
test_that('partial F inversion preserves anchor and external floor', {
 withr::local_dir(repo_root)
 for(ratio in c(0,.25,1,2)) {
  v<-biology$solve_relative_partial_f(ratio,.3,.2,.15,50,1e-12)
  expect_true(is.finite(v$F_ITA_future))
  expect_equal(biology$g_partial(v$F_ITA_future,.2,.15),ratio*biology$g_partial(.3,.2,.15),tolerance=1e-10)
  if(ratio==1)expect_equal(v$F_ITA_future,.3,tolerance=1e-10)
  if(ratio==0)expect_equal(v$F_ITA_future,0)
 }
})
test_that('CFR normalization cannot relabel another country', {
 withr::local_dir(repo_root)
 expect_equal(biology$normalise_cfr(c('123','ITA000000123')),rep('ITA000000123',2))
 expect_error(biology$normalise_cfr('FRA000000123'),'prefix')
})
