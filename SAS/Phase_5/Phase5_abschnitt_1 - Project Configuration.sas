/**************************************************************************
 * Projekt      : Tarifmodellierung MTPL
 * Phase        : Phase 5 – Performancevergleich & Abschlussbericht
 * Abschnitt    : 1 – Projektkonfiguration
 *
 * Beschreibung :
 * Initialisierung der SAS-Umgebung.
 * Definiert Makrovariablen, globale Optionen, ODS-Ausgabe,
 * Zufallsseed und Projektpfade.
 *
 * Entspricht Python:
 * ----------------------------------------
 * import ...
 * RANDOM_SEED = 42
 * TEST_SIZE   = 0.20
 * DATA_PATH
 * PLOT_DIR
 *************************************************************************/


/**************************************************************************
 * 1. SAS-Optionen
 **************************************************************************/

options
        nocenter
        validvarname=v7
        mprint
        mlogic
        symbolgen
        msglevel=i
        compress=yes
        fullstimer;


/**************************************************************************
 * 2. Projektpfade
 *
 * Bitte den Root-Pfad anpassen.
 **************************************************************************/

%let PROJECT_ROOT =
C:\MTPL_Project;

%let DATA_DIR   = &PROJECT_ROOT.\data;
%let OUTPUT_DIR = &PROJECT_ROOT.\output;
%let PLOT_DIR   = &OUTPUT_DIR.\plots;


/**************************************************************************
 * 3. Dateinamen
 **************************************************************************/

%let DATASET = freMTPLfreq_sev_data_1000.csv;


/**************************************************************************
 * 4. Modellparameter
 **************************************************************************/

%let RANDOM_SEED = 42;

%let TEST_SIZE = 0.20;


/**************************************************************************
 * 5. Numerische Konstanten
 **************************************************************************/

%let EXPOSURE_MIN = 1E-6;
%let EXPOSURE_MAX = 1;

%let BONUSMALUS_MIN = 50;
%let BONUSMALUS_MAX = 350;


/**************************************************************************
 * 6. Bibliotheken
 **************************************************************************/

libname MTPLDATA "&DATA_DIR.";

libname MTPLOUT "&OUTPUT_DIR.";


/**************************************************************************
 * 7. ODS-Ausgabe
 *
 * Analog zum Python-Ausgabeverzeichnis "plots".
 **************************************************************************/

ods graphics on
    / reset
      imagename="MTPL"
      imagefmt=png
      noborder;

ods listing gpath="&PLOT_DIR.";

ods html
    path="&OUTPUT_DIR."
    file="Phase5_Report.html"
    style=HTMLBlue;


/**************************************************************************
 * 8. Titel und Fußzeile
 **************************************************************************/

title1 "Tarifmodellierung: GLM vs Machine Learning";
title2 "Phase 5 - Performancevergleich";
title3 "French MTPL Portfolio";

footnote1
"Automatisch erzeugt mit SAS";


/**************************************************************************
 * 9. Startzeit des Projektes
 *
 * Wird später zur Laufzeitmessung verwendet.
 **************************************************************************/

%let START_TIME = %sysfunc(datetime());

%put NOTE: ==============================================;
%put NOTE: Phase 5 gestartet.;
%put NOTE: Startzeit = %sysfunc(datetime(),datetime20.);
%put NOTE: ==============================================;


/**************************************************************************
 * 10. Versionsinformationen
 **************************************************************************/

%put;
%put NOTE: ----------------------------------------------;
%put NOTE: SAS Version      = &sysvlong4;
%put NOTE: Betriebssystem   = &sysscpl;
%put NOTE: Benutzer         = &sysuserid;
%put NOTE: Rechner          = &syshostname;
%put NOTE: ----------------------------------------------;


/**************************************************************************
 * 11. Prüfen der Projektordner
 **************************************************************************/

%macro CheckDirectory(path);

    %if %sysfunc(fileexist(&path.)) %then
        %put NOTE: Verzeichnis vorhanden -> &path.;
    %else
        %put WARNING: Verzeichnis NICHT gefunden -> &path.;

%mend;

%CheckDirectory("&DATA_DIR.");
%CheckDirectory("&OUTPUT_DIR.");
%CheckDirectory("&PLOT_DIR.");


/**************************************************************************
 * 12. Übersicht der Projektparameter
 **************************************************************************/

%put;
%put =====================================================;
%put Projektkonfiguration;
%put =====================================================;
%put Datensatz           = &DATASET.;
%put Datenverzeichnis    = &DATA_DIR.;
%put Output              = &OUTPUT_DIR.;
%put Plotverzeichnis     = &PLOT_DIR.;
%put Random Seed         = &RANDOM_SEED.;
%put Testanteil          = &TEST_SIZE.;
%put Exposure Minimum    = &EXPOSURE_MIN.;
%put Exposure Maximum    = &EXPOSURE_MAX.;
%put BonusMalus Minimum  = &BONUSMALUS_MIN.;
%put BonusMalus Maximum  = &BONUSMALUS_MAX.;
%put =====================================================;
