/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.10 - K-Fold Cross Validation
*
* Purpose:
*   Create K-Fold cross validation structure (K=5).
*
*   Equivalent to Python:
*       KFold(n_splits=5, shuffle=True, random_state=...)
*
* Input:
*      WORK.ML_TRAIN_FINAL
*
* Output:
*      WORK.ML_KFOLD
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.10 - K-Fold Cross Validation";

/*-----------------------------------------------------------------------
* Step 1 : Define macro parameters
*-----------------------------------------------------------------------*/

%let K = 5;
%let SEED = 20250506;

/*-----------------------------------------------------------------------
* Step 2 : Random fold assignment using PROC SURVEYSELECT
*-----------------------------------------------------------------------*/

proc surveyselect
    data=work.ML_Train_Final
    out=work.ML_KFold
    method=srs
    samprate=1
    seed=&SEED.
    n=&K.
    outall;

run;


/*-----------------------------------------------------------------------
* Step 3 : Assign fold IDs
*-----------------------------------------------------------------------*/

data work.ML_KFold;

    set work.ML_KFold;

    /*---------------------------------------------------------------
      PROC SURVEYSELECT with N=&K creates K systematic groups
      We assign Fold_ID using MOD logic for stability
    ---------------------------------------------------------------*/

    retain _counter 0;

    _counter + 1;

    Fold_ID = mod(_counter-1, &K.) + 1;

run;


/*-----------------------------------------------------------------------
* Step 4 : Verify fold distribution
*-----------------------------------------------------------------------*/

title3 "Fold Distribution Check";

proc freq
    data=work.ML_KFold;

    tables Fold_ID / missing;

run;


/*-----------------------------------------------------------------------
* Step 5 : Check exposure balance across folds
*-----------------------------------------------------------------------*/

title3 "Exposure Balance Across Folds";

proc means
    data=work.ML_KFold
    mean sum;

    class Fold_ID;

    var Exposure ClaimNb ClaimTotal;

run;


/*-----------------------------------------------------------------------
* Step 6 : Macro for fold-based training/validation split
*-----------------------------------------------------------------------*/

%macro cv_loop(dataset=work.ML_KFold, k=&K.);

    %do i = 1 %to &k.;

        data work.train_fold_&i
             work.valid_fold_&i;

            set &dataset.;

            if Fold_ID = &i. then output work.valid_fold_&i;
            else output work.train_fold_&i;

        run;

        %put NOTE: Fold &i created (train + validation);

    %end;

%mend;


/*-----------------------------------------------------------------------
* Step 7 : Execute CV macro
*-----------------------------------------------------------------------*/

%cv_loop(dataset=work.ML_KFold, k=&K.);


/*-----------------------------------------------------------------------
* Step 8 : Summary log
*-----------------------------------------------------------------------*/

data _null_;

    set work.ML_KFold end=eof;

    if eof then do;

        put "========================================================";
        put " K-FOLD CROSS VALIDATION CREATED";
        put "========================================================";
        put " Number of Folds : &K.";
        put " Dataset         : WORK.ML_KFOLD";
        put " Method          : Random fold assignment";
        put " Seed            : &SEED.";
        put "========================================================";
    end;

run;

title;
