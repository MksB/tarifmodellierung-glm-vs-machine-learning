/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.13 - Intercept / Balance Correction
*
* Purpose:
*   Adjust the intercept so that the total predicted claim amount equals
*   the total observed claim amount.
*
* Mathematical Background
* -------------------------------------------------------------------------
*
*      Balance Factor = Observed Total / Predicted Total
*
*      ß0(new) = ß0(old) + log(Balance Factor)
*
*      µ(new) = µ(old) × Balance Factor
*
* Only the intercept is adjusted.
* All tariff relativities remain unchanged.
*
* Input
* -------------------------------------------------------------------------
*      WORK.GAMMA_REDUCED_PE
*      WORK.GAMMA_REDUCED_PRED
*
* Output
* -------------------------------------------------------------------------
*      WORK.GAMMA_BALANCE
*      WORK.GAMMA_REDUCED_PE_BAL
*      WORK.GAMMA_REDUCED_PRED_BAL
*
**************************************************************************/

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.13 - Intercept / Balance Correction";

/*-----------------------------------------------------------------------
* Step 1 : Portfolio Totals
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Gamma_Balance as

    select

        sum(Severity)          as Observed_Total   format=18.2,

        sum(PredictedSeverity) as Predicted_Total  format=18.2,

        calculated Observed_Total /
        calculated Predicted_Total

            as Balance_Factor format=12.8,

        log(calculated Balance_Factor)

            as Intercept_Shift format=12.8

    from work.Gamma_Reduced_Pred;

quit;


/*-----------------------------------------------------------------------
* Step 2 : Correct Intercept
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Gamma_Reduced_PE_Bal as

    select

        a.*,

        case

            when upcase(Parameter)="INTERCEPT"

            then a.Estimate + b.Intercept_Shift

            else a.Estimate

        end as Corrected_Estimate

    from work.Gamma_Reduced_PE as a

    cross join work.Gamma_Balance as b;

quit;


/*-----------------------------------------------------------------------
* Step 3 : Apply Correction to Predictions
*-----------------------------------------------------------------------*/

data work.Gamma_Reduced_Pred_Bal;

    if _N_=1 then
        set work.Gamma_Balance;

    set work.Gamma_Reduced_Pred;

    BalancedSeverity = PredictedSeverity * Balance_Factor;

run;


/*-----------------------------------------------------------------------
* Step 4 : Validation
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Gamma_Balance_Check as

    select

        sum(Severity)

            as Observed_Total format=18.2,

        sum(BalancedSeverity)

            as Balanced_Total format=18.2,

        calculated Balanced_Total
        -
        calculated Observed_Total

            as Difference format=18.6

    from work.Gamma_Reduced_Pred_Bal;

quit;


/*-----------------------------------------------------------------------
* Step 5 : Print Balance Factor
*-----------------------------------------------------------------------*/

title3 "Balance Correction";

proc print
    data=work.Gamma_Balance
    noobs
    label;

    label

        Observed_Total  = "Observed Portfolio Severity"
        Predicted_Total = "Predicted Portfolio Severity"
        Balance_Factor  = "Balance Factor"
        Intercept_Shift = "Intercept Adjustment";

run;


/*-----------------------------------------------------------------------
* Step 6 : Corrected Intercept
*-----------------------------------------------------------------------*/

title3 "Corrected Intercept";

proc print
    data=work.Gamma_Reduced_PE_Bal
    noobs
    label;

    where upcase(Parameter)="INTERCEPT";

    var

        Parameter
        Estimate
        Corrected_Estimate;

    label

        Estimate            = "Original Estimate"
        Corrected_Estimate  = "Balanced Estimate";

run;


/*-----------------------------------------------------------------------
* Step 7 : Portfolio Validation
*-----------------------------------------------------------------------*/

title3 "Portfolio Balance Validation";

proc print
    data=work.Gamma_Balance_Check
    noobs
    label;

run;


/*-----------------------------------------------------------------------
* Step 8 : Write Summary to SAS Log
*-----------------------------------------------------------------------*/

data _null_;

    set work.Gamma_Balance;

    put;
    put "==============================================================";
    put "          INTERCEPT BALANCE CORRECTION";
    put "==============================================================";
    put " Observed Portfolio Total : " Observed_Total 18.2;
    put " Predicted Portfolio Total: " Predicted_Total 18.2;
    put " Balance Factor           : " Balance_Factor 12.8;
    put " Intercept Shift          : " Intercept_Shift 12.8;
    put "==============================================================";

run;

title;
