/**************************************************************************
 * Projekt      : freMTPL Claim Frequency Modelling
 * Phase        : SHAP Phase 4 Analysis
 * Abschnitt    : 8 - Gradient Boosting (XGBoost-Ersatz)
 *
 * SAS-Version  : SAS Viya
 *
 * Beschreibung:
 * Gradient Boosting als funktionaler Ersatz für XGBoost.
 *
 * Zielvariable:
 *     Frequency = ClaimNb / Exposure
 *
 * Vorhersage:
 *     PredictedClaimNb = PredictedFrequency * Exposure
 *
 **************************************************************************/


/**************************************************************************
 * ODS OUTPUT
 **************************************************************************/

ods graphics on;

ods output
    FitStatistics      = work.XGB_FITSTAT
    VariableImportance = work.XGB_IMPORTANCE;


/**************************************************************************
 * Gradient Boosting Modell
 **************************************************************************/

proc gradboost
    data=work.FREQ_TRAIN
    seed=&RANDOM_SEED;

    /* Numerische Variablen */

    input
        VehPower
        VehAge
        DrivAge
        BonusMalus
        Density
    / level=interval;

    /* Kategoriale Variablen */

    input
        VehBrand
        VehGas
        Area
        Region
    / level=nominal;

    /* Zielvariable */

    target Frequency / level=interval;

    /* Exposure-Gewichtung */

    weight Exposure;

    /* ---------------------------------------------------------------
       Parameter ähnlich XGBoost
       --------------------------------------------------------------- */

    ntrees          = 1000

    learningrate    = 0.05

    samplingrate    = 0.80

    maxdepth        = 6

    minleafsize     = 10

    assignmissing=useinsearch

    maxbranch       = 2

    leafsize        = 5

    lasso           = 0

    ridge           = 1e-6;

    savestate
        rstore=work.XGB_MODEL;

run;

quit;


/**************************************************************************
 * Testdatensatz scoren
 **************************************************************************/

proc astore;

    score
        data   = work.FREQ_TEST
        rstore = work.XGB_MODEL
        out    = work.XGB_SCORE;

run;


/**************************************************************************
 * Schadenanzahl berechnen
 **************************************************************************/

data work.XGB_SCORE;

    set work.XGB_SCORE;

    PredictedFrequency = P_Frequency;

    PredictedClaimNb = PredictedFrequency * Exposure;

run;


/**************************************************************************
 * Modellgüte
 **************************************************************************/

title "Gradient Boosting - Fit Statistics";

proc print
    data=work.XGB_FITSTAT
    noobs;
run;


/**************************************************************************
 * Variable Importance
 **************************************************************************/

proc sort
    data=work.XGB_IMPORTANCE;
    by descending Importance;
run;

title "Variable Importance";

proc print
    data=work.XGB_IMPORTANCE
    noobs;
run;


/**************************************************************************
 * Portfoliovergleich
 **************************************************************************/

proc sql;

create table work.XGB_PORTFOLIO as

select

    count(*)                        as Policies,

    sum(ClaimNb)                    as ObservedClaims,

    sum(PredictedClaimNb)           as PredictedClaims,

    mean(Frequency)                 as MeanObservedFrequency,

    mean(PredictedFrequency)        as MeanPredictedFrequency,

    calculated PredictedClaims /
    calculated ObservedClaims       as CalibrationRatio

from work.XGB_SCORE;

quit;


/**************************************************************************
 * Übersicht der Vorhersagen
 **************************************************************************/

proc means
    data=work.XGB_SCORE
    n
    mean
    std
    min
    median
    max
    maxdec=6;

    var

        Frequency

        PredictedFrequency

        ClaimNb

        PredictedClaimNb;

run;


/**************************************************************************
 * Log
 **************************************************************************/

%put;
%put ==========================================================;
%put Gradient Boosting (XGBoost-Ersatz) erfolgreich trainiert.;
%put;
%put Verfahren          : PROC GRADBOOST;
%put Anzahl Baeume      : 1000;
%put Learning Rate      : 0.05;
%put Maximale Tiefe     : 6;
%put Sampling Rate      : 0.80;
%put Zielvariable       : Frequency;
%put Trainingsdaten     : work.FREQ_TRAIN;
%put Testdaten          : work.FREQ_TEST;
%put ==========================================================;

ods graphics off;
