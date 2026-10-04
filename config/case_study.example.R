# Copy to case_study.R (ignored by Git), supply local inputs, review every setting.
# This is a configuration template, not an official management allocation.
case <- list(
  configured = FALSE,
  case_id = "my_case",
  calendar = list(anchor=2025L, baseline=2026L, future=2027:2030, calibration=2022:2024),
  domain = list(years_to_submit=2020:2025, species_to_submit=c("HKE","NEP"),
    gears_to_submit=c("OTB","LLS"), CS_gsas=c("GSA09","GSA10","GSA111","GSA112"),
    spatial_resolution_km=2, fts=c("DTS","HOK"), CS_crs=4326, country="ITA",
    country_aliases=c("ITA","IT"), map_regions="Italy"),
  paths = list(
    reference_directory="data/reference",
    gsa_file="InputData/areas/areas.shp", land_file=NULL,
    bathymetry_file="InputData/bathymetry.rds",
    fdi=list(A="InputData/fdi/A.rds",G="InputData/fdi/G.rds",H="InputData/fdi/H.rds",I="InputData/fdi/I.rds"),
    fuel_prices_file="InputData/fuel_prices.csv",
    effort_pattern="InputData/effort/%d.rds", landings_pattern="InputData/landings/%d.rds",
    medits_ta="InputData/survey/TA.xlsx", medits_tb="InputData/survey/TB.xlsx",medits_tc="InputData/survey/TC.xlsx",
    stock_parameters_file="InputData/stock_parameters.xlsx",
    commercial_age_baseline="", # Empty explicitly selects the existing MEDITS fallback.
    survey_cache="checkpoints/survey",
    # Choose the exact bundle / result after each upstream run; no latest-file lookup.
    step1_bundle="", step2_result="", economic_audit="",
    cessation_file="", catch_quotas="InputData/catch_quotas.csv", effort_quotas="InputData/effort_quotas.csv",
    fmsy_limits="", constraint_scope="",
    economic_reference="InputData/economic_reference.xlsx",
    step3=list(
      stock_area_crosswalk_file="InputData/assessment/stock_area_crosswalk.csv",
      stock_age_parameters_file="InputData/assessment/stock_age_parameters.csv",
      commercial_age_baseline_file="InputData/assessment/commercial_age_baseline.csv",
      stock_reference_points_file="InputData/assessment/stock_reference_points.csv",
      single_stock_advice_file="InputData/assessment/single_stock_advice.csv",
      stock_reference_points_provenance_file="InputData/assessment/stock_reference_points_provenance.csv",
      assessment_stock_crosswalk_file="InputData/assessment/assessment_stock_crosswalk.csv",
      assessment_history_file="InputData/assessment/assessment_history.csv",
      assessment_anchor_2025_file="InputData/assessment/assessment_anchor.csv",
      assessment_total_catch_file="InputData/assessment/assessment_total_catch.csv",
      fdi_table_a_2024_2025_file="InputData/fdi/Table_A_CATCH.xlsx",
      annex_f_target_file="InputData/assessment/annex_F_target.csv",
      calibration_expected_file="InputData/assessment/calibration_expected.csv",
      ara_ars_authorized_vessels_file="InputData/authorized_vessels.xlsx"
    )
  ),
  survey=list(areas=c(9L,10L,11L),years=2020:2025,sheet=1L,
    species_crosswalk=data.frame(medits_genus=c("MERL","NEPR"),medits_species=c("MER","NOR"),Species=c("HKE","NEP"))),
  economics=list(
    gear_crosswalk=data.frame(Gear=c("OTB","LLS"),reference_fishing_technique_code=c("DTS","HOK")),
    length_crosswalk=data.frame(VL=c("VL0006","VL0612","VL1215","VL1518","VL1824","VL2440","VL40XX"),
      reference_vessel_length_class=c("VL0006","VL0612","VL1218","VL1218","VL1824","VL2440","VL40XX")),
    segment_fallbacks=data.frame(Gear=character(),VL=character(),
      fallback_fishing_technique_code=character(),fallback_vessel_length_class=character())
  ),
  expected_step1_md5="", expected_fdi_md5="",
  step1_controls=list(steaming_speed=8.5*1.852, quantile_thrB=0.1, quantile_Logit=0.05,
    quantile_Effort=0.05, quantile_effort_fleet=0.1, thr_depth=2000,
    economic_country_code="ITA", run_age_module=TRUE, fishing_time_elasticity_default=0.5,
    steaming_to_fishing_fuel_ratio_default=66/72.8, reuse_checkpoints=TRUE),
  management=list(
    # Empty = no FMSY stock constraints; select assessment IDs from constraint_scope.csv.
    # Example: c("NEP_GSA11"). Every selected stock needs a complete annual limit series.
    fmsy_stocks=character(), enforce_catch_quotas=FALSE,
    fuel_price_eur_l=NULL, depth_limit_m=800, regulated_gear="OTB",
    effort_length_classes=c("VL0612","VL1218","VL1824","VL2440"),

    source="User-defined scenario assumptions; supply provenance"
  ),
  # FDI / MEDITS adapters and the two-group Annex-style report are retained.
  reporting=list(authorization_sheet="Authorized_vessels",authorization_skip=3L,expected_authorized_vessels=NULL,
    effort_groups=c("Authorized group","Other vessels"),
    effort_group_codes=c("GROUP1","GROUP2"),
    assessment_source="Supply assessment source and vintage",
    reference_point_source="Supply reference-point source and vintage",
    catch_only_stock_ids=character(),assessment_only_stocks=character(),emu="EMU2",
    cfr_prefix="ITA", cfr_numeric_width=9L),
  scenarios=data.frame(
    role=c("baseline","A","B"),scenario_id=c("BASELINE","SCENARIO_A","SCENARIO_B"),
    cm_status=c("without_cm","without_cm","with_cm"),method="both",
    depth_closure=c(TRUE,TRUE,TRUE),closed_months=I(list(integer(),integer(),10L)),
    depth_bonus=c(0,0,0),season_bonus=c(0,0,0),cessation_bonus=c(0,0,0)
  ),
  controls=list(step1=list(),step2=list(maximum_sweeps=20L,n_replicates=3L,parallel_enabled=FALSE,parallel_workers=4L),
    step3=list(),economic_audit=list())
)
