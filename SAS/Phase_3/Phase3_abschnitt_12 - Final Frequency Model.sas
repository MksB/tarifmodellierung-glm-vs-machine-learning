/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.12 - Final Frequency Model
*
* Purpose:
*   Train final production-grade frequency model using Gradient Boosting.
*
* Model:
*   - Distribution : Poisson
*   - Link function : Log
*   - Offset        : log(Exposure)
*
* Input:
*      WORK.ML_TRAIN_FINAL
*      WORK.ML_VALID
*      WORK.BEST_PARAMS
*
* Output:
*      WORK.FREQ_MODEL
*      WORK.FREQ_PRED
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.12 - Final Frequency Model (Poisson GBM)";

/*-----------------------------------------------------------------------
* Step 1 : Extract best hyperparameters
*-----------------------------------------------------------------------*/

proc sql noprint;

    select MaxDepth, LearningRate, NTrees, Subsample
    into :BEST_DEPTH, :BEST_LR, :BEST_TREES, :BEST_SUB
    from work.Best_Params;

quit;

/*-----------------------------------------------------------------------
* Step 2 : Train final Poisson GBM model
*-----------------------------------------------------------------------*/

proc gradboost
    data=work.ML_Train_Final
    seed=20250506
    ntrees=&BEST_TREES.
    learningrate=&BEST_LR.
    maxdepth=&BEST_DEPTH.
    subsample=&BEST_SUB.
    distribution=poisson
    outmodel=work.FREQ_Model;

    /*---------------------------------------------------------------
      Input features (engineered + encoded)
    ---------------------------------------------------------------*/

    input
        VehPower
        Density
        BonusMalus
        VehAge
        DrivAge
        Exposure
        VehGas_ID
        VehBrand_ID
        Region_ID
        Area_ID
        Log_Density
        Z_Power
        Z_BM
        Risk_Index
        / level=interval;

    /*---------------------------------------------------------------
      Target variable (frequency modeling)
    ---------------------------------------------------------------*/

    target Claim_Frequency / level=interval;

    /*---------------------------------------------------------------
      Offset = log exposure (important actuarial structure)
    ---------------------------------------------------------------*/

    offset Log_Exposure;

    /*---------------------------------------------------------------
      Save predictions
    ---------------------------------------------------------------*/

    output out=work.FREQ_Pred pred=Pred_Frequency;

run;


/*-----------------------------------------------------------------------
* Step 3 : Score validation dataset
*-----------------------------------------------------------------------*/

proc gradboost
    inmodel=work.FREQ_Model
    data=work.ML_Valid
    out=work.FREQ_Valid_Pred;

run;


/*-----------------------------------------------------------------------
* Step 4 : Performance evaluation (Poisson deviance approximation)
*-----------------------------------------------------------------------*/

proc sql;

    create table work.FREQ_Performance as
    select

        sum(Claim_Frequency) as Obs_Total,
        sum(Pred_Frequency)  as Pred_Total,

        mean( (Claim_Frequency - Pred_Frequency)**2 ) as MSE,
        mean( abs(Claim_Frequency - Pred_Frequency) ) as MAE

    from work.FREQ_Valid_Pred;

quit;


/*-----------------------------------------------------------------------
* Step 5 : Variable importance (if supported)
*-----------------------------------------------------------------------*/

title3 "Variable Importance - Frequency Model";

proc gradboost
    inmodel=work.FREQ_Model
    printimportance;

run;


/*-----------------------------------------------------------------------
* Step 6 : Output diagnostics dataset
*-----------------------------------------------------------------------*/

data work.FREQ_Diagnostics;

    set work.FREQ_Valid_Pred;

    Residual = Claim_Frequency - Pred_Frequency;

    AbsError = abs(Residual);

    SquaredError = Residual * Residual;

run;


/*-----------------------------------------------------------------------
* Step 7 : Summary statistics of residuals
*-----------------------------------------------------------------------*/

title3 "Model Diagnostics";

proc means
    data=work.FREQ_Diagnostics
    n mean std min p1 p50 p99 max;

    var Residual AbsError SquaredError;

run;


/*-----------------------------------------------------------------------
* Step 8 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.FREQ_Model end=eof;

    if eof then do;

        put "========================================================";
        put " FINAL FREQUENCY MODEL TRAINED";
        put "========================================================";
        put " Model Type      : PROC GRADBOOST (Poisson)";
        put " Target          : Claim_Frequency";
        put " Offset          : Log_Exposure";
        put " Best Parameters : Retrieved from WORK.BEST_PARAMS";
        put " Output Model    : WORK.FREQ_MODEL";
        put "========================================================";
    end;

run;

title;
