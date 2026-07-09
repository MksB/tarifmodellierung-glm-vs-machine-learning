/**************************************************************************
 * Projekt      : freMTPL Claim Frequency Modelling
 * Phase        : SHAP Phase 4 Analysis
 * Abschnitt    : 11 – Master-Vergleichstabelle
 *
 * Beschreibung
 * ------------
 * Zusammenführung aller Modellmetriken in einer Vergleichstabelle.
 *
 * Modelle:
 *
 *   • Poisson GLM
 *   • Gradient Boosting (LightGBM-Ersatz)
 *   • Gradient Boosting (XGBoost-Ersatz)
 *
 **************************************************************************/

title;
footnote;


/**************************************************************************
 * 1. GLM
 **************************************************************************/

data work.GLM;

length Model $35;

set work.GLM_METRICS;

Model="Poisson GLM";

run;


/**************************************************************************
 * 2. Gradient Boosting
 **************************************************************************/

data work.GB;

length Model $35;

set work.GB_METRICS;

Model="Gradient Boosting";

run;


/**************************************************************************
 * 3. XGBoost-Ersatz
 **************************************************************************/

data work.XGB;

length Model $35;

set work.XGB_METRICS;

Model="Gradient Boosting (XGBoost)";

run;


/**************************************************************************
 * 4. Mastertabelle erzeugen
 **************************************************************************/

data work.ALL_METRICS;

set

work.GLM

work.GB

work.XGB;

run;


/**************************************************************************
 * 5. Long ? Wide
 **************************************************************************/

proc sql;

create table
work.MODEL_COMPARISON as

select

Model,

max(case when Metric="RMSE"
         then Value end)               as RMSE,

max(case when Metric="MAE"
         then Value end)               as MAE,

max(case when Metric="Poisson Deviance"
         then Value end)               as Poisson_Deviance,

max(case when Metric="Normalized Gini"
         then Value end)               as Gini,

max(case when Metric="Runtime (seconds)"
         then Value end)               as Runtime

from

work.ALL_METRICS

group by

Model

order by

RMSE;

quit;


/**************************************************************************
 * 6. Relative Verbesserung
 **************************************************************************/

proc sql noprint;

select RMSE

into :GLM_RMSE

from work.MODEL_COMPARISON

where Model="Poisson GLM";

quit;


data work.MODEL_COMPARISON;

set work.MODEL_COMPARISON;

RMSE_Improvement=

100*

((&GLM_RMSE-RMSE)

/&GLM_RMSE);

format

RMSE_Improvement

8.2;

run;


/**************************************************************************
 * 7. Ranking
 **************************************************************************/

proc rank

data=work.MODEL_COMPARISON

out=work.MODEL_COMPARISON

ties=low;

var

RMSE;

ranks

Rank;

run;

data work.MODEL_COMPARISON;

set work.MODEL_COMPARISON;

Rank+1;

run;


/**************************************************************************
 * 8. Ausgabe
 **************************************************************************/

title1 "Master Comparison Table";

proc report
data=work.MODEL_COMPARISON
nowd
headline
headskip
split="|";

column

Rank

Model

RMSE

MAE

Poisson_Deviance

Gini

Runtime

RMSE_Improvement;

define Rank
/display
"Rank";

define Model
/display
"Model";

define RMSE
/display
format=8.4;

define MAE
/display
format=8.4;

define Poisson_Deviance
/display
format=8.4;

define Gini
/display
format=8.4;

define Runtime
/display
format=8.2;

define RMSE_Improvement
/display
format=8.2
"% Improvement";

run;


/**************************************************************************
 * 9. Export
 **************************************************************************/

proc export

data=work.MODEL_COMPARISON

outfile="&OUTPUT_DIR./Model_Comparison.csv"

dbms=csv

replace;

run;


/**************************************************************************
 * 10. Log
 **************************************************************************/

%put;
%put ========================================================;
%put Master Comparison Table erfolgreich erstellt.;
%put;
%put Anzahl Modelle = 3;
%put Ausgabe = MODEL_COMPARISON;
%put Export  = Model_Comparison.csv;
%put ========================================================;
