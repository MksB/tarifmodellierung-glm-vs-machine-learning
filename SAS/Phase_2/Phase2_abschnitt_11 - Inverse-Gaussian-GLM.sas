/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.11 - Inverse Gaussian GLM (Full Model)
*
* Purpose:
*   Fit the full Inverse Gaussian GLM for claim severity.
*
* Response:
*      Severity
*
* Distribution:
*      Inverse Gaussian
*
* Link Function:
*      Log
*
* NOTE:
*   - No offset is used for severity modelling.
*   - Analytical weights = ClaimNb (equivalent to R weights=ClaimNb).
*
* Input:
*      WORK.SEVERITY_GLM
*
* Output:
*      WORK.IG_FULL_PE
*      WORK.IG_FULL_TYPE3
*      WORK.IG_FULL_MODELFIT
*      WORK.IG_FULL_CRITERIA
*      WORK.IG_FULL_PRED
*
**************************************************************************/

ods graphics on;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.11 - Inverse Gaussian GLM (Full Model)";

/*-----------------------------------------------------------------------
* Save ODS Output Tables
*-----------------------------------------------------------------------*/

ods output
    ParameterEstimates = work.IG_Full_PE
    Type3              = work.IG_Full_Type3
    ModelFit           = work.IG_Full_ModelFit
    Criteria           = work.IG_Full_Criteria;

/*-----------------------------------------------------------------------
* Fit Inverse Gaussian GLM
*-----------------------------------------------------------------------*/

proc genmod data=work.SEVERITY_GLM;

    class

        VehPower   (ref=first)
        VehAge     (ref=first)
        DrivAge    (ref=first)
        BonusMalus (ref=first)
        VehBrand   (ref=first)
        VehGas     (ref=first)
        Area       (ref=first)
        Region     (ref=first)

        / param=ref;

    model Severity =

          VehPower
          VehAge
          DrivAge
          BonusMalus
          VehBrand
          VehGas
          Area
          Density
          Region

          /

          dist=igaussian
          link=log
          type3
          lrci;

    /*---------------------------------------------------------------
      Analytical Weights
    ---------------------------------------------------------------*/

    weight ClaimNb;

    /*---------------------------------------------------------------
      Predicted Values and Residuals
    ---------------------------------------------------------------*/

    output out = work.IG_Full_Pred

        pred      = PredSeverity
        xbeta     = LinearPredictor

        resraw    = RawResidual
        resdev    = DevianceResidual
        reschi    = PearsonResidual

        stdresdev = StdDevianceResidual
        stdreschi = StdPearsonResidual;

run;


/*-----------------------------------------------------------------------
* Parameter Estimates
*-----------------------------------------------------------------------*/

title3 "Inverse Gaussian GLM - Parameter Estimates";

proc print
    data=work.IG_Full_PE
    noobs
    label;
run;


/*-----------------------------------------------------------------------
* Type III Tests
*-----------------------------------------------------------------------*/

title3 "Type III Analysis of Effects";

proc print
    data=work.IG_Full_Type3
    noobs
    label;
run;


/*-----------------------------------------------------------------------
* Goodness-of-Fit Statistics
*-----------------------------------------------------------------------*/

title3 "Model Fit Statistics";

proc print
    data=work.IG_Full_ModelFit
    noobs
    label;
run;


/*-----------------------------------------------------------------------
* Residual Diagnostics
*-----------------------------------------------------------------------*/

title3 "Residual Diagnostics";

proc means
    data=work.IG_Full_Pred
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
        PearsonResidual
        StdDevianceResidual
        StdPearsonResidual;

run;


/*-----------------------------------------------------------------------
* Observed vs Predicted Severity
*-----------------------------------------------------------------------*/

title3 "Observed versus Predicted Severity";

proc sgplot
    data=work.IG_Full_Pred;

    scatter
        x=PredSeverity
        y=Severity
        / transparency=0.70;

    lineparm
        x=0
        y=0
        slope=1;

    xaxis label="Predicted Severity";
    yaxis label="Observed Severity";

run;


/*-----------------------------------------------------------------------
* Residual Distribution
*-----------------------------------------------------------------------*/

title3 "Distribution of Deviance Residuals";

proc sgplot
    data=work.IG_Full_Pred;

    histogram DevianceResidual / nbins=30;

    density DevianceResidual / type=kernel;

    xaxis label="Deviance Residual";
    yaxis label="Density";

run;

ods graphics off;

title;
