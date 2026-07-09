/**************************************************************************
 * Projekt      : Tarifmodellierung MTPL
 * Phase        : Phase 5 – Performancevergleich & Abschlussbericht
 * Abschnitt    : 2 – Datenimport
 *
 * Beschreibung :
 * Einlesen des MTPL-Datensatzes aus einer CSV-Datei.
 * Anschließende Plausibilitätsprüfung der importierten Daten.
 *
 * Entspricht Python:
 *
 * df = pd.read_csv(DATA_PATH, index_col=0)
 *
 **************************************************************************/


/**************************************************************************
 * 1. CSV-Datei importieren
 **************************************************************************/

proc import
    datafile="&DATA_DIR.\&DATASET."
    out=work.MTPL_RAW
    dbms=csv
    replace;
    guessingrows=max;
    getnames=yes;
run;


/**************************************************************************
 * 2. Optional: Erste Spalte entfernen
 *
 * Python verwendet:
 *     index_col = 0
 *
 * Beim CSV-Import wird diese Indexspalte häufig als VAR1 importiert.
 * Falls vorhanden und nicht benötigt, wird sie gelöscht.
 **************************************************************************/

data work.MTPL_RAW;

    set work.data;

run;


/**************************************************************************
 * 3. Datensatzinformationen
 **************************************************************************/

title3 "Datensatzinformationen";

proc contents
    data=work.MTPL_RAW
    varnum;
run;


/**************************************************************************
 * 4. Anzahl Beobachtungen und Variablen
 **************************************************************************/

proc sql noprint;

    select
        count(*)
    into :NOBS trimmed
    from work.MTPL_RAW;

quit;

%let NVAR=%sysfunc(attrn(%sysfunc(open(work.MTPL_RAW)),NVARS));

%put NOTE: ----------------------------------------------;
%put NOTE: Beobachtungen = &NOBS.;
%put NOTE: Variablen     = &NVAR.;
%put NOTE: ----------------------------------------------;


/**************************************************************************
 * 5. Erste Beobachtungen anzeigen
 **************************************************************************/

title3 "Erste Beobachtungen";

proc print
    data=work.MTPL_RAW(obs=10);
run;


/**************************************************************************
 * 6. Fehlende Werte prüfen
 **************************************************************************/

title3 "Fehlende numerische Werte";

proc means
    data=work.MTPL_RAW
    n
    nmiss;
run;


/**************************************************************************
 * 7. Kategoriale Variablen prüfen
 **************************************************************************/

title3 "Kategoriale Variablen";

proc freq
    data=work.MTPL_RAW;

    tables
        VehBrand
        VehGas
        Area
        Region
        / missing;

run;


/**************************************************************************
 * 8. Numerische Variablen prüfen
 **************************************************************************/

title3 "Numerische Variablen";

proc means
    data=work.MTPL_RAW
    n
    mean
    std
    min
    p25
    median
    p75
    max
    maxdec=2;

    var
        Exposure
        ClaimNb
        ClaimTotal
        VehPower
        VehAge
        DrivAge
        BonusMalus
        Density;

run;


/**************************************************************************
 * 9. Datensatz validieren
 **************************************************************************/

%macro ValidateImport();

    %if &NOBS.=0 %then %do;

        %put ERROR: =====================================================;
        %put ERROR: Der Datensatz wurde nicht erfolgreich importiert.;
        %put ERROR: =====================================================;

        %abort cancel;

    %end;

    %else %do;

        %put NOTE: =====================================================;
        %put NOTE: CSV-Datei erfolgreich importiert.;
        %put NOTE: Datensatz = work.MTPL_RAW;
        %put NOTE: Beobachtungen = &NOBS.;
        %put NOTE: =====================================================;

    %end;

%mend;

%ValidateImport();
