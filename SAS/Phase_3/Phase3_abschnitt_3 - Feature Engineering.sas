/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.3 - Feature Engineering
*
* Purpose:
*   Create modelling features for ML algorithms (GBM / RF / XGBoost-like).
*
* Input:
*      WORK.ML_DATA
*
* Output:
*      WORK.ML_FEATURES
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.3 - Feature Engineering";

/*-----------------------------------------------------------------------
* Step 1 : Binning / Discretization using PROC FORMAT
*-----------------------------------------------------------------------*/

proc format;

    /* Vehicle Age */
    value vehage_f
        low - 1   = "0-1"
        2 - 5     = "2-5"
        6 - 10    = "6-10"
        11 - high = "11+";

    /* Driver Age */
    value drivage_f
        low - 25  = "<25"
        26 - 40   = "26-40"
        41 - 60   = "41-60"
        61 - high = "60+";

    /* Density */
    value density_f
        low - 50     = "Low"
        51 - 500     = "Medium"
        501 - 2000   = "High"
        2001 - high  = "Very High";

    /* Bonus-Malus */
    value bm_f
        low - 50   = "Good"
        51 - 100   = "Neutral"
        101 - 150  = "Bad"
        151 - high = "Very Bad";

run;


/*-----------------------------------------------------------------------
* Step 2 : Feature Engineering (DATA Step)
*-----------------------------------------------------------------------*/

data work.ML_Features;

    set work.ML_Data;

    /*---------------------------------------------------------------
      1. Log transformations (stabilize skewed distributions)
    ---------------------------------------------------------------*/

    Log_Exposure = log(max(Exposure, 0.0001));
    Log_Density  = log(Density + 1);

    /*---------------------------------------------------------------
      2. Frequency and Severity Targets (ML structure)
    ---------------------------------------------------------------*/

    Claim_Frequency = ClaimNb / max(Exposure, 0.0001);

    if ClaimNb > 0 then
        Claim_Severity = ClaimTotal / ClaimNb;
    else
        Claim_Severity = .;

    Has_Claim = (ClaimNb > 0);

    /*---------------------------------------------------------------
      3. Categorical Binning (using formats)
    ---------------------------------------------------------------*/

    VehAge_Bin   = put(VehAge, vehage_f.);
    DrivAge_Bin  = put(DrivAge, drivage_f.);
    Density_Bin  = put(Density, density_f.);
    Bonus_Bin    = put(BonusMalus, bm_f.);

    /*---------------------------------------------------------------
      4. Interaction / Risk Features
    ---------------------------------------------------------------*/

    Power_to_Age = VehPower / max(VehAge, 1);

    Risk_Exposure = Exposure * (1 + Density/1000);

    /*---------------------------------------------------------------
      5. Stability adjustments (caps / safeguards)
    ---------------------------------------------------------------*/

    if Claim_Frequency > 10 then Claim_Frequency = 10;

    if Claim_Severity > 50000 then Claim_Severity = 50000;

    /*---------------------------------------------------------------
      6. Categorical encoding helper (for ML algorithms)
         (equivalent to Label Encoding in Python)
    ---------------------------------------------------------------*/

    VehBrand_ID = input(VehBrand, best32.);
    VehGas_ID   = input(VehGas, best32.);
    Area_ID     = input(Area, best32.);
    Region_ID   = input(Region, best32.);

run;


/*-----------------------------------------------------------------------
* Step 3 : Basic validation of engineered features
*-----------------------------------------------------------------------*/

title3 "Feature Summary Statistics";

proc means
    data=work.ML_Features
    n mean std min p1 p50 p99 max maxdec=4;

    var
        Log_Exposure
        Log_Density
        Claim_Frequency
        Claim_Severity
        Power_to_Age
        Risk_Exposure;

run;


/*-----------------------------------------------------------------------
* Step 4 : Distribution check of binned variables
*-----------------------------------------------------------------------*/

title3 "Binned Variables Distribution";

proc freq
    data=work.ML_Features;

    tables
        VehAge_Bin
        DrivAge_Bin
        Density_Bin
        Bonus_Bin
        Has_Claim
        / missing;

run;


/*-----------------------------------------------------------------------
* Step 5 : Missing value check after feature engineering
*-----------------------------------------------------------------------*/

title3 "Missing Values after Feature Engineering";

proc means
    data=work.ML_Features
    n nmiss;

run;


/*-----------------------------------------------------------------------
* Step 6 : Final dataset confirmation log
*-----------------------------------------------------------------------*/

data _null_;

    set work.ML_Features end=eof;

    if eof then do;

        put "========================================================";
        put " FEATURE ENGINEERING COMPLETED";
        put "========================================================";
        put " Output Dataset : WORK.ML_FEATURES";
        put " Transformations:";
        put "  - Log transforms";
        put "  - Binning (PROC FORMAT)";
        put "  - Interaction features";
        put "  - Target engineering";
        put "========================================================";

    end;

run;

title;
