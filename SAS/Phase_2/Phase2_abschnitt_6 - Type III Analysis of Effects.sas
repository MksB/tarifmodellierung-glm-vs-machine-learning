/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.6 - Type III Analysis of Effects
*
* Purpose:
*   Analyse the statistical significance of each rating factor in the
*   full Gamma GLM using Type III Likelihood Ratio Tests.
*
*   The resulting table is used for:
*
*      - Variable selection
*      - Identification of insignificant predictors
*      - Construction of the reduced Gamma GLM
*
* Input:
*      WORK.GAMMA_FULL_TYPE3
*
**************************************************************************/

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.6 - Type III Analysis of Effects";

/*-----------------------------------------------------------------------
* Step 1 : Display Type III Tests
*-----------------------------------------------------------------------*/

proc print
    data=work.Gamma_Full_Type3
    noobs
    label;

    var
        Source
        DF
        ChiSq
        ProbChiSq;

    label

        Source     = "Rating Factor"
        DF         = "Degrees of Freedom"
        ChiSq  = "Wald Chi-Square"
        ProbChiSq  = "p-Value";

    format ProbChiSq pvalue8.4;

run;


/*-----------------------------------------------------------------------
* Step 2 : Rank Variables by Statistical Significance
*-----------------------------------------------------------------------*/

proc sort
    data=work.Gamma_Full_Type3
    out=work.Gamma_Type3_Sorted;

    by ProbChiSq;

run;

title3 "Ranking of Rating Factors";

proc print
    data=work.Gamma_Type3_Sorted
    noobs
    label;

    var
        Source
        DF
        WaldChiSq
        ProbChiSq;

    format ProbChiSq pvalue8.4;

run;


/*-----------------------------------------------------------------------
* Step 3 : Classify Significant Effects
*-----------------------------------------------------------------------*/

data work.Gamma_Type3_Result;

    set work.Gamma_Type3_Sorted;

    length Significance $20;

    if ProbChiSq < 0.001 then
        Significance = "*** Highly Significant";

    else if ProbChiSq < 0.01 then
        Significance = "** Significant";

    else if ProbChiSq < 0.05 then
        Significance = "* Significant";

    else
        Significance = "Not Significant";

run;


/*-----------------------------------------------------------------------
* Step 4 : Print Final Results
*-----------------------------------------------------------------------*/

title3 "Classification of Rating Factors";

proc print
    data=work.Gamma_Type3_Result
    noobs
    label;

    var
        Source
        DF
        ChiSq
        ProbChiSq
        Significance;

    format ProbChiSq pvalue8.4;

run;


/*-----------------------------------------------------------------------
* Step 5 : Significant Variables (a = 0.05)
*-----------------------------------------------------------------------*/

data work.Gamma_SelectedEffects;

    set work.Gamma_Type3_Result;

    where ProbChiSq < 0.05;

run;

title3 "Variables Selected for the Reduced Gamma GLM";

proc print
    data=work.Gamma_SelectedEffects
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Step 6 : Non-significant Variables
*-----------------------------------------------------------------------*/

data work.Gamma_RemovedEffects;

    set work.Gamma_Type3_Result;

    where ProbChiSq >= 0.05;

run;

title3 "Variables Suggested for Removal";

proc print
    data=work.Gamma_RemovedEffects
    noobs
    label;

run;

title;
