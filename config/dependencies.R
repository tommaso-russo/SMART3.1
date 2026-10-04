# Direct dependencies; transitive packages are resolved by the package installer.
smart31_dependencies <- list(
  common=c("rmarkdown","knitr","yaml","dplyr","tidyr","tibble","purrr","ggplot2","sf","scales","readr"),
  step1=c("chron","data.table","fasterize","fields","ggmap","ggpubr","ggrepel","ggsci","ggspatial",
    "gtsummary","gridExtra","irr","mapdata","maps","mapview","marmap","mgcv","nnls","openxlsx",
    "patchwork","PBSmapping","prioritizr","progress","raster","reshape2","rpart","stringr","terra",
    "tidyterra","webr","viridis","png","ggimage","ggdendro","readxl","units"),
  step2=c("maps","slam","Rglpk","ragg","rstudioapi"),
  step3=c("openxlsx","readxl"),
  tests=c("testthat","withr","slam","Rglpk","maps","openxlsx","readxl"),
  reproducibility="renv"
)
# join relationship checks and pick() require dplyr >= 1.1.1.
smart31_minimum_versions <- c(dplyr="1.1.1",ggplot2="3.4.0",testthat="3.0.0")
smart31_minimum_R <- "4.3.0"
