/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.6 - Categorical Variable Encoding
*
* Purpose:
*   Convert categorical variables into integer encodings
*   for ML algorithms (PROC GRADBOOST / HPFOREST compatible).
*
* Input:
*      WORK.ML_BINNED
*
* Output:
*      WORK.ML_ENCODED
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.6 - Categorical Encoding";

/*-----------------------------------------------------------------------
* Step 1 : Create stable encoding maps using PROC FORMAT
*-----------------------------------------------------------------------*/

proc format;

    /* Vehicle Gas Type */
    value $vehgas_enc
        "Diesel" = 1
        "Regular" = 2
        other     = 0;

    /* Vehicle Brand */
    value $vehbrand_enc
        "B1" = 1
        "B2" = 2
        "B3" = 3
        "B4" = 4
        "B5" = 5
        "B6" = 6
        "B7" = 7
        "B8" = 8
        "B9" = 9
        "B10" = 10
        "B11" = 11
        "B12" = 12
        "B13" = 13
        "B14" = 14
        other = 0;

    /* Region */
    value $region_enc
        other = 0;

    /* Area */
    value $area_enc
        other = 0;

run;


/*-----------------------------------------------------------------------
* Step 2 : Apply encoding
*-----------------------------------------------------------------------*/

data work.ML_Encoded;

    set work.ML_Binned;

    /*---------------------------------------------------------------
      Direct integer encoding (Tree-based ML compatible)
    ---------------------------------------------------------------*/

    VehGas_ID   = input(put(VehGas, $vehgas_enc.), 8.);
    VehBrand_ID = input(put(VehBrand, $vehbrand_enc.), 8.);
    Region_ID   = input(put(Region, $region_enc.), 8.);
    Area_ID     = input(put(Area, $area_enc.), 8.);

    /*---------------------------------------------------------------
      Optional: safeguard for missing categories
    ---------------------------------------------------------------*/

    if missing(VehGas_ID)   then VehGas_ID = 0;
    if missing(VehBrand_ID) then VehBrand_ID = 0;
    if missing(Region_ID)   then Region_ID = 0;
    if missing(Area_ID)     then Area_ID = 0;

    /*---------------------------------------------------------------
      Frequency-based encoding (optional enhancement for ML)
    ---------------------------------------------------------------*/

run;


/*-----------------------------------------------------------------------
* Step 3 : Frequency encoding (advanced ML feature)
*-----------------------------------------------------------------------*/

proc sql;

    create table work._vehbrand_freq as
    select VehBrand,
           count(*) as freq
    from work.ML_Encoded
    group by VehBrand;

    create table work.ML_Encoded_Freq as
    select a.*,
           b.freq / (select count(*) from work.ML_Encoded) as VehBrand_Freq
    from work.ML_Encoded as a
    left join work._vehbrand_freq as b
    on a.VehBrand = b.VehBrand;

quit;


/*-----------------------------------------------------------------------
* Step 4 : Validation of encoding
*-----------------------------------------------------------------------*/

title3 "Encoded Variable Summary";

proc means
    data=work.ML_Encoded_Freq
    n mean std min max;

    var
        VehGas_ID
        VehBrand_ID
        Region_ID
        Area_ID
        VehBrand_Freq;

run;


/*-----------------------------------------------------------------------
* Step 5 : Distribution check
*-----------------------------------------------------------------------*/

title3 "Encoded Category Distribution";

proc freq
    data=work.ML_Encoded_Freq;

    tables
        VehGas_ID
        VehBrand_ID
        Region_ID
        Area_ID
        / missing;

run;


/*-----------------------------------------------------------------------
* Step 6 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.ML_Encoded_Freq end=eof;

    if eof then do;

        put "========================================================";
        put " CATEGORICAL ENCODING COMPLETED";
        put "========================================================";
        put " Output Dataset : WORK.ML_ENCODED_FREQ";
        put " Encoding Types:";
        put "  - Integer encoding (tree-based ML)";
        put "  - Frequency encoding (VehBrand)";
        put "========================================================";

    end;

run;

title;
