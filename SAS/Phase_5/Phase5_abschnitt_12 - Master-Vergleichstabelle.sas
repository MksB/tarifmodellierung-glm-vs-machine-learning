/**************************************************************************
* Projekt      : freMTPL Claim Frequency Modelling
* Phase        : SHAP Phase 4 Analysis
* Abschnitt    : 12 – Abschlussbericht und Export
*
* Beschreibung:
*   • Export der Vergleichstabelle
*   • Erstellung eines HTML-Berichts
*   • Erstellung eines PDF-Berichts
*   • Projektzusammenfassung
*
**************************************************************************/

title;
footnote;

ods graphics on;


/**************************************************************************
* 1. Export Vergleichstabelle
**************************************************************************/

proc export
    data=work.MODEL_COMPARISON
    outfile="&OUTPUT_DIR./Model_Comparison.csv"
    dbms=csv
    replace;
run;


/**************************************************************************
* 2. HTML-Bericht
**************************************************************************/

ods html5
    path="&OUTPUT_DIR."
    file="Claim_Frequency_Report.html"
    style=HTMLBlue;

title1 "Claim Frequency Modelling";
title2 "Abschlussbericht";

proc report
    data=work.MODEL_COMPARISON
    nowd
    headline
    headskip;
run;


/* GLM */

title2 "Poisson GLM";

proc print
    data=work.GLM_FREQ_PARAMETERS
    noobs;
run;


/* Gradient Boosting */

title2 "Gradient Boosting";

proc print
    data=work.GB_FREQ_IMPORTANCE
    noobs;
run;


/* XGBoost */

title2 "Gradient Boosting (XGBoost-Ersatz)";

proc print
    data=work.XGB_IMPORTANCE
    noobs;
run;


/* Grafiken */

title2 "Beobachtet vs. Prognostiziert";

proc sgplot
    data=work.GLM_FREQ_TEST_PRED;

    scatter
        x=ClaimNb
        y=PredictedClaimNb;

    lineparm
        x=0
        y=0
        slope=1;

run;

ods html5 close;


/**************************************************************************
* 3. PDF-Bericht
**************************************************************************/

ods pdf
    file="&OUTPUT_DIR./Claim_Frequency_Report.pdf"
    style=Journal;

title1 "Claim Frequency Modelling";
title2 "Final Report";

proc report
    data=work.MODEL_COMPARISON
    nowd;
run;

title2 "GLM Parameter";

proc print
    data=work.GLM_FREQ_PARAMETERS;
run;

title2 "Variable Importance";

proc print
    data=work.GB_FREQ_IMPORTANCE;
run;

title2 "XGBoost Variable Importance";

proc print
    data=work.XGB_IMPORTANCE;
run;

title2 "Prediction";

proc sgplot
    data=work.GLM_FREQ_TEST_PRED;

    scatter
        x=ClaimNb
        y=PredictedClaimNb;

    lineparm
        x=0
        y=0
        slope=1;

run;

ods pdf close;


/**************************************************************************
* 4. Projektergebnis
**************************************************************************/

proc sql noprint;

select

Model

into :BESTMODEL

from work.MODEL_COMPARISON

having RMSE=min(RMSE);

quit;


/**************************************************************************
* 5. Laufzeit
**************************************************************************/

%let PROJECT_END=%sysfunc(datetime());

%let PROJECT_RUNTIME=
%sysevalf((&PROJECT_END-&START_TIME));


/**************************************************************************
* 6. Zusammenfassung
**************************************************************************/

data work.PROJECT_SUMMARY;

length
Project $60
BestModel $40;

Project="freMTPL Claim Frequency Modelling";

BestModel="&BESTMODEL";

Runtime=&PROJECT_RUNTIME;

RunDate=datetime();

format

RunDate datetime20.

Runtime 8.2;

run;


/**************************************************************************
* 7. Ausgabe
**************************************************************************/

title "Projektzusammenfassung";

proc print
    data=work.PROJECT_SUMMARY
    noobs;
run;


/**************************************************************************
* 8. Export Projektzusammenfassung
**************************************************************************/

proc export
    data=work.PROJECT_SUMMARY
    outfile="&OUTPUT_DIR./Project_Summary.csv"
    dbms=csv
    replace;
run;


/**************************************************************************
* 9. LOG
**************************************************************************/

%put;
%put ===========================================================;
%put Claim Frequency Modelling erfolgreich abgeschlossen.;
%put;
%put Bestes Modell      = &BESTMODEL;
%put Gesamtlaufzeit     = &PROJECT_RUNTIME Sekunden;
%put;
%put Exportierte Dateien:;
%put   Model_Comparison.csv;
%put   Project_Summary.csv;
%put   Claim_Frequency_Report.html;
%put   Claim_Frequency_Report.pdf;
%put ===========================================================;

ods graphics off;
