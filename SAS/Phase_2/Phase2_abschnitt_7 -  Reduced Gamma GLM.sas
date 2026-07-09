/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.7 - Reduced Gamma GLM
*
* Purpose:
*   Fit the reduced Gamma GLM using only statistically significant
*   rating factors identified in the Type III analysis.
*
* Distribution :
*      Gamma
*
* Link Function :
*      Log
*
* Response :
*      Severity
*
* Input :
*      WORK.SEVERITY_GLM
*
* Output :
*      WORK.GAMMA_REDUCED_PE
*      WORK.GAMMA_REDUCED_TYPE3
*      WORK.GAMMA_REDUCED_MODELFIT
*      WORK.GAMMA_REDUCED_PRED
*
**************************************************************************/

ods graphics on;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.7 - Reduced Gamma GLM";

/*-----------------------------------------------------------------------
* Fit Reduced Gamma GLM
*-----------------------------------------------------------------------*/

ods output

    ParameterEstimates = work.Gamma_Reduced_PE
    Type3              = work.Gamma_Reduced_Type3
    ModelFit           = work.Gamma_Reduced_ModelFit
    Criteria           = work.Gamma_Reduced_Criteria;

proc genmod data=work.severity_glm;

    class

        Area
        VehPower
        DrivAge
        BonusMalus
        VehBrand

        / param=ref ref=first;

    model Severity =

        Area
        VehPower
        DrivAge
        BonusMalus
        VehBrand
        Density

        /

        dist=gamma
        link=log
        type3
        lrci;

    output out=work.Gamma_Reduced_Pred

        pred     = PredictedSeverity
        resraw   = RawResidual
        resdev   = DevianceResidual
        reschi   = PearsonResidual
        xbeta    = LinearPredictor;

run;


/*-----------------------------------------------------------------------
* Parameter Estimates
*-----------------------------------------------------------------------*/

title3 "Parameter Estimates";

proc print
    data=work.Gamma_Reduced_PE
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Type III Tests
*-----------------------------------------------------------------------*/

title3 "Type III Analysis";

proc print
    data=work.Gamma_Reduced_Type3
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Model Fit Statistics
*-----------------------------------------------------------------------*/

title3 "Model Fit Statistics";

proc print
    data=work.Gamma_Reduced_ModelFit
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Residual Summary
*-----------------------------------------------------------------------*/

title3 "Residual Summary";

proc means
    data=work.Gamma_Reduced_Pred

    n
    mean
    std
    min
    q1
    median
    q3
    max
    maxdec=4;

    var

        RawResidual
        DevianceResidual
        PearsonResidual;

run;


/*-----------------------------------------------------------------------
* Distribution of Deviance Residuals
*-----------------------------------------------------------------------*/

title3 "Distribution of Deviance Residuals";

proc sgplot
    data=work.Gamma_Reduced_Pred;

    histogram DevianceResidual /
        nbins=30;

    density DevianceResidual /
        type=kernel;

    xaxis label="Deviance Residual";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* Observed vs Predicted Severity
*-----------------------------------------------------------------------*/

title3 "Observed versus Predicted Severity";

proc sgplot
    data=work.Gamma_Reduced_Pred;

    scatter

        x=PredictedSeverity
        y=Severity

        / transparency=0.70;

    lineparm

        x=0
        y=0
        slope=1;

    xaxis label="Predicted Severity";
    yaxis label="Observed Severity";

run;

ods graphics off;

title;
