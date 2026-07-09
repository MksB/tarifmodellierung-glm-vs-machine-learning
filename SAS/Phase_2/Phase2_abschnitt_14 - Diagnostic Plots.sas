/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.14 - Diagnostic Plots
*
* Purpose:
*   Diagnostic assessment of the reduced Gamma GLM.
*
*   Diagnostics:
*      1. Observed vs Predicted
*      2. Residuals vs Predicted
*      3. Pearson Residuals vs Predicted
*      4. Deviance Residuals vs Predicted
*      5. Histogram of Deviance Residuals
*      6. QQ Plot of Deviance Residuals
*      7. Histogram of Pearson Residuals
*
* Input:
*      WORK.GAMMA_REDUCED_PRED
*
**************************************************************************/

ods graphics on / reset width=7in height=5in imagemap;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.14 - Diagnostic Plots";



/*-----------------------------------------------------------------------
* 2.14.1 Observed versus Predicted
*-----------------------------------------------------------------------*/

title3 "Observed versus Predicted Severity";

proc sgplot data=work.Gamma_Reduced_Pred;

    scatter
        x=PredictedSeverity
        y=Severity
        / transparency=0.60
          markerattrs=(symbol=circlefilled size=6);

    lineparm
        x=0
        y=0
        slope=1
        / lineattrs=(thickness=2);

    xaxis label="Predicted Severity";
    yaxis label="Observed Severity";

run;



/*-----------------------------------------------------------------------
* 2.14.2 Raw Residuals versus Predicted
*-----------------------------------------------------------------------*/

title3 "Raw Residuals versus Predicted Values";

proc sgplot data=work.Gamma_Reduced_Pred;

    scatter
        x=PredictedSeverity
        y=RawResidual
        / transparency=0.60
          markerattrs=(symbol=circlefilled size=5);

    refline 0 / axis=y;

    xaxis label="Predicted Severity";
    yaxis label="Raw Residual";

run;



/*-----------------------------------------------------------------------
* 2.14.3 Pearson Residuals
*-----------------------------------------------------------------------*/

title3 "Pearson Residuals versus Predicted Values";

proc sgplot data=work.Gamma_Reduced_Pred;

    scatter
        x=PredictedSeverity
        y=PearsonResidual
        / transparency=0.60
          markerattrs=(symbol=circlefilled size=5);

    refline 0 / axis=y;

    xaxis label="Predicted Severity";
    yaxis label="Pearson Residual";

run;



/*-----------------------------------------------------------------------
* 2.14.4 Deviance Residuals
*-----------------------------------------------------------------------*/

title3 "Deviance Residuals versus Predicted Values";

proc sgplot data=work.Gamma_Reduced_Pred;

    scatter
        x=PredictedSeverity
        y=DevianceResidual
        / transparency=0.60
          markerattrs=(symbol=circlefilled size=5);

    refline 0 / axis=y;

    xaxis label="Predicted Severity";
    yaxis label="Deviance Residual";

run;



/*-----------------------------------------------------------------------
* 2.14.5 Histogram of Deviance Residuals
*-----------------------------------------------------------------------*/

title3 "Distribution of Deviance Residuals";

proc sgplot data=work.Gamma_Reduced_Pred;

    histogram DevianceResidual
        / nbins=35;

    density DevianceResidual
        / type=kernel;

    refline 0 / axis=x;

    xaxis label="Deviance Residual";
    yaxis label="Frequency";

run;



/*-----------------------------------------------------------------------
* 2.14.6 QQ Plot
*-----------------------------------------------------------------------*/

title3 "Normal QQ Plot of Deviance Residuals";

proc univariate
    data=work.Gamma_Reduced_Pred
    normal;

    var DevianceResidual;

    qqplot DevianceResidual
        / normal(mu=est sigma=est);

run;



/*-----------------------------------------------------------------------
* 2.14.7 Histogram of Pearson Residuals
*-----------------------------------------------------------------------*/

title3 "Distribution of Pearson Residuals";

proc sgplot data=work.Gamma_Reduced_Pred;

    histogram PearsonResidual
        / nbins=35;

    density PearsonResidual
        / type=kernel;

    refline 0 / axis=x;

    xaxis label="Pearson Residual";
    yaxis label="Frequency";

run;



/*-----------------------------------------------------------------------
* 2.14.8 Summary Statistics of Residuals
*-----------------------------------------------------------------------*/

title3 "Residual Summary Statistics";

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
    skewness
    kurtosis
    maxdec=4;

    var
        RawResidual
        PearsonResidual
        DevianceResidual;

run;

ods graphics off;

title;
