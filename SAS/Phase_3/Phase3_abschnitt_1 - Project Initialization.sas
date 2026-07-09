/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.1 - Project Initialization
*
* Purpose:
*   Initialize the SAS session for the machine learning workflow.
*
* Contents:
*   - SAS system options
*   - Library definitions
*   - Global macro variables
*   - ODS configuration
*   - Random seed
*
**************************************************************************/

/*-----------------------------------------------------------------------
* 1. SAS System Options
*-----------------------------------------------------------------------*/

options
    nocenter
    validvarname=v7
    validmemname=extend
    compress=yes
    fullstimer
    mprint
    mlogic
    symbolgen
    msglevel=i
    formchar="|----|+|---+=|-/\<>*"
    threads;

/*-----------------------------------------------------------------------
* 2. ODS Graphics
*-----------------------------------------------------------------------*/

ods graphics on;

/*-----------------------------------------------------------------------
* 3. Global Project Directories
*-----------------------------------------------------------------------*/

%let PROJECT_ROOT = C:\REPORT;

%let DATA_DIR     = &PROJECT_ROOT.\Data;
%let MODEL_DIR    = &PROJECT_ROOT.\Models;
%let OUTPUT_DIR   = &PROJECT_ROOT.\Output;
%let REPORT_DIR   = &PROJECT_ROOT.\Reports;
%let LOG_DIR      = &PROJECT_ROOT.\Logs;

/*-----------------------------------------------------------------------
* 4. SAS Libraries
*-----------------------------------------------------------------------*/

libname RAWDATA  "&DATA_DIR.";
libname MODEL    "&MODEL_DIR.";
libname REPORT   "&REPORT_DIR.";
libname OUTPUT   "&OUTPUT_DIR.";

/*-----------------------------------------------------------------------
* 5. Global Random Seed
*
* Equivalent to:
*
*     numpy.random.seed(...)
*     random.seed(...)
*
*-----------------------------------------------------------------------*/

%let RANDOM_SEED = 20250506;

/*-----------------------------------------------------------------------
* 6. Machine Learning Parameters
*-----------------------------------------------------------------------*/

%let TRAIN_RATIO = 0.80;
%let VALID_RATIO = 0.20;

%let KFOLDS      = 5;
%let MAX_ITER    = 100;

%let NTHREADS    = 8;

/*-----------------------------------------------------------------------
* 7. Default Output Names
*-----------------------------------------------------------------------*/

%let DATA_FREQ = Frequency_ML;
%let DATA_SEV  = Severity_ML;

%let MODEL_FREQ = GBM_Frequency;
%let MODEL_SEV  = GBM_Severity;

/*-----------------------------------------------------------------------
* 8. Helper Macro
*
* Print section headers into the SAS log.
*-----------------------------------------------------------------------*/

%macro section(title);

    %put;
    %put ============================================================;
    %put &title;
    %put ============================================================;
    %put;

%mend section;

/*-----------------------------------------------------------------------
* 9. Start Message
*-----------------------------------------------------------------------*/

%section(Phase 3 - Machine Learning Modelling);

%put Project Directory : &PROJECT_ROOT.;
%put Data Directory    : &DATA_DIR.;
%put Output Directory  : &OUTPUT_DIR.;
%put Model Directory   : &MODEL_DIR.;
%put Random Seed       : &RANDOM_SEED.;
%put Number of Threads : &NTHREADS.;

/*-----------------------------------------------------------------------
* 10. Initialize Random Number Generator
*-----------------------------------------------------------------------*/

data _null_;
    call streaminit(&RANDOM_SEED.);
run;

/*-----------------------------------------------------------------------
* 11. Display SAS Environment
*-----------------------------------------------------------------------*/

proc options
    option=(threads compress validvarname);
run;

title;
footnote;
