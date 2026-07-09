/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.4 - Numerical Transformations
*
* Purpose:
*   Apply numerical transformations for ML readiness:
*     - Log transformations
*     - Winsorization (capping)
*     - Standardization (z-score)
*
* Input:
*      WORK.ML_FEATURES
*
* Output:
*      WORK.ML_NUMERIC
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.4 - Numerical Transformations";

/*-----------------------------------------------------------------------
* Step 1 : Compute summary statistics for scaling
*-----------------------------------------------------------------------*/

proc means
    data=work.ML_Features noprint;

    var
        Exposure
        Density
        VehPower
        BonusMalus;

    output out=work._stats_

        mean=mean_Exposure mean_Density mean_VehPower mean_BonusMalus
        std =std_Exposure  std_Density  std_VehPower  std_BonusMalus;

run;


/*-----------------------------------------------------------------------
* Step 2 : Numerical feature transformation
*-----------------------------------------------------------------------*/

data work.ML_Numeric;

    if _n_=1 then set work._stats_;

    set work.ML_Features;

    /*---------------------------------------------------------------
      1. Winsorization (outlier control)
    ---------------------------------------------------------------*/

    Exposure_W = min(max(Exposure, 0.01), 1);
    Density_W  = min(max(Density, 1), 5000);
    Power_W    = min(max(VehPower, 40), 200);
    BM_W       = min(max(BonusMalus, 50), 200);

    /*---------------------------------------------------------------
      2. Log transformations
    ---------------------------------------------------------------*/

    Log_Exposure = log(Exposure_W);
    Log_Density  = log(Density_W);
    Log_Power    = log(Power_W);
    Log_BM       = log(BM_W);

    /*---------------------------------------------------------------
      3. Z-score standardization
      (equivalent to sklearn StandardScaler)
    ---------------------------------------------------------------*/

    Z_Exposure = (Exposure_W - mean_Exposure) / std_Exposure;
    Z_Density  = (Density_W  - mean_Density)  / std_Density;
    Z_Power    = (Power_W    - mean_VehPower) / std_VehPower;
    Z_BM       = (BM_W       - mean_BonusMalus) / std_BonusMalus;

    /*---------------------------------------------------------------
      4. Exposure stability feature
    ---------------------------------------------------------------*/

    Log_Exposure_Stable = log(max(Exposure, 0.0001));

    /*---------------------------------------------------------------
      5. Interaction-ready numeric features
    ---------------------------------------------------------------*/

    Risk_Index = Z_Density * Z_BM;
    Power_Ratio = Z_Power / (abs(Z_BM) + 1);

run;


/*-----------------------------------------------------------------------
* Step 3 : Validation of transformed variables
*-----------------------------------------------------------------------*/

title3 "Transformed Variable Summary";

proc means
    data=work.ML_Numeric
    n mean std min p1 p50 p99 max maxdec=4;

    var
        Log_Exposure
        Log_Density
        Z_Exposure
        Z_Density
        Z_Power
        Z_BM
        Risk_Index;

run;


/*-----------------------------------------------------------------------
* Step 4 : Missing value check
*-----------------------------------------------------------------------*/

title3 "Missing Values After Transformation";

proc means
    data=work.ML_Numeric
    n nmiss;

run;


/*-----------------------------------------------------------------------
* Step 5 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.ML_Numeric end=eof;

    if eof then do;

        put "========================================================";
        put " NUMERICAL TRANSFORMATIONS COMPLETED";
        put "========================================================";
        put " Output Dataset : WORK.ML_NUMERIC";
        put " Operations:";
        put "  - Winsorization";
        put "  - Log transforms";
        put "  - Z-score scaling";
        put "  - Interaction features";
        put "========================================================";

    end;

run;

title;
