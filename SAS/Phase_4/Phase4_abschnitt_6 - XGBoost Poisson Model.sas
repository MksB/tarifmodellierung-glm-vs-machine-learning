/*============================================================================*/
/* SECTION 6                                                                  */
/* XGBoost Poisson Model                                                      */
/* Corresponds to Python:                                                     */
/*   - fit_xgboost()                                                          */
/*   - get_gain_importance()                                                  */
/*============================================================================*/

%put NOTE: ============================================================;
%put NOTE: SECTION 6 - XGBOOST MODEL;
%put NOTE: ============================================================;

/*---------------------------------------------------------------------------
Prepare training and validation data

Equivalent to:

base_margin = log(Exposure)
---------------------------------------------------------------------------*/

data work.train_xgb;
    set work.train_data;
    LogExposure = log(Exposure);
run;

data work.test_xgb;
    set work.test_data;
    LogExposure = log(Exposure);
run;

/*---------------------------------------------------------------------------
Train XGBoost model

Python equivalent

objective            = count:poisson
max_depth            = 4
learning_rate        = 0.05
n_estimators         = 300
subsample            = 0.80
colsample_bytree     = 0.80
min_child_weight     = 20
reg_alpha            = 0.1
reg_lambda           = 1.0
early_stopping_rounds=30
---------------------------------------------------------------------------*/

proc xgboost
    data=work.train_xgb
    validdata=work.test_xgb
    seed=42;

    input
        VehPower
        VehAge
        DrivAge
        BonusMalus
        Density
        VehBrand
        VehGas
        Area
        Region
        LogDensity
        BonusMalusCapped;

    target ClaimNb;

    offset LogExposure;

    /* Booster parameters */
    booster gbtree;

    objective poisson;

    eta                 = 0.05;
    maxdepth            = 4;
    numround            = 300;

    subsample           = 0.80;
    colsamplebytree     = 0.80;

    minchildweight      = 20;

    alpha               = 0.10;
    lambda              = 1.00;

    earlystop = 30;

    importance
        out=work.XGB_FeatureImportance;

    savestate
        rstore=work.XGB_Model;

run;

/*---------------------------------------------------------------------------
Extract Gain Importance

Equivalent to:

model.get_booster().get_score(
    importance_type="gain"
)
---------------------------------------------------------------------------*/

data work.GainImportance;

    set work.XGB_FeatureImportance;

    length Feature $40;

    Feature = Variable;

    Gain = Importance;

    keep
        Feature
        Gain;

run;

/*---------------------------------------------------------------------------
Normalised Gain

Equivalent to

Gain_Norm = Gain / Gain.sum()
---------------------------------------------------------------------------*/

proc sql noprint;

    select sum(Gain)
    into :TOTAL_GAIN
    from work.GainImportance;

quit;

data work.GainImportance;

    set work.GainImportance;

    Gain_Norm = Gain / &TOTAL_GAIN;

run;

/*---------------------------------------------------------------------------
Sort descending
---------------------------------------------------------------------------*/

proc sort
    data=work.GainImportance;
    by descending Gain;
run;

/*---------------------------------------------------------------------------
Display feature importance
---------------------------------------------------------------------------*/

title "XGBoost Feature Importance (Gain)";

proc print
    data=work.GainImportance
    noobs
    label;

    var
        Feature
        Gain
        Gain_Norm;

    label
        Gain      = "Gain"
        Gain_Norm = "Normalized Gain";

run;

title;

/*---------------------------------------------------------------------------
Log information
---------------------------------------------------------------------------*/

proc sql noprint;

    select count(*)
    into :NFEATURES
    from work.GainImportance;

quit;

%put NOTE: ----------------------------------------------;
%put NOTE: XGBoost model successfully trained.;
%put NOTE: Feature importance calculated.;
%put NOTE: Number of active predictors = &NFEATURES;
%put NOTE: Model stored in WORK.XGB_Model;
%put NOTE: ----------------------------------------------;
