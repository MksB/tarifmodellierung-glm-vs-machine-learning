/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.7 - Frequency / Severity Dataset Creation
*
* Purpose:
*   Split the modelling data into:
*     - Frequency dataset (claim counts per exposure)
*     - Severity dataset (average claim severity)
*
* Input:
*      WORK.ML_ENCODED_FREQ
*
* Output:
*      WORK.ML_FREQ
*      WORK.ML_SEV
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.7 - Frequency / Severity Dataset Creation";

/*-----------------------------------------------------------------------
* Step 1 : Create Frequency Dataset
*-----------------------------------------------------------------------*/

data work.ML_Freq;

    set work.ML_Encoded_Freq;

    /*---------------------------------------------------------------
      Frequency target definition
      Equivalent to Python:
          y_freq = ClaimNb / Exposure
    ---------------------------------------------------------------*/

    if Exposure > 0 then
        Claim_Frequency = ClaimNb / Exposure;
    else
        Claim_Frequency = .;

    /*---------------------------------------------------------------
      Offset (log exposure) for Poisson-type models
    ---------------------------------------------------------------*/

    Log_Exposure = log(max(Exposure, 0.0001));

    /*---------------------------------------------------------------
      Stability cap (avoid extreme frequencies)
    ---------------------------------------------------------------*/

    if Claim_Frequency > 10 then Claim_Frequency = 10;

run;


/*-----------------------------------------------------------------------
* Step 2 : Create Severity Dataset
*-----------------------------------------------------------------------*/

data work.ML_Sev;

    set work.ML_Encoded_Freq;

    /*---------------------------------------------------------------
      Severity target definition
      Equivalent to Python:
          y_sev = ClaimTotal / ClaimNb
    ---------------------------------------------------------------*/

    if ClaimNb > 0 then
        Claim_Severity = ClaimTotal / ClaimNb;
    else
        Claim_Severity = .;

    /*---------------------------------------------------------------
      Optional log transformation for Gamma modeling
    ---------------------------------------------------------------*/

    Log_Severity = log(max(Claim_Severity, 0.0001));

    /*---------------------------------------------------------------
      Keep only positive claims (standard actuarial practice)
    ---------------------------------------------------------------*/

    if ClaimNb = 0 then delete;

run;


/*-----------------------------------------------------------------------
* Step 3 : Validation - Frequency dataset
*-----------------------------------------------------------------------*/

title3 "Frequency Dataset Summary";

proc means
    data=work.ML_Freq
    n mean std min p1 p50 p99 max;

    var
        Claim_Frequency
        Exposure
        ClaimNb;

run;


/*-----------------------------------------------------------------------
* Step 4 : Validation - Severity dataset
*-----------------------------------------------------------------------*/

title3 "Severity Dataset Summary";

proc means
    data=work.ML_Sev
    n mean std min p1 p50 p99 max;

    var
        Claim_Severity
        ClaimTotal
        ClaimNb;

run;


/*-----------------------------------------------------------------------
* Step 5 : Sanity check - exposure consistency
*-----------------------------------------------------------------------*/

proc sql;

    title3 "Portfolio Totals Check";

    select

        sum(Exposure)     as Total_Exposure,
        sum(ClaimNb)      as Total_Claims,
        sum(ClaimTotal)   as Total_Severity format=comma18.2

    from work.ML_Encoded_Freq;

quit;


/*-----------------------------------------------------------------------
* Step 6 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.ML_Sev end=eof;

    if eof then do;

        put "========================================================";
        put " FREQUENCY / SEVERITY DATASETS CREATED";
        put "========================================================";
        put " Frequency Dataset : WORK.ML_FREQ";
        put " Severity Dataset  : WORK.ML_SEV";
        put " Transformations:";
        put "  - Claim Frequency = ClaimNb / Exposure";
        put "  - Claim Severity  = ClaimTotal / ClaimNb";
        put "  - Log exposure & severity features";
        put "========================================================";
    end;

run;

title;
