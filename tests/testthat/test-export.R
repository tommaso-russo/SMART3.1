test_that('annual F export preserves values and rejects inconsistent vectors', {
 withr::local_dir(repo_root)
 sc<-unlist(example_case$scenario_codes,use.names=FALSE)
 x<-expand.grid(contract_scenario_code=sc,method=c('bayesian_dirichlet','stochastic_optimizer'),Age=0:2,stringsAsFactors=FALSE)
 x$replicate<-1L;x$assessment_stock<-'EXAMPLE';x$F_total<-seq_len(nrow(x))/100
 x$calibration<-example_case$calibration_id;x$calibration_valid<-TRUE
 x$representative_year_start<-ifelse(x$contract_scenario_code==sc[1],2026L,2027L)
 x$representative_year_end<-ifelse(x$contract_scenario_code==sc[1],2026L,2030L)
 periods<-data.frame(scenario=sc,start=c(2026,2027,2027),end=c(2026,2030,2030))
 out<-smart31_expand_f(x,example_case$calibration_id,1L,sc,periods)
 expect_equal(nrow(out),54)
 expect_setequal(out$YEAR,2026:2030)
 expect_equal(out$F[out$scenario=='A' & out$Age==1 & out$method=='stochastic_optimizer'],rep(x$F_total[x$contract_scenario_code=='A' & x$Age==1 & x$method=='stochastic_optimizer'],4))
 expect_error(smart31_expand_f(rbind(x,x[1,]),example_case$calibration_id,1,sc,periods),'Duplicate')
 x$calibration_valid[1]<-FALSE
 expect_error(smart31_expand_f(x,example_case$calibration_id,1,sc,periods),'Invalid calibration')
})
