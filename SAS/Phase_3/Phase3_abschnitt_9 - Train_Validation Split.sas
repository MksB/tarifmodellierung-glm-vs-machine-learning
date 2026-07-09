/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.9 - Train / Validation Split
*
* Purpose:
*   Create reproducible train-validation split using PROC SURVEYSELECT.
*
*   Equivalent to Python:
*       train_test_split(..., stratify=y)
*
* Input:
*      WORK.ML_BINNED
*
* Output:
*      WORK.ML_TRAIN
*      WORK.ML_VALID
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.9 - Train / Validation Split";

/*-----------------------------------------------------------------------
* Step 1 : Create stratification variable
*-----------------------------------------------------------------------*/

data work.ML_Split_Base;

    set work.ML_Binned;

    /*---------------------------------------------------------------
      Stratification logic (proxy for stratified sampling)
      based on claim frequency class
    ---------------------------------------------------------------*/

    if ClaimNb = 0 then Stratum = "0_NoClaim";
    else if ClaimNb = 1 then Stratum = "1_SingleClaim";
    else if ClaimNb <= 3 then Stratum = "2_LowFreq";
    else Stratum = "3_HighFreq";

run;


/*-----------------------------------------------------------------------
* Step 2 : Train sample (80%)
*-----------------------------------------------------------------------*/

proc surveyselect
    data=work.ML_Split_Base
    out=work.ML_Train
    method=srs
    samprate=0.8
    seed=20250506
    outall;

    strata Stratum;

run;


/*-----------------------------------------------------------------------
* Step 3 : Split train / validation
*-----------------------------------------------------------------------*/

data work.ML_Train_Final
     work.ML_Valid;

    set work.ML_Train;

    if selected = 1 then output work.ML_Train_Final;
    else output work.ML_Valid;

run;


/*-----------------------------------------------------------------------
* Step 4 : Check split proportions
*-----------------------------------------------------------------------*/

proc sql;

    title3 "Train / Validation Split Check";

    select

        (select count(*) from work.ML_Train_Final) as Train_Count,
        (select count(*) from work.ML_Valid)       as Valid_Count,

        calculated Train_Count /
        (calculated Train_Count + calculated Valid_Count)
            as Train_Ratio format=8.4;

quit;


/*-----------------------------------------------------------------------
* Step 5 : Stratum distribution check
*-----------------------------------------------------------------------*/

title3 "Stratum Distribution - Train";

proc freq
    data=work.ML_Train_Final;

    tables Stratum / missing;

run;


title3 "Stratum Distribution - Validation";

proc freq
    data=work.ML_Valid;

    tables Stratum / missing;

run;


/*-----------------------------------------------------------------------
* Step 6 : Exposure balance check
*-----------------------------------------------------------------------*/

proc means
    data=work.ML_Train_Final
    mean sum;

    var Exposure ClaimNb ClaimTotal;

run;

proc means
    data=work.ML_Valid
    mean sum;

    var Exposure ClaimNb ClaimTotal;

run;


/*-----------------------------------------------------------------------
* Step 7 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.ML_Train_Final end=eof;

    if eof then do;

        put "========================================================";
        put " TRAIN / VALIDATION SPLIT COMPLETED";
        put "========================================================";
        put " Train Dataset   : WORK.ML_TRAIN_FINAL";
        put " Validation Set  : WORK.ML_VALID";
        put " Split Method    : STRATIFIED SRS (PROC SURVEYSELECT)";
        put " Ratio           : 80 / 20";
        put " Seed            : 20250506";
        put "========================================================";

    end;

run;

title;
