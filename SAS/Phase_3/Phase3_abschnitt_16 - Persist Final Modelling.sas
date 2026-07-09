/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.16 - Persist Final Models
*
* Purpose:
*   Persist the final Frequency and Severity Gradient Boosting models.
*
* Compatible with:
*      SAS 9.4
*      SAS Viya
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.16 - Persist Final Models";

/*-----------------------------------------------------------------------
* Step 1 : Define permanent library
*-----------------------------------------------------------------------*/

libname MODELLIB "J:\FREELANCE\Versicherung\SAS\Models";

/*-----------------------------------------------------------------------
* Step 2 : Save Frequency Model
*-----------------------------------------------------------------------*/

data MODELLIB.FREQ_MODEL_GBM;
    set WORK.FREQ_MODEL;
run;

/*-----------------------------------------------------------------------
* Step 3 : Save Severity Model
*-----------------------------------------------------------------------*/

data MODELLIB.SEV_MODEL_GBM;
    set WORK.SEV_MODEL;
run;

/*-----------------------------------------------------------------------
* Step 4 : Save Hyperparameter Table
*-----------------------------------------------------------------------*/

data MODELLIB.BEST_PARAMETERS;
    set WORK.BEST_PARAMS;
run;

/*-----------------------------------------------------------------------
* Step 5 : Save Variable Importance
*-----------------------------------------------------------------------*/

data MODELLIB.VARIMP_FREQUENCY;
    set WORK.VARIMP_FREQ;
run;

data MODELLIB.VARIMP_SEVERITY;
    set WORK.VARIMP_SEV;
run;

/*-----------------------------------------------------------------------
* Step 6 : Save Model Metadata
*-----------------------------------------------------------------------*/

data MODELLIB.MODEL_METADATA;

    length
        ModelName $40
        Algorithm $30
        Target $30
        Distribution $20
        Created $25;

    Created = put(datetime(), datetime20.);

    ModelName    = "Frequency_GBM";
    Algorithm    = "PROC GRADBOOST";
    Target       = "Claim_Frequency";
    Distribution = "Poisson";
    output;

    ModelName    = "Severity_GBM";
    Algorithm    = "PROC GRADBOOST";
    Target       = "Claim_Severity";
    Distribution = "Gamma";
    output;

run;

/*-----------------------------------------------------------------------
* Step 7 : Verify stored models
*-----------------------------------------------------------------------*/

proc contents data=MODELLIB.FREQ_MODEL_GBM;
run;

proc contents data=MODELLIB.SEV_MODEL_GBM;
run;

/*-----------------------------------------------------------------------
* Step 8 : Log information
*-----------------------------------------------------------------------*/

data _null_;

    put "========================================================";
    put " FINAL ML MODELS SUCCESSFULLY STORED";
    put "========================================================";
    put " Library        : MODELIB";
    put " Frequency Model: FREQ_MODEL_GBM";
    put " Severity Model : SEV_MODEL_GBM";
    put " Metadata       : MODEL_METADATA";
    put " Hyperparameter : BEST_PARAMETERS";
    put "========================================================";

run;

title;
