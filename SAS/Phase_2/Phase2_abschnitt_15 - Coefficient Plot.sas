/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.15 - Coefficient Plot
*
* Purpose:
*   Visualize the estimated coefficients of the reduced Gamma GLM
*   together with their 95% confidence intervals.
*
* Input:
*      WORK.GAMMA_REDUCED_PE
*
* Output:
*      WORK.GAMMA_COEFFICIENTS
*
**************************************************************************/

ods graphics on / reset width=10in height=8in imagemap;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.15 - Coefficient Plot";


/*-----------------------------------------------------------------------
* Step 1 : Prepare parameter estimates
*-----------------------------------------------------------------------*/

data work.Gamma_Coefficients;

    set work.Gamma_Reduced_PE;

    length Effect $200;

    /* Remove intercept from coefficient plot */

    if upcase(Parameter)="INTERCEPT" then delete;

    Effect = cats(Parameter," : ",Level1);

    /*--------------------------------------------------------------
      Confidence intervals

      PROC GENMOD normally returns:
         LowerWaldCL
         UpperWaldCL

      If these variables are not available, they are calculated from
      Estimate ± 1.96 × StdErr.
    --------------------------------------------------------------*/

    if missing(LowerWaldCL) then
        LowerCL = Estimate - 1.96*StdErr;
    else
        LowerCL = LowerWaldCL;

    if missing(UpperWaldCL) then
        UpperCL = Estimate + 1.96*StdErr;
    else
        UpperCL = UpperWaldCL;

run;


/*-----------------------------------------------------------------------
* Step 2 : Sort coefficients
*-----------------------------------------------------------------------*/

proc sort
    data=work.Gamma_Coefficients;

    by Estimate;

run;


/*-----------------------------------------------------------------------
* Step 3 : Coefficient plot
*-----------------------------------------------------------------------*/

title3 "Regression Coefficients with 95% Confidence Intervals";

proc sgplot
    data=work.Gamma_Coefficients;

    highlow

        y=Effect

        low=LowerCL
        high=UpperCL

        / type=line
          lineattrs=(thickness=2);

    scatter

        y=Effect
        x=Estimate

        / markerattrs=(symbol=circlefilled size=8);

    refline 0
        / axis=x
          lineattrs=(pattern=shortdash thickness=2);

    xaxis
        label="Regression Coefficient (Log Scale)"
        grid;

    yaxis
        discreteorder=data
        label="Rating Factor";

run;


/*-----------------------------------------------------------------------
* Step 4 : Exponentiated coefficients (Relativities)
*-----------------------------------------------------------------------*/

data work.Gamma_Relativities;

    set work.Gamma_Coefficients;

    Relativity = exp(Estimate);
    LowerRel   = exp(LowerCL);
    UpperRel   = exp(UpperCL);

    format

        Relativity
        LowerRel
        UpperRel

        8.4;

run;


/*-----------------------------------------------------------------------
* Step 5 : Print relativities
*-----------------------------------------------------------------------*/

title3 "Tariff Relativities";

proc print
    data=work.Gamma_Relativities
    noobs
    label;

    var

        Effect
        Estimate
        StdErr
        Relativity
        LowerRel
        UpperRel;

    label

        Effect      = "Rating Factor"
        Estimate    = "Coefficient"
        StdErr      = "Std. Error"
        Relativity  = "exp(Coefficient)"
        LowerRel    = "95% CI Lower"
        UpperRel    = "95% CI Upper";

run;


/*-----------------------------------------------------------------------
* Step 6 : Relativity plot
*-----------------------------------------------------------------------*/

title3 "Tariff Relativities";

proc sgplot
    data=work.Gamma_Relativities;

    highlow

        y=Effect

        low=LowerRel
        high=UpperRel

        / type=line
          lineattrs=(thickness=2);

    scatter

        y=Effect
        x=Relativity

        / markerattrs=(symbol=circlefilled size=8);

    refline 1
        / axis=x
          lineattrs=(pattern=shortdash thickness=2);

    xaxis

        label="Tariff Relativity"
        grid;

    yaxis

        discreteorder=data
        label="Rating Factor";

run;

ods graphics off;

title;
