/**************************************************************************
 * Projekt      : Tarifmodellierung MTPL
 * Phase        : Phase 5 – Performancevergleich & Abschlussbericht
 * Abschnitt    : 3 – Feature Engineering
 *
 * Beschreibung :
 * Aufbereitung des importierten MTPL-Datensatzes für die Modellierung.
 *
 * Entspricht Python:
 *     load_and_prepare()
 *
 * Durchgeführte Schritte:
 *   1. Exposure-Clipping
 *   2. Berechnung LogExposure
 *   3. Berechnung AvgCost
 *   4. Berechnung Frequency
 *   5. Winsorisierung BonusMalus
 *
 * Hinweis:
 * Das Label-Encoding der kategorialen Variablen erfolgt in SAS NICHT,
 * da PROC GENMOD die CLASS-Anweisung verwendet.
 **************************************************************************/


/**************************************************************************
 * 1. Feature Engineering
 **************************************************************************/

data work.MTPL_PREPARED;

    set work.MTPL_RAW;

    /**********************************************************************
     * Exposure-Clipping
     *
     * Python:
     * df["Exposure"] = df["Exposure"].clip(1E-6,1)
     **********************************************************************/

    if missing(Exposure) then Exposure = .;
    else do;

        if Exposure < &EXPOSURE_MIN then
            Exposure = &EXPOSURE_MIN;

        else if Exposure > &EXPOSURE_MAX then
            Exposure = &EXPOSURE_MAX;

    end;


    /**********************************************************************
     * LogExposure
     *
     * Python:
     * np.log(Exposure)
     **********************************************************************/

    if Exposure > 0 then
        LogExposure = log(Exposure);
    else
        LogExposure = .;


    /**********************************************************************
     * Durchschnittliche Schadenhöhe
     *
     * Python:
     * AvgCost = ClaimTotal / ClaimNb
     **********************************************************************/

    if ClaimNb > 0 then
        AvgCost = ClaimTotal / ClaimNb;
    else
        AvgCost = .;


    /**********************************************************************
     * Schadenfrequenz
     *
     * Python:
     * Frequency = ClaimNb / Exposure
     **********************************************************************/

    if Exposure > 0 then
        Frequency = ClaimNb / Exposure;
    else
        Frequency = .;


    /**********************************************************************
     * Winsorisierung BonusMalus
     *
     * Python:
     * clip(50,350)
     **********************************************************************/

    if not missing(BonusMalus) then do;

        if BonusMalus < &BONUSMALUS_MIN then
            BonusMalus = &BONUSMALUS_MIN;

        else if BonusMalus > &BONUSMALUS_MAX then
            BonusMalus = &BONUSMALUS_MAX;

    end;

run;


/**************************************************************************
 * 2. Datensatz prüfen
 **************************************************************************/

title3 "Feature Engineering - Übersicht";

proc contents
    data=work.MTPL_PREPARED
    varnum;
run;


/**************************************************************************
 * 3. Neue Variablen prüfen
 **************************************************************************/

title3 "Neue Features";

proc means
    data=work.MTPL_PREPARED
    n
    nmiss
    mean
    std
    min
    median
    max
    maxdec=4;

    var
        Exposure
        LogExposure
        AvgCost
        Frequency
        BonusMalus;

run;


/**************************************************************************
 * 4. Schadenrate berechnen
 *
 * Python:
 * (ClaimNb > 0).mean()
 **************************************************************************/

proc sql noprint;

    select
        mean(case when ClaimNb > 0 then 1 else 0 end)
    into :CLAIM_RATE
    from work.MTPL_PREPARED;

quit;

%let CLAIM_RATE=%sysevalf(&CLAIM_RATE*100);


/**************************************************************************
 * 5. Log-Ausgabe
 **************************************************************************/

%put;
%put ========================================================;
%put Feature Engineering abgeschlossen.;
%put;
%put Datensatz : work.MTPL_PREPARED;
%put Schadenrate = %sysfunc(round(&CLAIM_RATE,0.01)) %%;
%put ========================================================;


/**************************************************************************
 * 6. Plausibilitätsprüfung
 **************************************************************************/

title3 "Plausibilitätsprüfung";

proc print
    data=work.MTPL_PREPARED(obs=10);

    var
        Exposure
        LogExposure
        ClaimNb
        ClaimTotal
        AvgCost
        Frequency
        BonusMalus;

run;
