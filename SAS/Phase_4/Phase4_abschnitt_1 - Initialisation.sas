/**************************************************************************
 * Project      : SHAP Phase 4 Analysis – freMTPL Claim Frequency Modelling
 * Phase        : 4
 * Section      : 1 – Initialisation
 *
 * Purpose
 * -------
 * Initialise the SAS session, define global options, library references,
 * file paths and project-wide macro variables used throughout the analysis.
 *
 * Python Equivalent
 * -----------------
 * - import statements
 * - logging configuration
 * - global constants
 * - pathlib.Path objects
 **************************************************************************/


/**************************************************************************
 * SECTION 1.1 – SAS System Options
 *
 * Enable useful debugging information during development.
 **************************************************************************/

options
        nocenter
        nodate
        nonumber
        validvarname=v7
        missing='.'
        mprint
        mlogic
        symbolgen
        fullstimer;

/**************************************************************************
 * SECTION 1.2 – Project Root Directory
 *
 * NOTE:
 * Change PROJECT_ROOT to your local environment if required.
 **************************************************************************/

%let PROJECT_ROOT = C:/report;


/**************************************************************************
 * SECTION 1.3 – Input and Output Paths
 *
 * Equivalent to Python pathlib.Path objects.
 **************************************************************************/

%let DATA_FILE =
&PROJECT_ROOT./freMTPLfreq_sev_data.csv;

%let OUTPUT_DIR =
&PROJECT_ROOT./shap_output;


/**************************************************************************
 * SECTION 1.4 – Create Output Directory (if necessary)
 **************************************************************************/

options dlcreatedir;

libname OUT "&OUTPUT_DIR.";

libname OUT clear;


/**************************************************************************
 * SECTION 1.5 – Library References
 *
 * WORK     : temporary datasets
 * OUTLIB   : output datasets
 **************************************************************************/

libname PROJECT "&PROJECT_ROOT.";
libname OUTPUT  "&OUTPUT_DIR.";


/**************************************************************************
 * SECTION 1.6 – Global Model Constants
 *
 * Equivalent to Python constants.
 **************************************************************************/

%let RANDOM_SEED = 42;
%let TEST_SIZE   = 0.20;


/*---------------------------------------------------------------*
 | XGBoost Hyperparameters (documentation only)
 |
 | NOTE:
 | These parameters are used later in PROC GRADBOOST (SAS Viya)
 | or PROC PYTHON. They are stored as macro variables to allow
 | central maintenance.
 *---------------------------------------------------------------*/

%let XGB_OBJECTIVE        = count:poisson;
%let XGB_MAX_DEPTH        = 4;
%let XGB_LEARNING_RATE    = 0.05;
%let XGB_N_ESTIMATORS     = 300;
%let XGB_SUBSAMPLE        = 0.80;
%let XGB_COLSAMPLE        = 0.80;
%let XGB_MIN_CHILD_WEIGHT = 20;
%let XGB_REG_ALPHA        = 0.10;
%let XGB_REG_LAMBDA       = 1.00;


/**************************************************************************
 * SECTION 1.7 – Variable Lists
 *
 * Equivalent to:
 * NUMERIC_FEATURES
 * CATEGORIC_FEATURES
 * MODEL_FEATURES
 **************************************************************************/

%let NUMERIC_FEATURES =
        VehPower
        VehAge
        DrivAge
        BonusMalus
        Density;

%let CATEGORICAL_FEATURES =
        VehBrand
        VehGas
        Area
        Region;

%let MODEL_FEATURES =
        VehPower
        VehAge
        DrivAge
        BonusMalus
        Density
        VehBrand
        VehGas
        Area
        Region
        LogDensity
        BonusMalusCapped;


/**************************************************************************
 * SECTION 1.8 – Log Initialisation
 *
 * SAS automatically writes to the LOG window. The following messages
 * reproduce the intent of Python's logging module.
 **************************************************************************/

%put NOTE: ==========================================================;
%put NOTE: SHAP Phase 4 Analysis Initialisation Started.;
%put NOTE: Project Root : &PROJECT_ROOT.;
%put NOTE: Data File    : &DATA_FILE.;
%put NOTE: Output Dir   : &OUTPUT_DIR.;
%put NOTE: Random Seed  : &RANDOM_SEED.;
%put NOTE: Test Size    : &TEST_SIZE.;
%put NOTE: ==========================================================;


/**************************************************************************
 * END OF SECTION 1
 **************************************************************************/
