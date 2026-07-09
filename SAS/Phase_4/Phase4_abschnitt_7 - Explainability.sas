/**************************************************************************
SECTION 7
Explainability
Approximation of Python SHAP Analysis for SAS 9.4
**************************************************************************/

title;
footnote;

/***********************************************************************
Create Variable Importance Dataset
***********************************************************************/

ods graphics on;

ods output VariableImportance=work.var_importance;

proc gradboost
    inmodel=gb_model;
    importance;
run;

ods output close;


/***********************************************************************
Normalise Importance
***********************************************************************/

proc sql noprint;
select sum(Importance)
into :TOTAL_IMP
from work.var_importance;
quit;

data work.shap_importance;

set work.var_importance;

MeanAbsSHAP = Importance / &TOTAL_IMP.;

label
MeanAbsSHAP="Normalized Importance";

run;


/***********************************************************************
Sort descending
***********************************************************************/

proc sort
data=work.shap_importance;
by descending MeanAbsSHAP;
run;


/***********************************************************************
Top 15 Variables
***********************************************************************/

data work.top15;

set work.shap_importance(obs=15);

Rank=_N_;

run;


/**************************************************************************
Beeswarm Approximation
**************************************************************************/

ods graphics / width=1100px height=700px;

proc sgplot data=work.top15;

scatter
    x=MeanAbsSHAP
    y=Rank
/
markerattrs=(symbol=circlefilled size=10 color=CX2C7FB8);

yaxis reverse
      display=(nolabel)
      integer;

xaxis
      grid
      label="Approximate Mean |Contribution|";

title
"Approximate SHAP Beeswarm Summary";

run;


/**************************************************************************
SHAP Bar Plot Approximation
**************************************************************************/

proc sgplot data=work.top15;

hbarparm
    category=Variable
    response=MeanAbsSHAP
/
fillattrs=(color=CX4F81BD);

xaxis
grid
label="Normalized Variable Importance";

title
"Approximate SHAP Feature Importance";

run;


/**************************************************************************
Dependence Plot Approximation
**************************************************************************/

%macro dependence(var);

proc sgplot data=test_data;

scatter
x=&var.
y=Predicted
/
markerattrs=(symbol=circlefilled size=7);

loess
x=&var.
y=Predicted
/
smooth=0.5;

xaxis grid;

yaxis grid
label="Predicted Claim Frequency";

title "Dependence Plot - &var.";

run;

%mend;


/* Top explanatory variables */

%dependence(VehAge);

%dependence(DrivAge);

%dependence(BonusMalus);

%dependence(LogDensity);

%dependence(BonusMalusCapped);


/**************************************************************************
Individual Risk Analysis
(Waterfall Approximation)
**************************************************************************/

proc sort
data=test_predictions
out=work.sorted_prediction;

by Predicted;

run;


/* Lowest Risk */

data low_risk;

set work.sorted_prediction(firstobs=1 obs=1);

run;


/* Median Risk */

data median_risk;

set work.sorted_prediction
point=nobs
nobs=nobs;

if _N_=ceil(nobs/2);

stop;

run;


/* Highest Risk */

data high_risk;

set work.sorted_prediction;

if _N_=nobs;

run;


/* Display */

title "Lowest Risk Observation";

proc print data=low_risk;
run;

title "Median Risk Observation";

proc print data=median_risk;
run;

title "Highest Risk Observation";

proc print data=high_risk;
run;


/**************************************************************************
GLM vs Gradient Boost Comparison
**************************************************************************/

proc sql;

create table work.glm_vs_gb as

select

a.Feature,

a.GLM_Coef,

b.MeanAbsSHAP

from glm_coefficients as a

left join work.shap_importance as b

on a.Feature=b.Variable;

quit;


/**************************************************************************
Direction Agreement
**************************************************************************/

data work.glm_vs_gb;

set work.glm_vs_gb;

length Agreement $25.;

if GLM_Coef>0 and MeanAbsSHAP>0 then
Agreement="Same Direction";

else if GLM_Coef<0 and MeanAbsSHAP>0 then
Agreement="Opposite Direction";

else
Agreement="Insignificant";

run;


/**************************************************************************
Scatter Plot
**************************************************************************/

proc sgplot data=work.glm_vs_gb;

scatter
x=GLM_Coef
y=MeanAbsSHAP
/
datalabel=Feature
markerattrs=(symbol=circlefilled size=9);

refline 0 / axis=x;

xaxis grid
label="GLM Coefficient";

yaxis grid
label="Approximate SHAP Importance";

title
"GLM vs Gradient Boost Explainability";

run;


/**************************************************************************
Summary Table
**************************************************************************/

proc print
data=work.glm_vs_gb
label
noobs;

var
Feature
GLM_Coef
MeanAbsSHAP
Agreement;

run;

ods graphics off;
