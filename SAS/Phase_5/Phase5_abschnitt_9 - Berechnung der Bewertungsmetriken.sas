/**************************************************************************
 * Projekt      : freMTPL Claim Frequency Modelling
 * Phase        : SHAP Phase 4 Analysis
 * Abschnitt    : 9 – Berechnung der Bewertungsmetriken
 *
 * Beschreibung
 * ------------
 * Berechnung von
 *
 *   • Poisson Deviance
 *   • RMSE
 *   • MAE
 *   • Gini
 *   • Laufzeit
 *
 **************************************************************************/

ods graphics off;


/***********************************************************************
* Laufzeit starten
***********************************************************************/

%let TIMER_START=%sysfunc(datetime());



/***********************************************************************
* Macro: RMSE
***********************************************************************/

%macro RMSE(data=,actual=,pred=,out=);

proc sql noprint;

select

sqrt(mean((&actual-&pred)**2))

into :RMSE

from &data;

quit;

data &out;

length Metric $40 Value 8;

Metric="RMSE";

Value=&RMSE;

run;

%mend;



/***********************************************************************
* Macro: MAE
***********************************************************************/

%macro MAE(data=,actual=,pred=,out=);

proc sql noprint;

select

mean(abs(&actual-&pred))

into :MAE

from &data;

quit;

data &out;

length Metric $40 Value 8;

Metric="MAE";

Value=&MAE;

run;

%mend;



/***********************************************************************
* Macro: Poisson Deviance
***********************************************************************/

%macro PoissonDeviance(data=,actual=,pred=,out=);

data _Poisson;

set &data;

length Dev 8;

if &actual=0 then

    Dev=2*&pred;

else

    Dev=2*
       (&actual*log(&actual/&pred) - (&actual-&pred));

run;

proc sql noprint;

select mean(Dev)

into :POISSON_DEV

from _Poisson;

quit;

data &out;

length Metric $40 Value 8;

Metric="Poisson Deviance";

Value=&POISSON_DEV;

run;

proc datasets library=work nolist;

delete _Poisson;

quit;

%mend;



/***********************************************************************
* Macro: Gini
***********************************************************************/

%macro Gini(data=,actual=,pred=,out=);

proc sort

data=&data

out=_GINI;

by descending &pred;

run;

data _GINI;

set _GINI;

retain

CumActual 0

CumObs 0;

CumObs+1;

CumActual+&actual;

run;

proc sql noprint;

select

sum(CumActual)

into :GINI_NUM

from _GINI;

select

sum(&actual)

into :GINI_DEN

from _GINI;

quit;

%let GINI=%sysevalf(2*&GINI_NUM/(&GINI_DEN*&SQLOBS)-1);

data &out;

length Metric $40 Value 8;

Metric="Normalized Gini";

Value=&GINI;

run;

proc datasets library=work nolist;

delete _GINI;

quit;

%mend;



/***********************************************************************
* Beispiel:
* GLM
***********************************************************************/

%RMSE(

data=work.GLM_FREQ_TEST_PRED,

actual=ClaimNb,

pred=PredictedClaimNb,

out=RMSE_GLM

);


%MAE(

data=work.GLM_FREQ_TEST_PRED,

actual=ClaimNb,

pred=PredictedClaimNb,

out=MAE_GLM

);


%PoissonDeviance(

data=work.GLM_FREQ_TEST_PRED,

actual=ClaimNb,

pred=PredictedClaimNb,

out=DEV_GLM

);


%Gini(

data=work.GLM_FREQ_TEST_PRED,

actual=ClaimNb,

pred=PredictedClaimNb,

out=GINI_GLM

);



/***********************************************************************
* Laufzeit
***********************************************************************/

%let TIMER_STOP=%sysfunc(datetime());

%let ELAPSED=%sysevalf(&TIMER_STOP-&TIMER_START);



data Runtime;

length Metric $40 Value 8;

Metric="Runtime (seconds)";

Value=&ELAPSED;

run;



/***********************************************************************
* Mastertabelle
***********************************************************************/

data

work.GLM_METRICS;

set

RMSE_GLM

MAE_GLM

DEV_GLM

GINI_GLM

Runtime;

run;



title "GLM Performance Metrics";

proc print
data=work.GLM_METRICS
noobs;
run;
