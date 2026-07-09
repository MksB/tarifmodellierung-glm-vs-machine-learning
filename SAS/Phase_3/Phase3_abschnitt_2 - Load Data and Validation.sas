/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.2 - Load Data and Validation
*
* Purpose:
*   Load the modelling dataset and perform initial validation before
*   feature engineering and machine learning.
*
* Input:
*      RAWDATA.DATA_CLEAN_SEV_FREQ_AGG
*
* Output:
*      WORK.ML_DATA
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.2 - Load Data and Validation";

/*-----------------------------------------------------------------------
* Step 1 : Load modelling dataset
*-----------------------------------------------------------------------*/

data work.ML_Data;

    set work.data;

run;


/*-----------------------------------------------------------------------
* Step 2 : Dataset information
*-----------------------------------------------------------------------*/

title3 "Dataset Information";

proc contents
    data=work.ML_Data
    varnum;
run;


/*-----------------------------------------------------------------------
* Step 3 : Dataset dimensions
*-----------------------------------------------------------------------*/

proc sql;

    title3 "Number of Observations and Variables";

    select

        count(*) as Number_of_Observations

    from work.ML_Data;

quit;


/*-----------------------------------------------------------------------
* Step 4 : Variable types
*-----------------------------------------------------------------------*/

proc contents
    data=work.ML_Data
    out=work.Variable_Metadata(keep=Name Type Length Format Label)
    noprint;
run;

title3 "Variable Metadata";

proc print
    data=work.Variable_Metadata
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Step 5 : Missing value analysis
*-----------------------------------------------------------------------*/

title3 "Missing Value Summary";

proc means
    data=work.ML_Data
    n
    nmiss;

run;


/*-----------------------------------------------------------------------
* Step 6 : Frequency of categorical variables
*-----------------------------------------------------------------------*/

title3 "Categorical Variables";

proc freq
    data=work.ML_Data;

    tables

        VehPower
        VehAge
        DrivAge
        BonusMalus
        VehBrand
        VehGas
        Area
        Region

        / missing;

run;


/*-----------------------------------------------------------------------
* Step 7 : Summary of numerical variables
*-----------------------------------------------------------------------*/

title3 "Numerical Variables";

proc means

    data=work.ML_Data

    n
    mean
    std
    min
    p25
    median
    p75
    max
    maxdec=4;

    var

        Exposure
        Density
        ClaimNb
        ClaimTotal;

run;


/*-----------------------------------------------------------------------
* Step 8 : Duplicate Policy Check
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Duplicate_IDpol as

    select

        IDpol,

        count(*) as Number_of_Records

    from work.ML_Data

    group by IDpol

    having count(*) > 1;

quit;

title3 "Duplicate Policy IDs";

proc print
    data=work.Duplicate_IDpol
    noobs;

run;


/*-----------------------------------------------------------------------
* Step 9 : Exposure Validation
*-----------------------------------------------------------------------*/

title3 "Exposure Validation";

proc means

    data=work.ML_Data

    n
    min
    mean
    median
    max;

    var Exposure;

run;


/*-----------------------------------------------------------------------
* Step 10 : Target Variable Validation
*-----------------------------------------------------------------------*/

proc sql;

    title3 "Portfolio Totals";

    select

        sum(Exposure)   as Total_Exposure   format=14.2,
        sum(ClaimNb)     as Total_Claims     format=14.,
        sum(ClaimTotal)  as Total_Severity   format=comma18.2

    from work.ML_Data;

quit;


/*-----------------------------------------------------------------------
* Step 11 : Log Summary
*-----------------------------------------------------------------------*/

data _null_;

    set work.ML_Data end=LastObs;

    retain NObs 0;

    NObs + 1;

    if LastObs then do;

        put "========================================================";
        put " MACHINE LEARNING DATA VALIDATION";
        put "========================================================";
        put " Number of observations : " NObs;
        put " Dataset                : WORK.ML_DATA";
        put " Validation             : COMPLETED";
        put "========================================================";

    end;

run;

title;
footnote;
