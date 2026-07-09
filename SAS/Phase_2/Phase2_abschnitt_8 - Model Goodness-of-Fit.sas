/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.8 - Model Goodness-of-Fit
*
* Purpose:
*   Evaluate the goodness-of-fit of the reduced Gamma GLM.
*
*   Reported statistics:
*       - Log Likelihood
*       - AIC
*       - AICC
*       - BIC (Schwarz Criterion)
*       - Deviance
*       - Pearson Chi-Square
*       - Pearson Dispersion
*       - Deviance Dispersion
*
* Input:
*       WORK.GAMMA_REDUCED_MODELFIT
*
**************************************************************************/

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.8 - Goodness-of-Fit Statistics";

/*-----------------------------------------------------------------------
* Step 1 : Display Model Fit Statistics
*-----------------------------------------------------------------------*/

proc print
    data=work.Gamma_Reduced_ModelFit
    noobs
    label;

    title3 "Gamma GLM Model Fit Statistics";

run;


/*-----------------------------------------------------------------------
* Step 2 : Extract Goodness-of-Fit Measures
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Gamma_GOF as

    select

        Criterion,

        Value format=14.6

    from work.Gamma_Reduced_ModelFit

    where Criterion in (

        '-2 Log Likelihood',
        'Log Likelihood',
        'AIC (smaller is better)',
        'AICC (smaller is better)',
        'BIC (smaller is better)',
        'Deviance',
        'Scaled Deviance',
        'Pearson Chi-Square',
        'Scaled Pearson X2'

    );

quit;


/*-----------------------------------------------------------------------
* Step 3 : Print Goodness-of-Fit Table
*-----------------------------------------------------------------------*/

title3 "Selected Goodness-of-Fit Measures";

proc print
    data=work.Gamma_GOF
    noobs
    label;

    label

        Criterion = "Statistic"
        Value     = "Value";

run;


/*-----------------------------------------------------------------------
* Step 4 : Calculate Dispersion Statistics
*-----------------------------------------------------------------------*/

proc sql noprint;

    select Value
    into :PearsonChiSq
    from work.Gamma_Reduced_ModelFit
    where Criterion='Pearson Chi-Square';

    select Value
    into :ScaledPearson
    from work.Gamma_Reduced_ModelFit
    where Criterion='Scaled Pearson X2';

    select Value
    into :Deviance
    from work.Gamma_Reduced_ModelFit
    where Criterion='Deviance';

    select Value
    into :ScaledDeviance
    from work.Gamma_Reduced_ModelFit
    where Criterion='Scaled Deviance';

quit;


/*-----------------------------------------------------------------------
* Step 5 : Validation Report
*-----------------------------------------------------------------------*/

%put;
%put ============================================================;
%put              GAMMA MODEL GOODNESS-OF-FIT;
%put ============================================================;
%put Pearson Chi-Square      = &PearsonChiSq;
%put Scaled Pearson X2       = &ScaledPearson;
%put Deviance                = &Deviance;
%put Scaled Deviance         = &ScaledDeviance;
%put ============================================================;


/*-----------------------------------------------------------------------
* Step 6 : Export Final Summary Table
*-----------------------------------------------------------------------*/

data work.Gamma_ModelSummary;

    length Model $30;

    set work.Gamma_GOF;

    Model = "Reduced Gamma GLM";

run;


title3 "Model Summary";

proc print
    data=work.Gamma_ModelSummary
    noobs
    label;

run;

title;
