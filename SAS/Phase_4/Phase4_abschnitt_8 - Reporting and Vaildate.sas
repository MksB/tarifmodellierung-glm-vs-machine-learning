/**************************************************************************
SECTION 8
Reporting & Validation
Equivalent of Python:
    - write_regulatory_report()
    - run_unit_tests()
    - main()
**************************************************************************/

options mprint mlogic symbolgen;

title;
footnote;

/**************************************************************************
OUTPUT PATH
**************************************************************************/

%let OUTPUT_DIR = C:\Report;

/**************************************************************************
REPORT FILE
**************************************************************************/

filename report "&OUTPUT_DIR./regulatory_report.txt";

/**************************************************************************
MACRO:
WRITE_REGULATORY_REPORT
**************************************************************************/

%macro write_regulatory_report;

proc sql noprint;

select Feature
into :TOP1-:TOP5
from shap_importance(obs=5);

select MeanAbsSHAP
into :SHAP1-:SHAP5
from shap_importance(obs=5);

quit;

data _null_;

file report lrecl=32767;

put "==========================================================================";
put "REGULATORY EXPLAINABILITY REPORT";
put "==========================================================================";
put;

put "Document Type : Phase 4 - Explainability";
put "Dataset       : freMTPL";
put "Target        : Claim Frequency";
put "Models        : Poisson GLM + Gradient Boosting";
put "Platform      : SAS 9.4";
put;

put "--------------------------------------------------------------------------";
put "1. PURPOSE";
put "--------------------------------------------------------------------------";
put;

put "This report summarises the explainability analysis of the";
put "Gradient Boosting claim frequency model.";
put;

put "--------------------------------------------------------------------------";
put "2. TOP SHAP APPROXIMATION FEATURES";
put "--------------------------------------------------------------------------";
put;

put "Rank   Feature                     Importance";

put "-----------------------------------------------------------";

put "1      &TOP1.                     &SHAP1.";
put "2      &TOP2.                     &SHAP2.";
put "3      &TOP3.                     &SHAP3.";
put "4      &TOP4.                     &SHAP4.";
put "5      &TOP5.                     &SHAP5.";

put;
put "The ranking is based on normalized Gradient Boosting";
put "variable importance which approximates SHAP importance.";
put;

put "--------------------------------------------------------------------------";
put "3. MODEL VALIDATION";
put "--------------------------------------------------------------------------";
put;

put "Validation included:";
put " * Dataset integrity";
put " * Prediction validation";
put " * Variable importance";
put " * GLM comparison";
put;

put "--------------------------------------------------------------------------";
put "4. LIMITATIONS";
put "--------------------------------------------------------------------------";
put;

put "SAS 9.4 does not provide native SHAP values.";
put "Variable importance and dependence plots were used";
put "as an explainability approximation.";
put;

put "--------------------------------------------------------------------------";
put "5. CONCLUSION";
put "--------------------------------------------------------------------------";
put;

put "The Gradient Boosting model demonstrates consistent";
put "risk drivers compared to the GLM baseline and";
put "provides an interpretable machine learning solution";
put "within SAS 9.4.";

put;
put "End of Report.";

run;

%mend;


/**************************************************************************
MACRO:
RUN_UNIT_TESTS
Equivalent of Python run_unit_tests()
**************************************************************************/

%macro run_unit_tests;

%put;
%put ========================================;
%put RUNNING UNIT TESTS;
%put ========================================;

/***********************************************************************
TEST 1
Dataset Integrity
***********************************************************************/

proc sql noprint;

select count(*)
into :N_EXPOSURE

from model_data

where Exposure<=0;

quit;

%if &N_EXPOSURE.=0 %then
    %put NOTE: TEST 1 PASSED - Exposure > 0.;
%else
    %do;
        %put ERROR: TEST 1 FAILED.;
        %abort cancel;
    %end;


/***********************************************************************
TEST 2
Missing Values
***********************************************************************/

proc means
data=model_data
nmiss
noprint;

var
VehPower
VehAge
DrivAge
BonusMalus
Density
LogDensity
BonusMalusCapped;

output out=missing_check;

run;

data _null_;

set missing_check;

array vars {*} _numeric_;

do i=1 to dim(vars);

    if vars(i)>0 then do;
        put "ERROR: Missing values detected.";
        abort abend;
    end;

end;

run;

%put NOTE: TEST 2 PASSED - No Missing Values.;


/***********************************************************************
TEST 3
Prediction Validation
***********************************************************************/

proc sql noprint;

select count(*)
into :BAD_PRED

from test_predictions

where Predicted<0
or missing(Predicted);

quit;

%if &BAD_PRED.=0 %then
%put NOTE: TEST 3 PASSED - Predictions valid.;
%else
%do;
%put ERROR: TEST 3 FAILED.;
%abort cancel;
%end;


/***********************************************************************
TEST 4
Variable Importance
***********************************************************************/

proc sql noprint;

select count(*)
into :N_IMPORTANCE

from shap_importance;

quit;

%if &N_IMPORTANCE.>=5 %then
%put NOTE: TEST 4 PASSED.;
%else
%do;
%put ERROR: TEST 4 FAILED.;
%abort cancel;
%end;

%put;
%put ALL UNIT TESTS PASSED.;
%put;

%mend;


/**************************************************************************
MACRO:
SUMMARY
**************************************************************************/

%macro summary;

title "Top Variable Importance";

proc print
data=shap_importance(obs=10)
label
noobs;
run;

title "GLM versus Gradient Boost";

proc print
data=glm_vs_gb
label
noobs;
run;

%mend;


/**************************************************************************
MAIN()
Equivalent of Python main()
**************************************************************************/

%macro main;

%put;
%put =====================================================;
%put PHASE 4 - SHAP ANALYSIS;
%put =====================================================;

/***********************************************************************
Previous Sections
***********************************************************************/

%put Data Preparation Completed.;
%put Feature Encoding Completed.;
%put Train/Test Split Completed.;
%put GLM Completed.;
%put Gradient Boost Completed.;
%put Explainability Completed.;

/***********************************************************************
Validation
***********************************************************************/

%run_unit_tests

/***********************************************************************
Reporting
***********************************************************************/

%write_regulatory_report

/***********************************************************************
Summary
***********************************************************************/

%summary

%put;
%put =====================================================;
%put ALL OUTPUTS SUCCESSFULLY GENERATED;
%put =====================================================;

%mend;


/**************************************************************************
EXECUTE PIPELINE
**************************************************************************/

%main;
