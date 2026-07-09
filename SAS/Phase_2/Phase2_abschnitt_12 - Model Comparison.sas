/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.12 - Model Comparison
*
* Purpose:
*   Compare the Gamma GLM and the Inverse Gaussian GLM.
*
*   Compared statistics:
*      - Log Likelihood
*      - AIC
*      - AICC
*      - BIC
*      - Deviance
*      - Pearson Chi-Square
*
* Input:
*      WORK.GAMMA_REDUCED_MODELFIT
*      WORK.IG_FULL_MODELFIT
*
* Output:
*      WORK.MODEL_COMPARISON
*
**************************************************************************/

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.12 - Gamma vs. Inverse Gaussian";

/*-----------------------------------------------------------------------
* Step 1 : Prepare Gamma Model Statistics
*-----------------------------------------------------------------------*/

data Gamma_ModelFit;

    length Model $20 Criterion $40;

    set work.Gamma_Reduced_ModelFit;

    Model = "Gamma";

    keep Model Criterion Value;

run;


/*-----------------------------------------------------------------------
* Step 2 : Prepare Inverse Gaussian Statistics
*-----------------------------------------------------------------------*/

data IG_ModelFit;

    length Model $20 Criterion $40;

    set work.IG_Full_ModelFit;

    Model = "Inverse Gaussian";

    keep Model Criterion Value;

run;


/*-----------------------------------------------------------------------
* Step 3 : Combine Both Models
*-----------------------------------------------------------------------*/

data work.ModelFit_All;

    set Gamma_ModelFit
        IG_ModelFit;

run;


/*-----------------------------------------------------------------------
* Step 4 : Create Comparison Table
*-----------------------------------------------------------------------*/

proc sql;

create table work.Model_Comparison as

select

       Criterion,

       max(case
              when Model="Gamma"
              then Value
           end)                        as Gamma format=14.4,

       max(case
              when Model="Inverse Gaussian"
              then Value
           end)                        as Inverse_Gaussian format=14.4

from work.ModelFit_All

group by Criterion

order by Criterion;

quit;


/*-----------------------------------------------------------------------
* Step 5 : Print Comparison
*-----------------------------------------------------------------------*/

title3 "Goodness-of-Fit Comparison";

proc print
    data=work.Model_Comparison
    noobs
    label;

    label

        Criterion          = "Statistic"
        Gamma              = "Gamma GLM"
        Inverse_Gaussian   = "Inverse Gaussian GLM";

run;


/*-----------------------------------------------------------------------
* Step 6 : Determine Best Model
*-----------------------------------------------------------------------*/

proc sql noprint;

    select Gamma
        into :Gamma_AIC
    from work.Model_Comparison
    where upcase(Criterion) contains "AIC";

    select Inverse_Gaussian
        into :IG_AIC
    from work.Model_Comparison
    where upcase(Criterion) contains "AIC";

quit;


data work.Model_Recommendation;

    length Best_Model $30 Reason $80;

    Gamma_AIC=&Gamma_AIC;
    IG_AIC=&IG_AIC;

    if Gamma_AIC < IG_AIC then do;

        Best_Model="Gamma GLM";
        Reason="Lower AIC";

    end;

    else do;

        Best_Model="Inverse Gaussian GLM";
        Reason="Lower AIC";

    end;

run;


/*-----------------------------------------------------------------------
* Step 7 : Recommendation
*-----------------------------------------------------------------------*/

title3 "Recommended Severity Model";

proc print
    data=work.Model_Recommendation
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Step 8 : Write Results to SAS Log
*-----------------------------------------------------------------------*/

data _null_;

    set work.Model_Recommendation;

    put;
    put "========================================================";
    put "        MODEL COMPARISON";
    put "========================================================";
    put " Gamma AIC             = " Gamma_AIC 12.4;
    put " Inverse Gaussian AIC  = " IG_AIC 12.4;
    put;
    put " Recommended Model     = " Best_Model;
    put " Selection Criterion   = " Reason;
    put "========================================================";

run;

title;
