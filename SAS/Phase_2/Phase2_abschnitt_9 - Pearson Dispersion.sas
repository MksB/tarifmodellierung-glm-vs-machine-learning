/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.9 - Pearson Dispersion
*
* Purpose:
*   Calculate the Pearson dispersion parameter of the reduced
*   Gamma GLM.
*
* Formula:
*
*       phi = Sum(Pearson Residual²) / (n - p)
*
* where
*
*       n = Number of observations
*       p = Number of estimated parameters
*
* Input:
*       WORK.GAMMA_REDUCED_PRED
*       WORK.GAMMA_REDUCED_PE
*
**************************************************************************/

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.9 - Pearson Dispersion";

/*-----------------------------------------------------------------------
* Step 1 : Number of observations
*-----------------------------------------------------------------------*/

proc sql noprint;

    select count(*)
        into :NOBS trimmed
    from work.Gamma_Reduced_Pred;

quit;


/*-----------------------------------------------------------------------
* Step 2 : Number of estimated parameters
*-----------------------------------------------------------------------*/

proc sql noprint;

    select count(*)
        into :NPAR trimmed
    from work.Gamma_Reduced_PE;

quit;


/*-----------------------------------------------------------------------
* Step 3 : Calculate Pearson Chi-Square
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Pearson_Dispersion as

    select

        count(*)                                   as N,

        sum(PearsonResidual**2)                    as Pearson_ChiSquare
            format=14.6,

        &NPAR                                      as Number_of_Parameters,

        calculated N - calculated Number_of_Parameters
                                                   as Degrees_of_Freedom,

        calculated Pearson_ChiSquare /
        calculated Degrees_of_Freedom
                                                   as Dispersion
            format=12.6

    from work.Gamma_Reduced_Pred;

quit;


/*-----------------------------------------------------------------------
* Step 4 : Print Dispersion Estimate
*-----------------------------------------------------------------------*/

title3 "Pearson Dispersion Estimate";

proc print
    data=work.Pearson_Dispersion
    noobs
    label;

    label

        N                    = "Number of Observations"
        Pearson_ChiSquare    = "Pearson Chi-Square"
        Number_of_Parameters = "Estimated Parameters"
        Degrees_of_Freedom   = "Residual Degrees of Freedom"
        Dispersion           = "Dispersion Parameter (Phi)";

run;


/*-----------------------------------------------------------------------
* Step 5 : Dispersion Assessment
*-----------------------------------------------------------------------*/

data work.Dispersion_Assessment;

    set work.Pearson_Dispersion;

    length Model_Assessment $40;

    if Dispersion < 0.90 then
        Model_Assessment = "Possible Underdispersion";

    else if Dispersion <= 1.10 then
        Model_Assessment = "Good Dispersion";

    else
        Model_Assessment = "Possible Overdispersion";

run;

title3 "Dispersion Assessment";

proc print
    data=work.Dispersion_Assessment
    noobs
    label;

    var
        Dispersion
        Model_Assessment;

    label

        Dispersion      = "Estimated Phi"
        Model_Assessment= "Assessment";

run;


/*-----------------------------------------------------------------------
* Step 6 : Write Result to SAS Log
*-----------------------------------------------------------------------*/

data _null_;

    set work.Dispersion_Assessment;

    put "========================================================";
    put " Pearson Dispersion Assessment";
    put "========================================================";
    put " Number of observations : " N;
    put " Number of parameters   : " Number_of_Parameters;
    put " Pearson Chi-Square     : " Pearson_ChiSquare 12.4;
    put " Dispersion (Phi)       : " Dispersion 10.4;
    put " Assessment             : " Model_Assessment;
    put "========================================================";

run;

title;
