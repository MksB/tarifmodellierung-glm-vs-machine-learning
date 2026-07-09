/**************************************************************************
 * Projekt      : Tarifmodellierung MTPL
 * Phase        : Phase 5 – Performancevergleich & Abschlussbericht
 * Abschnitt    : 6 – Gamma-GLM (Severity)
 *
 * Beschreibung :
 * Schätzung eines Gamma-GLM zur Modellierung der
 * durchschnittlichen Schadenhöhe (AvgCost).
 *
 * Entspricht Python:
 *
 *     GammaRegressor(alpha=1.0)
 *
 * Zielvariable:
 *
 *     AvgCost = ClaimTotal / ClaimNb
 *
 * Gewichtung:
 *
 *     WEIGHT ClaimNb
 *
 * Verteilung:
 *
 *     Gamma
 *
 * Link:
 *
 *     Log
 *
 **************************************************************************/


/**************************************************************************
 * 1. ODS OUTPUT
 **************************************************************************/

ods output

    ParameterEstimates = work.GLM_SEV_PARAMETERS

    Type3              = work.GLM_SEV_TYPE3

    ModelFit           = work.GLM_SEV_MODELFIT

    ObStats            = work.GLM_SEV_OBS;


/**************************************************************************
 * 2. Gamma-GLM
 **************************************************************************/

proc genmod
    data = work.SEV_TRAIN;

    class

        VehBrand (ref=first)
        VehGas   (ref=first)
        Area     (ref=first)
        Region   (ref=first);

    model

        AvgCost =

            VehPower
            VehAge
            DrivAge
            BonusMalus
            VehBrand
            VehGas
            Area
            Density
            Region

        /

        dist  = gamma

        link  = log

        type3

        lrci;

    /**********************************************************************
     * Gewichtung
     *
     * Python:
     * sample_weight = ClaimNb
     **********************************************************************/

    weight ClaimNb;

    /**********************************************************************
     * Vorhersagen Trainingsdaten
     **********************************************************************/

    output

        out = work.GLM_SEV_TRAIN_PRED

        pred    = PredictedAvgCost

        resraw  = RawResidual

        reschi  = PearsonResidual

        resdev  = DevianceResidual

        xbeta   = LinearPredictor;

    /**********************************************************************
     * Modell speichern
     **********************************************************************/

    store out = work.GLM_SEV_MODEL;

run;

quit;


/**************************************************************************
 * 3. Testdatensatz scoren
 **************************************************************************/

proc plm
    restore = work.GLM_SEV_MODEL;

    score

        data = work.SEV_TEST

        out  = work.GLM_SEV_TEST_PRED

        predicted = PredictedAvgCost

        lclm

        uclm;

run;


/**************************************************************************
 * 4. Modellparameter
 **************************************************************************/

title3 "Gamma GLM - Parameterschätzungen";

proc print
    data = work.GLM_SEV_PARAMETERS
    noobs;
run;


/**************************************************************************
 * 5. Type-III-Tests
 **************************************************************************/

title3 "Gamma GLM - Type III Analyse";

proc print
    data = work.GLM_SEV_TYPE3
    noobs;
run;


/**************************************************************************
 * 6. Modellgüte
 **************************************************************************/

title3 "Gamma GLM - Modellgüte";

proc print
    data = work.GLM_SEV_MODELFIT
    noobs;
run;


/**************************************************************************
 * 7. Zusammenfassung der Vorhersagen
 **************************************************************************/

title3 "Vorhersagen - Testdatensatz";

proc means
    data = work.GLM_SEV_TEST_PRED
    n
    mean
    std
    min
    median
    max
    maxdec=4;

    var

        AvgCost
        PredictedAvgCost;

run;


/**************************************************************************
 * 8. Portfolio-Kalibrierung
 **************************************************************************/

proc sql;

create table
work.GLM_SEV_CALIBRATION as

select

    count(*)                               as N_Claims,

    sum(AvgCost)                           as ObservedCost,

    sum(PredictedAvgCost)                  as PredictedCost,

    mean(AvgCost)                          as MeanObserved,

    mean(PredictedAvgCost)                 as MeanPredicted,

    calculated PredictedCost /
    calculated ObservedCost                as CalibrationRatio

from

work.GLM_SEV_TEST_PRED;

quit;


title3 "Portfolio-Kalibrierung";

proc print
    data=work.GLM_SEV_CALIBRATION
    noobs;
run;


/**************************************************************************
 * 9. Residuenanalyse
 **************************************************************************/

title3 "Residuenanalyse";

proc means
    data = work.GLM_SEV_TRAIN_PRED
    n
    mean
    std
    min
    median
    max
    maxdec=4;

    var

        RawResidual
        PearsonResidual
        DevianceResidual;

run;


/**************************************************************************
 * 10. Log-Ausgabe
 **************************************************************************/

%put;
%put ==========================================================;
%put Gamma GLM erfolgreich geschätzt.;
%put;
%put Zielvariable : AvgCost;
%put Verteilung   : Gamma;
%put Link         : Log;
%put Gewichtung   : ClaimNb;
%put Trainingsdaten : work.SEV_TRAIN;
%put Testdaten      : work.SEV_TEST;
%put ==========================================================;
