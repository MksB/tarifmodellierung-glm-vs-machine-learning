/**************************************************************************
 * Projekt      : Tarifmodellierung MTPL
 * Phase        : SHAP Phase 4 – Claim Frequency Modelling
 * Abschnitt    : 7 – Gradient Boosting (LightGBM-Ersatz)
 *
 * SAS-Version  : SAS Viya
 *
 * Beschreibung
 * ------------
 * Ersatz für das Python-LightGBM-Modell mittels PROC GRADBOOST.
 *
 * Zielvariable:
 *
 *      Frequency = ClaimNb / Exposure
 *
 * Nach der Vorhersage:
 *
 *      PredictedClaimNb =
 *              PredictedFrequency * Exposure
 *
 **************************************************************************/


/**************************************************************************
 * 1. ODS OUTPUT
 **************************************************************************/

ods output

    FitStatistics      = work.GB_FREQ_FIT

    VariableImportance = work.GB_FREQ_IMPORTANCE;


/**************************************************************************
 * 2. Gradient Boosting
 **************************************************************************/

proc gradboost
    data = work.FREQ_TRAIN
    seed = &RANDOM_SEED;

    input

        VehPower
        VehAge
        DrivAge
        BonusMalus
        Density

        /

        level=interval;

    input

        VehBrand
        VehGas
        Area
        Region

        /

        level=nominal;

    target Frequency
        / level=interval;

    weight Exposure;

    autotune no;

    ntrees           = 500

    learningrate     = 0.05

    maxdepth         = 6

    minleafsize      = 20

    samplingrate     = 0.80;

    savestate
        rstore=work.GB_FREQ_MODEL;

run;

quit;


/**************************************************************************
 * 3. Testdatensatz scoren
 **************************************************************************/

proc astore;

    score

        data  = work.FREQ_TEST

        rstore=work.GB_FREQ_MODEL

        out   = work.GB_FREQ_TEST;

run;


/**************************************************************************
 * 4. Schadenanzahl berechnen
 **************************************************************************/

data work.GB_FREQ_TEST;

    set work.GB_FREQ_TEST;

    PredictedFrequency = P_Frequency;

    PredictedClaimNb =
        PredictedFrequency * Exposure;

run;


/**************************************************************************
 * 5. Variable Importance
 **************************************************************************/

title3 "Gradient Boosting - Variable Importance";

proc sort
    data=work.GB_FREQ_IMPORTANCE;
    by descending Importance;
run;

proc print
    data=work.GB_FREQ_IMPORTANCE
    noobs;
run;


/**************************************************************************
 * 6. Modellgüte
 **************************************************************************/

title3 "Gradient Boosting - Fit Statistics";

proc print
    data=work.GB_FREQ_FIT
    noobs;
run;


/**************************************************************************
 * 7. Vorhersageübersicht
 **************************************************************************/

proc means
    data=work.GB_FREQ_TEST
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
 * 8. Portfolio-Kalibrierung
 **************************************************************************/

proc sql;

create table
work.GB_FREQ_CALIBRATION as

select

    sum(ClaimNb) as ObservedClaims,

    sum(PredictedClaimNb) as PredictedClaims,

    calculated PredictedClaims /
    calculated ObservedClaims as CalibrationRatio

from work.GB_FREQ_TEST;

quit;


title3 "Gradient Boosting - Portfolio Calibration";

proc print
    data=work.GB_FREQ_CALIBRATION;
run;


/**************************************************************************
 * 9. Log
 **************************************************************************/

%put;
%put =========================================================;
%put Gradient Boosting erfolgreich trainiert.;
%put;
%put Verfahren      : PROC GRADBOOST;
%put Ersatz fuer    : Python LightGBM;
%put Zielvariable   : Frequency;
%put Baeume         : 500;
%put Learning Rate  : 0.05;
%put Maximale Tiefe : 6;
%put =========================================================;
