# Synthetic validation only; no private inputs and no fleet simulations.
if(!file.exists('R/workflow_config.R')) stop('Run from the repository root.')
files<-c(list.files('R','[.]R$',recursive=TRUE,full.names=TRUE),list.files('scripts','[.]R$',full.names=TRUE))
for(file in files) parse(file)
if(!requireNamespace('testthat',quietly=TRUE)) stop('Install the tests dependency group.')
testthat::test_dir('tests/testthat',reporter='summary',stop_on_failure=TRUE)
