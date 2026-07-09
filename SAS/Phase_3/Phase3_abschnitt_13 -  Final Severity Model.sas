/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.13 - Final Severity Model
*
* Purpose:
*   Train final production-grade severity model using Gradient Boosting.
*
* Model:
*   - Distribution : Gamma
*   - Link function: Log
*
* Input:
*      WORK.ML_TRAIN_FINAL
*      WORK.ML_VALID
*      WORK.BEST_PARAMS
*
* Output:
*      WORK.SEV_MODEL
*      WORK.SEV_PRED
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.13 - Final Severity Model (Gamma GBM)";

/*-----------------------------------------------------------------------
* Step 1 : Retrieve best hyperparameters
*-----------------------------------------------------------------------*/

proc sql noprint;

    select MaxDepth, LearningRate, NTrees, Subsample
    into :BEST_DEPTH, :BEST_LR, :BEST_TREES, :BEST_SUB
    from work.Best_Params;

quit;


/*-----------------------------------------------------------------------
* Step 2 : Train final Gamma GBM model
*-----------------------------------------------------------------------*/

proc gradboost
    data=work.ML_Train_Final
    seed=20250506
    ntrees=&BEST_TREES.
    learningrate=&BEST_LR.
    maxdepth=&BEST_DEPTH.
    subsample=&BEST_SUB.
    distribution=gamma
    outmodel=work.SEV_Model;

    /*---------------------------------------------------------------
      Input features (same engineered feature space as frequency model)
    ---------------------------------------------------------------*/

    input
        VehPower
        Density
        BonusMalus
        VehAge
        DrivAge
        VehGas_ID
        VehBrand_ID
        Region_ID
        Area_ID
        Log_Density
        Z_Power
        Z_BM
        Risk_Index
        Power_to_Age
        / level=interval;

    /*---------------------------------------------------------------
      Target variable (severity modeling)
    ---------------------------------------------------------------*/

    target Claim_Severity / level=interval;

    /*---------------------------------------------------------------
      Optional stability handling (Gamma requires positive target)
    ---------------------------------------------------------------*/

    where Claim_Severity > 0;

    /*---------------------------------------------------------------
      Output predictions
    ---------------------------------------------------------------*/

    output out=work.SEV_Pred pred=Pred_Severity;

run;


/*-----------------------------------------------------------------------
* Step 3 : Score validation dataset
*-----------------------------------------------------------------------*/

proc gradboost
    inmodel=work.SEV_Model
    data=work.ML_Valid
    out=work.SEV_Valid_Pred;

run;


/*-----------------------------------------------------------------------
* Step 4 : Model performance evaluation
*-----------------------------------------------------------------------*/

proc sql;

    create table work.SEV_Performance as
    select

        mean(Claim_Severity) as Obs_Mean,
        mean(Pred_Severity)  as Pred_Mean,

        mean( (Claim_Severity - Pred_Severity)**2 ) as MSE,
        mean( abs(Claim_Severity - Pred_Severity) ) as MAE,

        sum(Claim_Severity) as Total_Observed,
        sum(Pred_Severity)  as Total_Predicted

    from work.SEV_Valid_Pred;

quit;


/*-----------------------------------------------------------------------
* Step 5 : Diagnostic dataset creation
*-----------------------------------------------------------------------*/

data work.SEV_Diagnostics;

    set work.SEV_Valid_Pred;

    Residual = Claim_Severity - Pred_Severity;

    AbsError = abs(Residual);

    SquaredError = Residual * Residual;

    Log_Residual = log(max(Claim_Severity,0.0001))
                 - log(max(Pred_Severity,0.0001));

run;


/*-----------------------------------------------------------------------
* Step 6 : Residual analysis
*-----------------------------------------------------------------------*/

title3 "Severity Model Diagnostics";

proc means
    data=work.SEV_Diagnostics
    n mean std min p1 p50 p99 max;

    var Residual AbsError SquaredError Log_Residual;

run;


/*-----------------------------------------------------------------------
* Step 7 : Variable importance (if supported in PROC)
*-----------------------------------------------------------------------*/

title3 "Variable Importance - Severity Model";

proc gradboost
    inmodel=work.SEV_Model
    printimportance;

run;


/*-----------------------------------------------------------------------
* Step 8 : Check distribution of predictions
*-----------------------------------------------------------------------*/

title3 "Predicted Severity Distribution";

proc means
    data=work.SEV_Valid_Pred
    n mean std min p1 p50 p99 max;

    var Pred_Severity Claim_Severity;

run;


/*-----------------------------------------------------------------------
* Step 9 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.SEV_Model end=eof;

    if eof then do;

        put "========================================================";
        put " FINAL SEVERITY MODEL TRAINED";
        put "========================================================";
        put " Model Type      : PROC GRADBOOST (Gamma)";
        put " Target          : Claim_Severity";
        put " Key Features    : Engineered ML feature space";
        put " Best Parameters : Retrieved from WORK.BEST_PARAMS";
        put " Output Model    : WORK.SEV_MODEL";
        put "========================================================";
    end;

run;

title;
