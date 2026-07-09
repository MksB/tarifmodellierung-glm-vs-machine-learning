/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.8 - Monotonic Constraints Definition
*
* Purpose:
*   Define monotonic constraints for ML models (Gradient Boosting).
*   Used as governance layer for actuarial consistency.
*
* Approach:
*   - Create constraint metadata table
*   - Define monotonic direction per feature
*   - Provide macro interface for modeling step
*
* Output:
*      WORK.MONOTONE_CONSTRAINTS
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.8 - Monotonic Constraints Definition";

/*-----------------------------------------------------------------------
* Step 1 : Define monotonicity rules
*-----------------------------------------------------------------------*/

data work.Monotone_Constraints;

    length Variable $50 Direction $10 Role $20;

    /*---------------------------------------------------------------
      Positive monotonic relationship (+1)
      Higher value ? higher risk / severity
    ---------------------------------------------------------------*/

    Variable  = "VehPower";      Direction = "+1"; Role = "Risk Increasing"; output;
    Variable  = "Density";       Direction = "+1"; Role = "Risk Increasing"; output;
    Variable  = "BonusMalus";   Direction = "+1"; Role = "Risk Increasing"; output;

    /*---------------------------------------------------------------
      Exposure effect (positive)
    ---------------------------------------------------------------*/

    Variable  = "Exposure";     Direction = "+1"; Role = "Exposure Scaling"; output;

    /*---------------------------------------------------------------
      Age effects (non-linear approximated monotonic bins)
    ---------------------------------------------------------------*/

    Variable  = "DrivAge";      Direction = "-1"; Role = "Risk Decreasing"; output;

    Variable  = "VehAge";       Direction = "+1"; Role = "Risk Increasing (older vehicle)"; output;

    /*---------------------------------------------------------------
      Categorical encodings (treated as ordinal risk proxies)
    ---------------------------------------------------------------*/

    Variable  = "VehBrand_ID";  Direction = "+1"; Role = "Brand Risk Proxy"; output;
    Variable  = "VehGas_ID";    Direction = "+1"; Role = "Fuel Type Risk Proxy"; output;
    Variable  = "Area_ID";      Direction = "+1"; Role = "Geographical Risk"; output;
    Variable  = "Region_ID";    Direction = "+1"; Role = "Regional Risk"; output;

run;


/*-----------------------------------------------------------------------
* Step 2 : Review constraint table
*-----------------------------------------------------------------------*/

title3 "Monotonic Constraint Table";

proc print
    data=work.Monotone_Constraints
    noobs;

run;


/*-----------------------------------------------------------------------
* Step 3 : Create macro variables for downstream ML models
*-----------------------------------------------------------------------*/

proc sql noprint;

    /* Count positive constraints */
    select Variable
        into :MONO_POS separated by ' '
    from work.Monotone_Constraints
    where Direction = "+1";

    /* Count negative constraints */
    select Variable
        into :MONO_NEG separated by ' '
    from work.Monotone_Constraints
    where Direction = "-1";

quit;


/*-----------------------------------------------------------------------
* Step 4 : Macro wrapper for ML procedures
*-----------------------------------------------------------------------*/

%macro apply_monotonic_constraints();

    %put NOTE: Positive monotonic variables: &MONO_POS.;
    %put NOTE: Negative monotonic variables: &MONO_NEG.;

    /*
      NOTE:
      SAS PROC GRADBOOST does NOT directly support monotonic constraints
      like LightGBM.

      These macro variables are used to:
        - document model governance
        - enforce feature engineering rules
        - ensure consistent interpretation in reporting
    */

%mend;


/*-----------------------------------------------------------------------
* Step 5 : Validation
*-----------------------------------------------------------------------*/

proc freq data=work.Monotone_Constraints;

    tables Direction Role / missing;

run;


/*-----------------------------------------------------------------------
* Step 6 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.Monotone_Constraints end=eof;

    if eof then do;

        put "========================================================";
        put " MONOTONIC CONSTRAINTS DEFINED";
        put "========================================================";
        put " Output Dataset : WORK.MONOTONE_CONSTRAINTS";
        put " Positive vars  : VehPower, Density, BonusMalus, etc.";
        put " Negative vars  : DrivAge";
        put " Purpose        : ML governance + actuarial consistency";
        put "========================================================";
    end;

run;

title;
