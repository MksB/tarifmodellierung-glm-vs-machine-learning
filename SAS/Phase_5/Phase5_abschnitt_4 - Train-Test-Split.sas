/**************************************************************************
 * Projekt      : Tarifmodellierung MTPL
 * Phase        : Phase 5 – Performancevergleich & Abschlussbericht
 * Abschnitt    : 4 – Train-/Test-Split
 *
 * Beschreibung :
 * Erzeugt reproduzierbare Trainings- und Testdatensätze
 * für Frequenz- und Schwerenmodell.
 *
 * Entspricht Python:
 *
 * train_test_split(
 *      test_size = 0.20,
 *      random_state = 42
 * )
 *
 * Frequenzmodell:
 *      Alle Policen
 *
 * Schwerenmodell:
 *      Nur Beobachtungen mit ClaimNb > 0
 **************************************************************************/


/**************************************************************************
 * 1. Frequenzdatensatz
 **************************************************************************/

data WORK.FREQUENCY_DATA;

    set work.MTPL_PREPARED;

run;


/**************************************************************************
 * 2. Train-/Test-Split Frequenzmodell
 **************************************************************************/

proc surveyselect
    data=WORK.FREQUENCY_DATA
    out=WORK.FREQ_SPLIT
    seed=&RANDOM_SEED
    samprate=%sysevalf(1-&TEST_SIZE)
    outall
    method=SRS;
run;


/**************************************************************************
 * 3. Trainings- und Testdaten erzeugen
 **************************************************************************/

data
    work.FREQ_TRAIN
    work.FREQ_TEST;

    set WORK.FREQ_SPLIT;

    if Selected then
        output work.FREQ_TRAIN;
    else
        output work.FREQ_TEST;

run;


/**************************************************************************
 * 4. Schwerendatensatz erzeugen
 **************************************************************************/

data WORK.SEVERITY_DATA;

    set work.MTPL_PREPARED;

    where ClaimNb > 0;

run;


/**************************************************************************
 * 5. Train-/Test-Split Schwerenmodell
 **************************************************************************/

proc surveyselect
    data=WORK.SEVERITY_DATA
    out=WORK.SEV_SPLIT
    seed=&RANDOM_SEED
    samprate=%sysevalf(1-&TEST_SIZE)
    outall
    method=SRS;
run;


/**************************************************************************
 * 6. Trainings- und Testdaten erzeugen
 **************************************************************************/

data
    work.SEV_TRAIN
    work.SEV_TEST;

    set WORK.SEV_SPLIT;

    if Selected then
        output work.SEV_TRAIN;
    else
        output work.SEV_TEST;

run;


/**************************************************************************
 * 7. Datensatzgrößen bestimmen
 **************************************************************************/

proc sql noprint;

    select count(*)
    into :N_FREQ_TRAIN
    from work.FREQ_TRAIN;

    select count(*)
    into :N_FREQ_TEST
    from work.FREQ_TEST;

    select count(*)
    into :N_SEV_TRAIN
    from work.SEV_TRAIN;

    select count(*)
    into :N_SEV_TEST
    from work.SEV_TEST;

quit;


/**************************************************************************
 * 8. Übersicht
 **************************************************************************/

%put;
%put =====================================================;
%put Train-/Test-Split abgeschlossen;
%put =====================================================;
%put;
%put Frequenzmodell:;
%put Training = &N_FREQ_TRAIN.;
%put Test     = &N_FREQ_TEST.;
%put;
%put Schwerenmodell:;
%put Training = &N_SEV_TRAIN.;
%put Test     = &N_SEV_TEST.;
%put =====================================================;


/**************************************************************************
 * 9. Plausibilitätsprüfung
 **************************************************************************/

title3 "Train-/Test-Split Frequenzmodell";

proc freq data=WORK.FREQ_SPLIT;

    tables Selected / nocum;

run;


title3 "Train-/Test-Split Schwerenmodell";

proc freq data=WORK.SEV_SPLIT;

    tables Selected / nocum;

run;


/**************************************************************************
 * 10. Aufräumen
 **************************************************************************/

proc datasets library=WORK nolist;

    delete
        FREQUENCY_DATA
        SEVERITY_DATA
        FREQ_SPLIT
        SEV_SPLIT;

quit;
