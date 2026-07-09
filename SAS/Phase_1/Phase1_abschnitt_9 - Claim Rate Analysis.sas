/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Data Cleaning & Exposure Analysis
* Section  : 9 - Claim Rate Analysis
*
* Purpose:
*   Analyse the observed claim frequency adjusted for policy exposure.
*
*   ClaimRate = ClaimNb / Exposure
*
* Input:
*      WORK.DAT_FINAL
*
* Output:
*      WORK.DAT_CLAIMRATE
*
**************************************************************************/

ods graphics on;

title1 "Phase 1 - Claim Rate Analysis";

/*-----------------------------------------------------------------------
* 9.1 Calculate Claim Rate
*-----------------------------------------------------------------------*/

data work.dat_claimrate;

    set work.dat_final;

    /*--------------------------------------------------------------
      Observed annualized claim frequency
    --------------------------------------------------------------*/

    ClaimRate = ClaimNb / Exposure;

run;


/*-----------------------------------------------------------------------
* 9.2 Descriptive Statistics
*-----------------------------------------------------------------------*/

title2 "Descriptive Statistics of Claim Rate";

proc means data=work.dat_claimrate
           n
           nmiss
           mean
           median
           std
           min
           q1
           q3
           max
           maxdec=6;

    var ClaimRate;

run;


/*-----------------------------------------------------------------------
* 9.3 Distribution of Claim Rate
*-----------------------------------------------------------------------*/

title2 "Histogram of Claim Rate";

proc sgplot data=work.dat_claimrate;

    histogram ClaimRate /
        nbins=40;

    density ClaimRate /
        type=kernel;

    xaxis label="Observed Claim Rate";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* 9.4 Boxplot of Claim Rate
*-----------------------------------------------------------------------*/

title2 "Boxplot of Claim Rate";

proc sgplot data=work.dat_claimrate;

    vbox ClaimRate;

    yaxis label="Observed Claim Rate";

run;


/*-----------------------------------------------------------------------
* 9.5 Claim Rate by Area
*-----------------------------------------------------------------------*/

title2 "Claim Rate by Area";

proc sgplot data=work.dat_claimrate;

    vbox ClaimRate /
        category=Area;

    yaxis label="Observed Claim Rate";

run;


/*-----------------------------------------------------------------------
* 9.6 Claim Rate by Vehicle Fuel
*-----------------------------------------------------------------------*/

title2 "Claim Rate by Vehicle Fuel";

proc sgplot data=work.dat_claimrate;

    vbox ClaimRate /
        category=VehGas;

    yaxis label="Observed Claim Rate";

run;


/*-----------------------------------------------------------------------
* 9.7 Claim Rate by Vehicle Brand
*-----------------------------------------------------------------------*/

title2 "Claim Rate by Vehicle Brand";

proc sgplot data=work.dat_claimrate;

    vbox ClaimRate /
        category=VehBrand;

    yaxis label="Observed Claim Rate";

run;


/*-----------------------------------------------------------------------
* 9.8 Relationship between Claim Rate and Driver Age
*-----------------------------------------------------------------------*/

title2 "Claim Rate versus Driver Age";

proc sgplot data=work.dat_claimrate;

    scatter x=DrivAge
            y=ClaimRate
            / transparency=0.85;

    loess x=DrivAge
          y=ClaimRate;

    xaxis label="Driver Age";
    yaxis label="Observed Claim Rate";

run;


/*-----------------------------------------------------------------------
* 9.9 Relationship between Claim Rate and Bonus-Malus
*-----------------------------------------------------------------------*/

title2 "Claim Rate versus Bonus-Malus";

proc sgplot data=work.dat_claimrate;

    scatter x=BonusMalus
            y=ClaimRate
            / transparency=0.85;

    loess x=BonusMalus
          y=ClaimRate;

    xaxis label="Bonus-Malus";
    yaxis label="Observed Claim Rate";

run;


/*-----------------------------------------------------------------------
* 9.10 Highest Claim Rates
*-----------------------------------------------------------------------*/

title2 "Highest Observed Claim Rates";

proc sort data=work.dat_claimrate
          out=ClaimRate_Max;

    by descending ClaimRate;

run;

proc print data=ClaimRate_Max(obs=20) noobs;

    var IDpol
        Exposure
        ClaimNb
        ClaimRate;

run;


/*-----------------------------------------------------------------------
* 9.11 Claim Rate Percentiles
*-----------------------------------------------------------------------*/

proc univariate data=work.dat_claimrate noprint;

    var ClaimRate;

    output out=ClaimRate_Percentiles

        pctlpts=
            1
            5
            10
            25
            50
            75
            90
            95
            99

        pctlpre=P_;

run;

title2 "Claim Rate Percentiles";

proc print data=ClaimRate_Percentiles
           noobs;

run;

ods graphics off;

title;
