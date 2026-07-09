/**************************************************************************
 * Project      : SHAP Phase 4 Analysis – freMTPL Claim Frequency Modelling
 * Section      : 2 – Data Preparation
 *
 * Purpose
 * -------
 * Read the input dataset, validate the required variables and perform
 * the feature engineering required for the GLM and XGBoost models.
 *
 * Python Equivalent
 * -----------------
 * load_and_prepare()
 *
 * Created Variables
 * -----------------
 * Exposure            Exposure truncated to (0,1]
 * ClaimFreq           Claim frequency
 * LogDensity          log(1 + Density)
 * BonusMalusCapped    BonusMalus capped at 150
 **************************************************************************/


/**************************************************************************
 * SECTION 2.1
 * Import CSV file
 **************************************************************************/
/*
proc import
    datafile="&DATA_FILE."
    out=work.freMTPL_raw
    dbms=csv
    replace;
    guessingrows=max;
    getnames=yes;
run;
*/

/**************************************************************************
 * SECTION 2.2
 * Validate required variables
 *
 * Equivalent to
 *
 * required = {"Exposure","ClaimNb"} | ALL_FEATURES
 **************************************************************************/

proc contents
    data=work.data
    out=_contents_(keep=name)
    noprint;
run;

proc sql noprint;

    create table work._required_ as
    select *
    from (
        select "Exposure"    as NAME length=32
        union all
        select "ClaimNb"
        union all
        select "VehPower"
        union all
        select "VehAge"
        union all
        select "DrivAge"
        union all
        select "BonusMalus"
        union all
        select "Density"
        union all
        select "VehBrand"
        union all
        select "VehGas"
        union all
        select "Area"
        union all
        select "Region"
    );

quit;

/* alternative method */
data work._required_;
    length NAME $32.; 
    input NAME $;     
    datalines;
Exposure
ClaimNb
VehPower
VehAge
DrivAge
BonusMalus
Density
VehBrand
VehGas
Area
Region
;
run;

/*-----------------------------------------------------------------------
 Identify missing variables
 -----------------------------------------------------------------------*/

proc sql noprint;

create table work._missing_vars as
select a.name
from work._required_ as a

left join work._contents_ as b
on upcase(a.name)=upcase(b.name)

where b.name is missing;

select count(*)
into :N_MISSING
from work._missing_vars;

quit;


/*-----------------------------------------------------------------------
 Abort if variables are missing
 -----------------------------------------------------------------------*/

%macro check_schema;

%if &N_MISSING > 0 %then %do;

    %put ERROR:;
    %put ERROR: Required variables are missing from the input dataset.;
    %put ERROR:;

    proc print data=work._missing_vars;
        title "Missing Variables";
    run;

    %abort cancel;

%end;

%mend;

%check_schema;


/**************************************************************************
 * SECTION 2.3
 * Feature Engineering
 *
 * Python equivalent:
 *
 * Exposure.clip(lower=1e-6, upper=1.0)
 * ClaimFreq = ClaimNb / Exposure
 * LogDensity = log1p(Density)
 * BonusMalusCapped = clip(BonusMalus, upper=150)
 **************************************************************************/

data work.freMTPL_prepared;

    set work.data;

    length ClaimFreq
           LogDensity
           BonusMalusCapped 8.;

    /**************************************************************
     Exposure
     Clip to (0,1]
    **************************************************************/

    Exposure=max(1E-6,min(Exposure,1));

    /**************************************************************
     Claim Frequency
    **************************************************************/

    ClaimFreq=ClaimNb/Exposure;

    /**************************************************************
     Log Density
     Equivalent to numpy.log1p()
    **************************************************************/

    LogDensity=log(Density+1);

    /**************************************************************
     Cap Bonus-Malus
    **************************************************************/

    BonusMalusCapped=min(BonusMalus,150);

run;


/**************************************************************************
 * SECTION 2.4
 * Basic data quality checks
 **************************************************************************/

proc sql;

select
        count(*)                           as N_Obs,
        sum(Exposure)                      as Total_Exposure format=12.4,
        sum(ClaimNb)                       as Total_Claims,
        calculated Total_Claims /
        calculated Total_Exposure          as Claim_Rate format=8.5
from work.freMTPL_prepared;

quit;


/**************************************************************************
 * SECTION 2.5
 * Descriptive statistics
 **************************************************************************/

proc means
        data=work.freMTPL_prepared
        n
        nmiss
        mean
        std
        min
        p25
        median
        p75
        max;

var
    Exposure
    ClaimNb
    ClaimFreq
    VehPower
    VehAge
    DrivAge
    BonusMalus
    BonusMalusCapped
    Density
    LogDensity;

run;


/**************************************************************************
 * SECTION 2.6
 * Frequency tables for categorical variables
 **************************************************************************/

proc freq data=work.freMTPL_prepared;

tables
    VehBrand
    VehGas
    Area
    Region
    / missing;

run;


/**************************************************************************
 * SECTION 2 completed successfully
 **************************************************************************/

%put NOTE: =============================================;
%put NOTE: Data Preparation completed successfully.;
%put NOTE: Output dataset = WORK.FREMTPL_PREPARED;
%put NOTE: =============================================;
