/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.11 - Hyperparameter Search
*
* Purpose:
*   Perform hyperparameter tuning for Gradient Boosting model.
*
* Method:
*   Macro-driven grid search using PROC GRADBOOST.
*
* Input:
*      WORK.ML_TRAIN_FINAL
*      WORK.ML_VALID
*
* Output:
*      WORK.HP_RESULTS
*      WORK.BEST_PARAMS
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.11 - Hyperparameter Search";

/*-----------------------------------------------------------------------
* Step 1 : Define hyperparameter grid
*-----------------------------------------------------------------------*/

%let MAX_DEPTH_LIST = 3 5 7;
%let LEARN_RATE_LIST = 0.05 0.1;
%let N_TREES_LIST = 100 200;
%let SUBSAMPLE_LIST = 0.7 0.9;

/*-----------------------------------------------------------------------
* Step 2 : Results container
*-----------------------------------------------------------------------*/

data work.HP_Results;
    length Model $20;
    stop;
run;

/*-----------------------------------------------------------------------
* Step 3 : Hyperparameter search macro
*-----------------------------------------------------------------------*/

%macro hp_search;

%local d l n s;

%do d = 1 %to 3;
%do l = 1 %to 2;
%do n = 1 %to 2;
%do s = 1 %to 2;

/* Map values */
%let DEPTH = %scan(&MAX_DEPTH_LIST, &d);
%let LR    = %scan(&LEARN_RATE_LIST, &l);
%let TREES = %scan(&N_TREES_LIST, &n);
%let SUB   = %scan(&SUBSAMPLE_LIST, &s);

/*-------------------------------------------------------------------
  Train Gradient Boosting Model
-------------------------------------------------------------------*/

proc gradboost
    data=work.ML_Train_Final
    seed=20250506
    ntrees=&TREES.
    learningrate=&LR.
    maxdepth=&DEPTH.
    subsample=&SUB.
    distribution=gamma
    outmodel=work._model_tmp;

    input
        VehPower Density BonusMalus VehAge DrivAge Exposure
        VehGas_ID VehBrand_ID Region_ID Area_ID
        / level=interval;

    target Claim_Severity / level=interval;

    output out=work._pred_tmp pred=Pred;

run;

/*-------------------------------------------------------------------
  Score validation set
-------------------------------------------------------------------*/

proc gradboost
    inmodel=work._model_tmp
    data=work.ML_Valid
    out=work._scored_tmp;

run;

/*-------------------------------------------------------------------
  Evaluate performance
-------------------------------------------------------------------*/

proc sql noprint;

    select mean((Claim_Severity - Pred)*(Claim_Severity - Pred))
    into :RMSE
    from work._scored_tmp;

quit;

/*-------------------------------------------------------------------
  Store results
-------------------------------------------------------------------*/

data work.HP_Results;

    set work.HP_Results
        end=eof;

    if eof then do;

        Model = "GBM";

        MaxDepth = &DEPTH.;
        LearningRate = &LR.;
        NTrees = &TREES.;
        Subsample = &SUB.;

        RMSE = &RMSE.;

        output;
    end;

run;

%end;
%end;
%end;
%end;

%mend;

/*-----------------------------------------------------------------------
* Step 4 : Run search
*-----------------------------------------------------------------------*/

%hp_search;

/*-----------------------------------------------------------------------
* Step 5 : Select best model
*-----------------------------------------------------------------------*/

proc sql;

    create table work.Best_Params as

    select *

    from work.HP_Results

    having RMSE = min(RMSE);

quit;

/*-----------------------------------------------------------------------
* Step 6 : Print results
*-----------------------------------------------------------------------*/

title3 "Hyperparameter Search Results";

proc print
    data=work.HP_Results
    noobs;

run;

title3 "Best Parameter Set";

proc print
    data=work.Best_Params
    noobs;

run;

/*-----------------------------------------------------------------------
* Step 7 : Log summary
*-----------------------------------------------------------------------*/

data _null_;

    set work.Best_Params;

    put "========================================================";
    put " HYPERPARAMETER OPTIMIZATION COMPLETED";
    put "========================================================";
    put " Best RMSE       : " RMSE;
    put " MaxDepth        : " MaxDepth;
    put " Learning Rate   : " LearningRate;
    put " N Trees         : " NTrees;
    put " Subsample       : " Subsample;
    put "========================================================";

run;

title;
