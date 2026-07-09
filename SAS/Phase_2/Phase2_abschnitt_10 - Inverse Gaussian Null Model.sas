/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.10 - Inverse Gaussian Null Model
*
* Purpose:
*   Fit the intercept-only Inverse Gaussian GLM.
*
* Distribution :
*      Inverse Gaussian
*
* Link Function :
*      Log
*
* Mathematical Model:
*
*      log(E[Severity]) = ß0
*
* This model serves as the baseline for comparing the
* Inverse Gaussian GLM with the Gamma GLM.
*
* Input:
*      WORK.SEVERITY_GLM
*
* Output:
*      WORK.IG_NULL_PE
*      WORK.IG_NULL_MODELFIT
*      WORK.IG_NULL_CRITERIA
*      WORK.IG_NULL_PRED
*
**************************************************************************/

ods graphics on;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.10 - Inverse Gaussian Null Model";

/*-----------------------------------------------------------------------
* Fit Inverse Gaussian Null Model
*-----------------------------------------------------------------------*/

ods output
    ParameterEstimates = work.IG_Null_PE
    ModelFit           = work.IG_Null_ModelFit
    Criteria           = work.IG_Null_Criteria;

proc genmod data=work.severity_glm;

    model Severity =
        /
        dist=igaussian
        link=log
        type3
        lrci;

    output out=work.IG_Null_Pred

        pred    = PredictedSeverity
        resraw  = RawResidual
        resdev  = DevianceResidual
        reschi  = PearsonResidual
        xbeta   = LinearPredictor;

run;


/*-----------------------------------------------------------------------
* Parameter Estimates
*-----------------------------------------------------------------------*/

title3 "Parameter Estimates";

proc print
    data=work.IG_Null_PE
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Model Fit Statistics
*-----------------------------------------------------------------------*/

title3 "Model Fit Statistics";

proc print
    data=work.IG_Null_ModelFit
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Estimated Portfolio Mean Severity
*-----------------------------------------------------------------------*/

data work.IG_Null_Intercept;

    set work.IG_Null_PE;

    where Parameter = "Intercept";

    MeanSeverity = exp(Estimate);

    label
        MeanSeverity = "Estimated Portfolio Mean Severity";

run;

title3 "Estimated Mean Severity";

proc print
    data=work.IG_Null_Intercept
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Residual Summary
*-----------------------------------------------------------------------*/

title3 "Residual Summary";

proc means
    data=work.IG_Null_Pred

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
    data=work.IG_Null_Pred;

    histogram DevianceResidual /
        nbins=30;

    density DevianceResidual /
        type=kernel;

    xaxis label="Deviance Residual";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* Distribution of Predicted Severity
*-----------------------------------------------------------------------*/

title3 "Predicted Severity";

proc sgplot
    data=work.IG_Null_Pred;

    histogram PredictedSeverity /
        nbins=25;

    density PredictedSeverity /
        type=kernel;

    xaxis label="Predicted Severity";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* Save Null Model Summary
*-----------------------------------------------------------------------*/

data work.IG_Null_Summary;

    length Model $30 Distribution $20;

    set work.IG_Null_Intercept;

    Model        = "Null Model";
    Distribution = "Inverse Gaussian";

run;

title3 "Inverse Gaussian Null Model Summary";

proc print
    data=work.IG_Null_Summary
    noobs
    label;

run;

ods graphics off;

title;
