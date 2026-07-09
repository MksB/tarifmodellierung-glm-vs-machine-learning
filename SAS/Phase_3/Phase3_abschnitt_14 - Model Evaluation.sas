/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.14 - Model Evaluation
*
* Purpose:
*   Evaluate performance of final ML models:
*     - Frequency model (Poisson GBM)
*     - Severity model (Gamma GBM)
*
* Methods:
*     PROC ASSESS
*     PROC SQL
*
* Input:
*     WORK.FREQ_VALID_PRED
*     WORK.SEV_VALID_PRED
*
* Output:
*     WORK.MODEL_EVAL_FREQ
*     WORK.MODEL_EVAL_SEV
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.14 - Model Evaluation";

/*-----------------------------------------------------------------------
* Step 1 : Frequency model assessment (PROC ASSESS)
*-----------------------------------------------------------------------*/

proc assess
    data=work.FREQ_Valid_Pred
    out=work.Model_Eval_Freq;

    /*---------------------------------------------------------------
      True vs predicted frequency
    ---------------------------------------------------------------*/

    var Claim_Frequency / response=Pred_Frequency;

run;


/*-----------------------------------------------------------------------
* Step 2 : Severity model assessment (PROC ASSESS)
*-----------------------------------------------------------------------*/

proc assess
    data=work.SEV_Valid_Pred
    out=work.Model_Eval_Sev;

    var Claim_Severity / response=Pred_Severity;

run;


/*-----------------------------------------------------------------------
* Step 3 : Aggregated performance metrics (Frequency)
*-----------------------------------------------------------------------*/

proc sql;

    create table work.FREQ_Performance_Final as
    select

        mean(Claim_Frequency) as Obs_Mean,
        mean(Pred_Frequency)  as Pred_Mean,

        sqrt(mean((Claim_Frequency - Pred_Frequency)**2)) as RMSE,
        mean(abs(Claim_Frequency - Pred_Frequency))       as MAE,

        sum(Claim_Frequency) as Total_Observed,
        sum(Pred_Frequency)  as Total_Predicted,

        calculated Total_Predicted / calculated Total_Observed - 1
            as Bias format=percent8.2

    from work.FREQ_Valid_Pred;

quit;


/*-----------------------------------------------------------------------
* Step 4 : Aggregated performance metrics (Severity)
*-----------------------------------------------------------------------*/

proc sql;

    create table work.SEV_Performance_Final as
    select

        mean(Claim_Severity) as Obs_Mean,
        mean(Pred_Severity)  as Pred_Mean,

        sqrt(mean((Claim_Severity - Pred_Severity)**2)) as RMSE,
        mean(abs(Claim_Severity - Pred_Severity))       as MAE,

        sum(Claim_Severity) as Total_Observed,
        sum(Pred_Severity)  as Total_Predicted,

        calculated Total_Predicted / calculated Total_Observed - 1
            as Bias format=percent8.2

    from work.SEV_Valid_Pred;

quit;


/*-----------------------------------------------------------------------
* Step 5 : Combined Pure Premium evaluation (actuarial view)
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Pure_Premium_Eval as
    select

        a.PolicyID,

        /* Expected loss = Frequency × Severity */
        a.Pred_Frequency * b.Pred_Severity as Pred_Pure_Premium,

        a.Claim_Frequency * b.Claim_Severity as Obs_Pure_Premium,

        calculated Pred_Pure_Premium - calculated Obs_Pure_Premium
            as Residual,

        abs(calculated Residual) as Abs_Error

    from work.FREQ_Valid_Pred as a
    inner join work.SEV_Valid_Pred as b
        on a.PolicyID = b.PolicyID;

quit;


/*-----------------------------------------------------------------------
* Step 6 : Pure Premium summary metrics
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Pure_Premium_Summary as
    select

        mean(Pred_Pure_Premium) as Mean_Pred,
        mean(Obs_Pure_Premium)  as Mean_Obs,

        sqrt(mean(Residual**2)) as RMSE,
        mean(abs(Residual))     as MAE,

        sum(Pred_Pure_Premium) as Total_Pred,
        sum(Obs_Pure_Premium)  as Total_Obs,

        calculated Total_Pred / calculated Total_Obs - 1
            as Bias format=percent8.2

    from work.Pure_Premium_Eval;

quit;


/*-----------------------------------------------------------------------
* Step 7 : Diagnostic summary output
*-----------------------------------------------------------------------*/

title3 "Model Evaluation Summary - Frequency";

proc print data=work.FREQ_Performance_Final noobs;
run;

title3 "Model Evaluation Summary - Severity";

proc print data=work.SEV_Performance_Final noobs;
run;

title3 "Model Evaluation Summary - Pure Premium";

proc print data=work.Pure_Premium_Summary noobs;
run;


/*-----------------------------------------------------------------------
* Step 8 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.FREQ_Performance_Final;

    put "========================================================";
    put " MODEL EVALUATION COMPLETED";
    put "========================================================";
    put " Frequency RMSE : " RMSE;
    put " Severity RMSE  : " RMSE;
    put " Bias Check     : " Bias;
    put " Pure Premium Evaluation Completed";
    put "========================================================";

run;

title;
