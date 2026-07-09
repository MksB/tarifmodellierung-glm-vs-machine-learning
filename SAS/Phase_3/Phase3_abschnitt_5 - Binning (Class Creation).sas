/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.5 - Binning (Class Creation)
*
* Purpose:
*   Convert continuous variables into categorical risk classes
*   (binning / discretization for ML features).
*
* Input:
*      WORK.ML_NUMERIC
*
* Output:
*      WORK.ML_BINNED
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.5 - Binning (Class Creation)";

/*-----------------------------------------------------------------------
* Step 1 : Define bins using PROC FORMAT
*-----------------------------------------------------------------------*/

proc format;

    /*---------------------------------------------------------------
      Vehicle Age Bins
    ---------------------------------------------------------------*/
    value vehage_bin
        low - 1   = "0-1"
        2 - 5     = "2-5"
        6 - 10    = "6-10"
        11 - high = "11+";

    /*---------------------------------------------------------------
      Driver Age Bins
    ---------------------------------------------------------------*/
    value drivage_bin
        low - 25  = "<25"
        26 - 40   = "26-40"
        41 - 60   = "41-60"
        61 - high = "60+";

    /*---------------------------------------------------------------
      Exposure Bins
    ---------------------------------------------------------------*/
    value exp_bin
        low - 0.25 = "Very Low"
        0.25 - 0.5 = "Low"
        0.5 - 0.75 = "Medium"
        0.75 - 1   = "High";

    /*---------------------------------------------------------------
      Density Bins
    ---------------------------------------------------------------*/
    value dens_bin
        low - 100   = "Low"
        101 - 500   = "Medium"
        501 - 2000  = "High"
        2001 - high = "Very High";

    /*---------------------------------------------------------------
      Bonus-Malus Bins
    ---------------------------------------------------------------*/
    value bm_bin
        low - 50    = "Good"
        51 - 100    = "Neutral"
        101 - 150   = "Bad"
        151 - high  = "Very Bad";

run;


/*-----------------------------------------------------------------------
* Step 2 : Apply binning to dataset
*-----------------------------------------------------------------------*/

data work.ML_Binned;

    set work.ML_Numeric;

    /*---------------------------------------------------------------
      Apply formats -> categorical bins
    ---------------------------------------------------------------*/

    VehAge_Class  = put(VehAge, vehage_bin.);
    DrivAge_Class = put(DrivAge, drivage_bin.);
    Exposure_Class= put(Exposure, exp_bin.);
    Density_Class = put(Density, dens_bin.);
    BM_Class      = put(BonusMalus, bm_bin.);

    /*---------------------------------------------------------------
      Optional: numeric encoding of bins (ML-friendly)
    ---------------------------------------------------------------*/

    VehAge_Bin_ID  = input(compress(VehAge_Class,,'kd'), best32.);
    DrivAge_Bin_ID = input(compress(DrivAge_Class,,'kd'), best32.);

    /* safer fallback encoding for ML models */
    if VehAge_Class = "0-1" then VehAge_Bin_ID = 1;
    else if VehAge_Class = "2-5" then VehAge_Bin_ID = 2;
    else if VehAge_Class = "6-10" then VehAge_Bin_ID = 3;
    else if VehAge_Class = "11+" then VehAge_Bin_ID = 4;

    if DrivAge_Class = "<25" then DrivAge_Bin_ID = 1;
    else if DrivAge_Class = "26-40" then DrivAge_Bin_ID = 2;
    else if DrivAge_Class = "41-60" then DrivAge_Bin_ID = 3;
    else if DrivAge_Class = "60+" then DrivAge_Bin_ID = 4;

run;


/*-----------------------------------------------------------------------
* Step 3 : Check distribution of bins
*-----------------------------------------------------------------------*/

title3 "Binned Variable Distribution";

proc freq
    data=work.ML_Binned;

    tables
        VehAge_Class
        DrivAge_Class
        Exposure_Class
        Density_Class
        BM_Class
        / missing;

run;


/*-----------------------------------------------------------------------
* Step 4 : Summary check of numeric vs binned consistency
*-----------------------------------------------------------------------*/

title3 "Consistency Check";

proc means
    data=work.ML_Binned
    n mean std min max;

    class VehAge_Class;

    var Exposure Density;

run;


/*-----------------------------------------------------------------------
* Step 5 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.ML_Binned end=eof;

    if eof then do;

        put "========================================================";
        put " BINNING COMPLETED";
        put "========================================================";
        put " Output Dataset : WORK.ML_BINNED";
        put " Transformations:";
        put "  - Risk class binning (PROC FORMAT)";
        put "  - Categorical feature creation";
        put "  - Optional numeric encoding";
        put "========================================================";
    end;

run;

title;
