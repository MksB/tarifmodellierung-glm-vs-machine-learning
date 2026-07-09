/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.4 - Gamma Intercept-Only Model
*
* Purpose:
*   Fit the intercept-only Gamma GLM (Null Model).
*
*   Response Variable:
*       Severity
*
*   Distribution:
*       Gamma
*
*   Link Function:
*       Log
*
*   Mathematical Form:
*
*       log(E[Severity]) = ß0
*
*   The null model serves as the baseline for subsequent likelihood
*   ratio tests and model comparisons.
*
* Input:
*       WORK.SEVERITY_GLM
*
* Output:
*       Gamma_Null_PE
*       Gamma_Null_ModelFit
*       Gamma_Null_ObsStats
*       Gamma_Null_Pred
*
**************************************************************************/

ods graphics on;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.4 - Gamma Intercept-Only Model";

/*-----------------------------------------------------------------------
* Fit Gamma Null Model
*-----------------------------------------------------------------------*/

ods output
    ParameterEstimates = work.Gamma_Null_PE
    ModelFit           = work.Gamma_Null_ModelFit
    ModelfitStatistics = work.Gamma_Null_ModelFit
    Criteria           = work.Gamma_Null_Criteria
    ObStats            = work.Gamma_Null_ObsStats;

proc genmod data=work.severity_glm;

    model Severity =
        /
        dist = gamma
        link = log
        type3
        lrci;

    /*---------------------------------------------------------------
      Predicted Mean on Original Scale
    ---------------------------------------------------------------*/

    output out=work.Gamma_Null_Pred
           pred     = Pred_Severity
           resraw   = RawResidual
           resdev   = DevianceResidual
           reschi   = PearsonResidual
           xbeta    = LinearPredictor;

run;

title3 "Parameter Estimates";

proc print data=work.Gamma_Null_PE
           label
           noobs;
run;

title3 "Model Fit Statistics";

proc print data=work.Gamma_Null_ModelFit
           label
           noobs;
run;


/*-----------------------------------------------------------------------
* Calculate Mean Severity from Intercept
*-----------------------------------------------------------------------*/

data work.Gamma_Null_Intercept;

    set work.Gamma_Null_PE;

    if Parameter = "Intercept";

    MeanSeverity = exp(Estimate);

    keep
        Parameter
        Estimate
        StdErr
        LowerWaldCL
        UpperWaldCL
        MeanSeverity;

    label

        Estimate      = "Intercept Estimate"
        StdErr        = "Standard Error"
        LowerWaldCL   = "95% Lower CI"
        UpperWaldCL   = "95% Upper CI"
        MeanSeverity  = "Estimated Mean Severity";

run;

title3 "Estimated Portfolio Mean Severity";

proc print data=work.Gamma_Null_Intercept
           label
           noobs;
run;


/*-----------------------------------------------------------------------
* Residual Diagnostics
*-----------------------------------------------------------------------*/

title3 "Residual Diagnostics";

proc means data=work.Gamma_Null_Pred
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

proc sgplot data=work.Gamma_Null_Pred;

    histogram DevianceResidual /
              nbins=30;

    density DevianceResidual /
            type=kernel;

    xaxis label="Deviance Residual";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* Predicted Severity Distribution
*-----------------------------------------------------------------------*/

title3 "Predicted Mean Severity";

proc sgplot data=work.Gamma_Null_Pred;

    histogram Pred_Severity /
              nbins=25;

    xaxis label="Predicted Severity";
    yaxis label="Frequency";

run;

ods graphics off;

title;
