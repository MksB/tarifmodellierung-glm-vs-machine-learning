/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.5 - Gamma GLM (Full Model)
*
* Purpose:
*   Fit the full Gamma GLM for claim severity.
*
* Response:
*      Severity
*
* Distribution:
*      Gamma
*
* Link:
*      Log
*
* IMPORTANT
* -------------------------------------------------------------------------
* In contrast to the Poisson frequency model, NO OFFSET is used here.
* Claim severity is independent of policy exposure.
*
* To reproduce the R implementation, the number of claims is used as
* analytical weight.
*
* R:
* glm(AvgClaim ~ ..., family=Gamma(link="log"), weights=ClaimNb)
*
**************************************************************************/

ods graphics on;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.5 - Gamma GLM (Full Model)";

/*-----------------------------------------------------------------------
* Save all important ODS tables
*-----------------------------------------------------------------------*/

ods output

    ParameterEstimates = work.Gamma_Full_PE
    ModelFit           = work.Gamma_Full_ModelFit
    Type3              = work.Gamma_Full_Type3
    Criteria           = work.Gamma_Full_Criteria;


/*-----------------------------------------------------------------------
* Gamma GLM (Full Model)
*-----------------------------------------------------------------------*/

proc genmod data=work.Severity_GLM;

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

          dist=gamma
          link=log
          type3
          lrci;

    /*---------------------------------------------------------------
      Analytical weights

      R:
          weights = ClaimNb
    ---------------------------------------------------------------*/

    weight ClaimNb;

    /*---------------------------------------------------------------
      Store predictions and residuals
    ---------------------------------------------------------------*/

    output out = work.Gamma_Full_Pred

        pred    = PredSeverity
        xbeta   = LinearPredictor

        resraw  = RawResidual
        resdev  = DevianceResidual
        reschi  = PearsonResidual

        stdresdev = StdDevianceResidual
        stdreschi = StdPearsonResidual;

run;


/*-----------------------------------------------------------------------
* Parameter Estimates
*-----------------------------------------------------------------------*/

title3 "Gamma GLM - Parameter Estimates";

proc print
    data=work.Gamma_Full_PE
    label
    noobs;
run;


/*-----------------------------------------------------------------------
* Type III Analysis
*-----------------------------------------------------------------------*/

title3 "Type III Likelihood Tests";

proc print
    data=work.Gamma_Full_Type3
    label
    noobs;
run;


/*-----------------------------------------------------------------------
* Model Fit Statistics
*-----------------------------------------------------------------------*/

title3 "Model Fit Statistics";

proc print
    data=work.Gamma_Full_ModelFit
    label
    noobs;
run;


/*-----------------------------------------------------------------------
* Residual Summary
*-----------------------------------------------------------------------*/

title3 "Residual Diagnostics";

proc means
    data=work.Gamma_Full_Pred

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
* Observed versus Predicted
*-----------------------------------------------------------------------*/

title3 "Observed versus Predicted Severity";

proc sgplot
    data=work.Gamma_Full_Pred;

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

ods graphics off;

title;
