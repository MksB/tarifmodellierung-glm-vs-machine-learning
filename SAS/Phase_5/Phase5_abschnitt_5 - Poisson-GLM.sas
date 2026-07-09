/**************************************************************************
 * Projekt      : Tarifmodellierung MTPL
 * Phase        : Phase 5 – Performancevergleich & Abschlussbericht
 * Abschnitt    : 5 – Poisson-GLM
 *
 * Beschreibung :
 * Schätzt ein klassisches aktuarielles Frequenzmodell
 * mittels PROC GENMOD.
 *
 * Modell:
 *
 *      ClaimNb ~ X
 *
 *      Verteilung : Poisson
 *      Link       : Log
 *      Offset     : LogExposure
 *
 * Entspricht Python:
 *
 *     PoissonRegressor()
 *
 * Unterschied:
 *
 * Python approximiert den Offset über sample_weight.
 *
 * SAS verwendet den mathematisch korrekten Offset:
 *
 *      OFFSET = LogExposure
 *
 **************************************************************************/


/**************************************************************************
 * 1. ODS-Ausgaben definieren
 **************************************************************************/

ods output

    ParameterEstimates = work.GLM_FREQ_PARAMETERS

    Type3              = work.GLM_FREQ_TYPE3

    ModelFit           = work.GLM_FREQ_MODELFIT

    FitStatistics      = work.GLM_FREQ_FIT

    ObStats            = work.GLM_FREQ_PREDICT;


/**************************************************************************
 * 2. Poisson-GLM schätzen
 **************************************************************************/

proc genmod
    data = work.FREQ_TRAIN;

    /**********************************************************************
     * Kategoriale Variablen
     *
     * REF=FIRST
     * entspricht der Standardkodierung von R.
     **********************************************************************/

    class

        VehBrand   (ref=first)

        VehGas     (ref=first)

        Area       (ref=first)

        Region     (ref=first);

    /**********************************************************************
     * Modell
     **********************************************************************/

    model

        ClaimNb =

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

        dist   = poisson

        link   = log

        offset = LogExposure

        type3

        lrci;

    /**********************************************************************
     * Prognosen erzeugen
     **********************************************************************/

    output

        out = work.GLM_FREQ_TRAIN_PRED

        pred     = PredictedClaimNb

        resraw   = RawResidual

        reschi   = PearsonResidual

        resdev   = DevianceResidual

        xbeta    = LinearPredictor;

run;

quit;


/**************************************************************************
 * 3. Prognosen auf Testdatensatz
 **************************************************************************/

proc plm
    restore = work._LAST_;
run;


/**************************************************************************
 * Alternative:
 * PROC GENMOD SCORE existiert nicht.
 *
 * Deshalb wird das Modell über STORE wiederverwendet.
 **************************************************************************/

proc genmod
    data = work.FREQ_TRAIN;

    class

        VehBrand(ref=first)

        VehGas(ref=first)

        Area(ref=first)

        Region(ref=first);

    model

        ClaimNb =

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

        dist=poisson
        link=log
        offset=LogExposure;

    store out=work.GLM_FREQ_MODEL;

run;

quit;


/**************************************************************************
 * 4. Score Testdatensatz
 **************************************************************************/

proc plm
    restore=work.GLM_FREQ_MODEL;

    score

        data=work.FREQ_TEST

        out=work.GLM_FREQ_TEST_PRED

        predicted=PredictedClaimNb

        lclm

        uclm;

run;


/**************************************************************************
 * 5. Modellgüte
 **************************************************************************/

title3 "Poisson GLM - Modellgüte";

proc print
    data=work.GLM_FREQ_FIT;
run;


title3 "Poisson GLM - Parameter";

proc print
    data=work.GLM_FREQ_PARAMETERS;
run;


title3 "Likelihood-Ratio Type III";

proc print
    data=work.GLM_FREQ_TYPE3;
run;


/**************************************************************************
 * 6. Vorhersageübersicht
 **************************************************************************/

proc means

    data=work.GLM_FREQ_TEST_PRED

    n

    mean

    std

    min

    median

    max

    maxdec=6;

    var

        PredictedClaimNb;

run;


/**************************************************************************
 * 7. Portfolio-Balance
 *
 * Für ein korrekt spezifiziertes Poisson-GLM gilt näherungsweise:
 *
 *      Sum(Predicted)
 *          ˜
 *      Sum(Observed)
 *
 **************************************************************************/

proc sql;

create table
work.GLM_FREQ_BALANCE as

select

    sum(ClaimNb)              as ObservedClaims,

    sum(PredictedClaimNb)     as PredictedClaims,

    calculated PredictedClaims /
    calculated ObservedClaims as BalanceRatio

from

work.GLM_FREQ_TEST_PRED;

quit;


title3 "Portfolio Balance";

proc print
    data=work.GLM_FREQ_BALANCE;
run;


/**************************************************************************
 * 8. Log-Ausgabe
 **************************************************************************/

%put;
%put ========================================================;
%put Poisson GLM erfolgreich geschätzt.;
%put;
%put Verteilung : Poisson;
%put Link       : Log;
%put Offset     : LogExposure;
%put Trainingsdaten : work.FREQ_TRAIN;
%put Testdaten      : work.FREQ_TEST;
%put ========================================================;
