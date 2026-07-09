/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.1 - Prepare Severity Dataset
*
* Purpose:
*   Build the input dataset for the Gamma GLM severity model.
*
*   Severity = ClaimTotal / ClaimNb
*
*   Only policies with at least one reported claim are retained.
*
* Input:
*      WORK.DAT_FINAL
*
* Output:
*      WORK.SEVERITY_GLM
*
**************************************************************************/

options mprint mlogic symbolgen;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.1 - Preparation of Severity Dataset";

/*-----------------------------------------------------------------------
* Step 1 : Build Severity Dataset
*-----------------------------------------------------------------------*/

data work.severity_glm;

    set work.dat_final;

    /*--------------------------------------------------------------
      Keep only policies with at least one claim
    --------------------------------------------------------------*/

    if ClaimNb > 0;

    /*--------------------------------------------------------------
      Average claim severity
    --------------------------------------------------------------*/

    Severity = ClaimTotal / ClaimNb;

    /*--------------------------------------------------------------
      Basic validation
    --------------------------------------------------------------*/

    if Severity <= 0 then delete;

run;


/*-----------------------------------------------------------------------
* Step 2 : Verify Data Quality
*-----------------------------------------------------------------------*/

proc sql;

    create table work.severity_validation as

    select

        count(*)                              as Number_of_Policies,

        sum(ClaimNb)                          as Number_of_Claims,

        sum(ClaimTotal) format=comma18.2      as Total_ClaimAmount,

        mean(Severity) format=comma12.2       as Mean_Severity,

        median(Severity) format=comma12.2     as Median_Severity,

        min(Severity) format=comma12.2        as Minimum_Severity,

        max(Severity) format=comma12.2        as Maximum_Severity

    from work.severity_glm;

quit;


/*-----------------------------------------------------------------------
* Step 3 : Print Validation Summary
*-----------------------------------------------------------------------*/

proc print
    data=work.severity_validation
    noobs
    label;

    label

        Number_of_Policies = "Policies with Claims"
        Number_of_Claims   = "Observed Claims"
        Total_ClaimAmount  = "Total Claim Amount"
        Mean_Severity      = "Mean Severity"
        Median_Severity    = "Median Severity"
        Minimum_Severity   = "Minimum Severity"
        Maximum_Severity   = "Maximum Severity";

run;


/*-----------------------------------------------------------------------
* Step 4 : Check Missing Values
*-----------------------------------------------------------------------*/

proc means
    data=work.severity_glm
    n
    nmiss;

    var

        Severity
        ClaimNb
        ClaimTotal
        Exposure;

run;


/*-----------------------------------------------------------------------
* Step 5 : Verify Severity Variable
*-----------------------------------------------------------------------*/

proc freq
    data=work.severity_glm;

    tables ClaimNb / nocum;

run;


/*-----------------------------------------------------------------------
* Step 6 : Final Dataset Information
*-----------------------------------------------------------------------*/

proc contents
    data=work.severity_glm
    varnum;

run;


title;
