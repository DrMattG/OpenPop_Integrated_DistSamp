library(tidyverse)

# SETUP #
#-------#

## Source all functions in "R" folder
sourceDir <- function(path, trace = TRUE, ...) {
  for (nm in list.files(path, pattern = "[.][RrSsQq]$")) {
    if(trace) cat(nm,":")
    source(file.path(path, nm), ...)
    if(trace) cat("\n")
  }
}
sourceDir('R')


## Set switches 

# (Re-)downloading data
# downloadData <- FALSE
downloadData <- TRUE

# Recruitment per adult or per adult female
R_perF <- FALSE

# Drop observations of juveniles with no adults present
R_parent_drop0 <- TRUE

# Aggregation level for reproduction data
# NOTE: if this is not defined, will default to group level
sumR.Level <- "line" # Summing at the line level

# Random effects shared across areas
shareRE <- TRUE

# Time variation in survival
survVarT <- FALSE

# Rodent covariate on reproduction
fitRodentCov <- FALSE

# DOWNLOAD/FETCH DATA #
#---------------------#

if(downloadData){
  #Rype_arkiv <- downloadLN(datasets = "Fjellstyrene", versions = 1.6, save = TRUE)
  Rype_arkiv <- downloadLN(datasets = c("Fjellstyrene", "Statskog", "FeFo"), versions = c(1.7, 1.8, 1.12), save = TRUE)
}else{
  stop("downloadData = FALSE not supported yet. There is an issue with encoding when using LivingNorwayR::initializeDwCArchive() that needs to be resolved first.")
  #Rype_arkiv <- initializeDwCArchive("data/Rype_arkiv.zip")
}


# WRANGLE LINE TRANSECT DATA #
#----------------------------#

## Set localities/areas and time period of interest
localities <- listLocations()
areas <- listAreas()
minYear <- 2007
maxYear <- 2021

## List duplicate transects to remove
duplTransects <- listDuplTransects()

## Extract transect and observational data from DwC archive
LT_data <- wrangleData_LineTrans(DwC_archive_list = Rype_arkiv, 
                                 duplTransects = duplTransects,
                                 #localities = localities,
                                 areas = areas,
                                 areaAggregation = TRUE,
                                 minYear = minYear, maxYear = maxYear)


# WRANGLE KNOWN FATE CMR DATA #
#-----------------------------#

## Read in and reformat CMR data
d_cmr <- wrangleData_CMR(minYear = minYear)


# WRANGLE RODENT DATA #
#---------------------#

## Load and reformat rodent data
d_rodent <- wrangleData_Rodent(duplTransects = duplTransects,
                               #localities = localities,
                               areas = areas,
                               areaAggregation = TRUE,
                               minYear = minYear, maxYear = maxYear)


# PREPARE INPUT DATA FOR INTEGRATED MODEL #
#-----------------------------------------#

## Reformat data into vector/array list for analysis with Nimble
input_data <- prepareInputData(d_trans = LT_data$d_trans, 
                               d_obs = LT_data$d_obs,
                               d_cmr = d_cmr,
                               d_rodent = d_rodent,
                               #localities = localities, 
                               areas = areas,
                               areaAggregation = TRUE,
                               excl_neverObs = TRUE,
                               R_perF = R_perF,
                               R_parent_drop0 = R_parent_drop0,
                               sumR.Level = "line",
                               dataVSconstants = TRUE,
                               save = TRUE)


# MODEL SETUP #
#-------------#

## Determine correct code path
code.path <- selectCodePath(shareRE = shareRE,
                            survVarT = survVarT)

## Setup for model using nimbleDistance::dHN
model_setup <- setupModel(modelCode.path = code.path,
                          customDist = TRUE,
                          R_perF = R_perF,
                          shareRE = shareRE, 
                          survVarT = survVarT, 
                          fitRodentCov = fitRodentCov,
                          nim.data = input_data$nim.data,
                          nim.constants = input_data$nim.constants,
                          testRun = TRUE, nchains = 3,
                          initVals.seed = 0)

# MODEL (TEST) RUN #
#------------------#
#t.start <- Sys.time()
IDSM.out <- nimbleMCMC(code = model_setup$modelCode,
                       data = input_data$nim.data, 
                       constants = input_data$nim.constants,
                       inits = model_setup$initVals, 
                       monitors = model_setup$modelParams,
                       nchains = model_setup$mcmcParams$nchains, 
                       niter = model_setup$mcmcParams$niter, 
                       nburnin = model_setup$mcmcParams$nburn, 
                       thin = model_setup$mcmcParams$nthin, 
                       samplesAsCodaMCMC = TRUE, 
                       setSeed = 0)
#Sys.time() - t.start

saveRDS(IDSM.out, file = 'rypeIDSM_dHN_multiArea_realData_Lierne.rds')


# TIDY UP POSTERIOR SAMPLES #
#---------------------------#

IDSM.out.tidy <- tidySamples(IDSM.out = IDSM.out, save = TRUE)


# OPTIONAL: MCMC TRACE PLOTS #
#----------------------------#

plotMCMCTraces(mcmc.out = IDSM.out.tidy,
               fitRodentCov = fitRodentCov)


# OPTIONAL: TIME SERIES PLOTS #
#-----------------------------#

plotTimeSeries(mcmc.out = IDSM.out.tidy, 
               N_areas = input_data$nim.constant$N_areas, 
               area_names = input_data$nim.constant$area_names, 
               N_sites = input_data$nim.constant$N_sites, 
               min_years = input_data$nim.constant$min_years, 
               max_years = input_data$nim.constant$max_years, 
               minYear = minYear, maxYear = maxYear,
               VitalRates = TRUE, DetectParams = TRUE, Densities = TRUE)


# OPTIONAL: PLOT VITAL RATE POSTERIORS #
#--------------------------------------#

plotPosteriorDens_VR(mcmc.out = IDSM.out.tidy,
                     N_areas = input_data$nim.constant$N_areas, 
                     area_names = input_data$nim.constant$area_names, 
                     N_years = input_data$nim.constant$N_years,
                     minYear = minYear,
                     survAreaIdx = input_data$nim.constants$SurvAreaIdx,
                     survVarT = survVarT,
                     fitRodentCov = fitRodentCov) 


# OPTIONAL: PLOT COVARIATE PREDICTIONS #
#--------------------------------------#

if(fitRodentCov){
  plotCovPrediction(mcmc.out = IDSM.out.tidy,
                    effectParam = "betaR.R",
                    covName = "Rodent occupancy",
                    minCov = 0, 
                    maxCov = 1,
                    N_areas = input_data$nim.constant$N_areas, 
                    area_names = input_data$nim.constant$area_names,
                    fitRodentCov = fitRodentCov)
}


# OPTIONAL: MAP PLOTS #
#---------------------#

## Make map of Norwegian municipalities ("fylke")
NorwayMunic.map <- setupMap_NorwayMunic(shp.path = "data/Kommuner_2018_WGS84/Kommuner_2018_WGS84.shp",
                                        d_trans = LT_data$d_trans,
                                        areas = areas, areaAggregation = TRUE)

## Plot population growth rate, density, and vital rates on map
plotMaps(mcmc.out = IDSM.out.tidy, 
         mapNM = NorwayMunic.map,
         N_areas = input_data$nim.constant$N_areas, 
         area_names = input_data$nim.constant$area_names, 
         N_sites = input_data$nim.constant$N_sites, 
         min_years = input_data$nim.constant$min_years, 
         max_years = input_data$nim.constant$max_years, 
         minYear = minYear, maxYear = maxYear,
         fitRodentCov = fitRodentCov)


# OPTIONAL: MODEL COMPARISON (PLOTS) #
#------------------------------------#

# modelComp <- plotModelComparison(modelPaths = c("rypeIDSM_realData_Lierne.rds", 
#                                                 "rypeIDSM_dHN_realData_Lierne.rds"), 
#                                  modelChars = c("Zeroes trick", "dHN"), 
#                                  N_sites = 58, N_years = 6,
#                                  plotPath = "Plots/ModelCompTest",
#                                  returnData = FALSE)

