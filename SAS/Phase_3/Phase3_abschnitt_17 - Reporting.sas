/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.17 - Reporting
*
* Purpose:
*   Create a professional PDF report summarizing the complete
*   machine learning modelling process.
*
* Input:
*      WORK.BEST_PARAMS
*      WORK.FREQ_PERFORMANCE_FINAL
*      WORK.SEV_PERFORMANCE_FINAL
*      WORK.PURE_PREMIUM_SUMMARY
*      WORK.VARIMP_SUMMARY
*
* Output:
*      Phase3_ML_Model_Report.pdf
*
**************************************************************************/

/*-----------------------------------------------------------------------
* ODS Configuration
*-----------------------------------------------------------------------*/

ods graphics on;

ods pdf file="C:\Reports\Phase3_ML_Model_Report.pdf"
    style=journal
    dpi=300
    notoc;

/*-----------------------------------------------------------------------
* Cover Page
*-----------------------------------------------------------------------*/

title1 j=center h=16pt
"French Motor Third Party Liability";

title2 j=center h=14pt
"Machine Learning Pricing Models";

title3 j=center h=12pt
"Phase 3 - Model Development Report";

footnote1 j=center
"Generated on %sysfunc(datetime(),datetime20.)";

/*-----------------------------------------------------------------------
* Section 1 : Project Overview
*-----------------------------------------------------------------------*/

ods proclabel="Project Overview";

proc odstext;

p "Project: French MTPL Pricing";
p " ";
p "Phase 3 implements Machine Learning models for:";
p "  - Claim Frequency";
p "  - Claim Severity";
p " ";
p "Algorithms:";
p "  - Gradient Boosting";
p "  - Poisson Distribution";
p "  - Gamma Distribution";

run;

/*-----------------------------------------------------------------------
* Section 2 : Hyperparameters
*-----------------------------------------------------------------------*/

title "Optimal Hyperparameters";

proc print
    data=work.BEST_PARAMS
    label
    noobs;
run;

/*-----------------------------------------------------------------------
* Section 3 : Frequency Model Performance
*-----------------------------------------------------------------------*/

title "Frequency Model Performance";

proc print
    data=work.FREQ_PERFORMANCE_FINAL
    label
    noobs;
run;

/*-----------------------------------------------------------------------
* Section 4 : Severity Model Performance
*-----------------------------------------------------------------------*/

title "Severity Model Performance";

proc print
    data=work.SEV_PERFORMANCE_FINAL
    label
    noobs;
run;

/*-----------------------------------------------------------------------
* Section 5 : Pure Premium Summary
*-----------------------------------------------------------------------*/

title "Pure Premium Evaluation";

proc print
    data=work.PURE_PREMIUM_SUMMARY
    label
    noobs;
run;

/*-----------------------------------------------------------------------
* Section 6 : Variable Importance Ranking
*-----------------------------------------------------------------------*/

title "Variable Importance Ranking";

proc print
    data=work.VARIMP_SUMMARY(obs=20)
    label
    noobs;
run;

/*-----------------------------------------------------------------------
* Section 7 : Variable Importance Plot
*-----------------------------------------------------------------------*/

title "Top 20 Variable Importance";

proc sgplot data=work.VARIMP_SUMMARY(obs=20);

    hbar Variable /
        response=Total_Importance
        datalabel
        categoryorder=respdesc;

    xaxis label="Relative Importance";
    yaxis label="Predictor";

run;

/*-----------------------------------------------------------------------
* Section 8 : Frequency Prediction Diagnostics
*-----------------------------------------------------------------------*/

title "Observed vs Predicted Frequency";

proc sgplot data=work.FREQ_VALID_PRED;

    scatter
        x=Claim_Frequency
        y=Pred_Frequency
        transparency=0.40;

    lineparm
        x=0
        y=0
        slope=1;

    xaxis label="Observed";
    yaxis label="Predicted";

run;

/*-----------------------------------------------------------------------
* Section 9 : Severity Prediction Diagnostics
*-----------------------------------------------------------------------*/

title "Observed vs Predicted Severity";

proc sgplot data=work.SEV_VALID_PRED;

    scatter
        x=Claim_Severity
        y=Pred_Severity
        transparency=0.40;

    lineparm
        x=0
        y=0
        slope=1;

    xaxis label="Observed";
    yaxis label="Predicted";

run;

/*-----------------------------------------------------------------------
* Section 10 : Model Summary
*-----------------------------------------------------------------------*/

title "Model Summary";

proc odstext;

p "The modelling process has been completed successfully.";
p " ";
p "Developed Models:";
p "  - Frequency Model (Poisson Gradient Boosting)";
p "  - Severity Model (Gamma Gradient Boosting)";
p " ";
p "Outputs:";
p "  - Final prediction models";
p "  - Variable importance";
p "  - Hyperparameter optimization";
p "  - Validation statistics";
p "  - Pure Premium estimation";
p " ";
p "This report documents the complete Phase 3 machine learning workflow.";

run;

/*-----------------------------------------------------------------------
* Close Report
*-----------------------------------------------------------------------*/

footnote;

ods pdf close;
ods graphics off;

title;
