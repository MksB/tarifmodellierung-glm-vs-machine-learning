/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.16 - Reporting
*
* Purpose:
*   Generate a comprehensive PDF report summarizing the results of the
*   severity modelling phase.
*
* Report Contents
* -------------------------------------------------------------------------
*   1. Gamma GLM - Parameter Estimates
*   2. Gamma GLM - Type III Tests
*   3. Gamma GLM - Goodness-of-Fit
*   4. Inverse Gaussian GLM - Parameter Estimates
*   5. Inverse Gaussian GLM - Goodness-of-Fit
*   6. Model Comparison
*   7. Intercept Balance Correction
*   8. Residual Diagnostics
*   9. Tariff Relativities
*
**************************************************************************/

ods _all_ close;

ods listing;

ods graphics on;

/*-----------------------------------------------------------------------
* PDF Output
*-----------------------------------------------------------------------*/

ods pdf

file="C:\REPORT\Phase2_Severity_Model_Report.pdf"

style=Journal

startpage=yes

notoc;


/**************************************************************************
* Cover Page
**************************************************************************/

title1 j=center h=18pt
"French MTPL Pricing Model";

title2 j=center h=14pt
"Phase 2 - Severity Modelling";

title3 j=center h=12pt
"Gamma GLM and Inverse Gaussian GLM";

footnote1 j=center
"Generated with SAS PROC GENMOD";

proc odstext;

    p " ";
    p "This report summarizes the complete severity modelling process.";
    p " ";
    p "Contents:";
    p " ";
    p "  • Gamma GLM";
    p "  • Inverse Gaussian GLM";
    p "  • Goodness-of-Fit";
    p "  • Type III Tests";
    p "  • Model Comparison";
    p "  • Balance Correction";
    p "  • Diagnostic Plots";
    p " ";

run;


/**************************************************************************
* Gamma GLM
**************************************************************************/

ods pdf startpage=now;

title1 "Gamma GLM";
title2 "Parameter Estimates";

proc print
    data=work.Gamma_Reduced_PE
    noobs
    label;
run;


title2 "Type III Tests";

proc print
    data=work.Gamma_Reduced_Type3
    noobs
    label;
run;


title2 "Model Fit";

proc print
    data=work.Gamma_Reduced_ModelFit
    noobs
    label;
run;


/**************************************************************************
* Inverse Gaussian GLM
**************************************************************************/

ods pdf startpage=now;

title1 "Inverse Gaussian GLM";

title2 "Parameter Estimates";

proc print
    data=work.IG_Full_PE
    noobs
    label;
run;


title2 "Model Fit";

proc print
    data=work.IG_Full_ModelFit
    noobs
    label;
run;


/**************************************************************************
* Model Comparison
**************************************************************************/

ods pdf startpage=now;

title1 "Model Comparison";

proc print
    data=work.Model_Comparison
    noobs
    label;
run;


/**************************************************************************
* Balance Correction
**************************************************************************/

ods pdf startpage=now;

title1 "Portfolio Balance Correction";

proc print
    data=work.Gamma_Balance
    noobs
    label;
run;


/**************************************************************************
* Residual Summary
**************************************************************************/

ods pdf startpage=now;

title1 "Residual Summary";

proc means

    data=work.Gamma_Reduced_Pred

    n
    mean
    std
    min
    q1
    median
    q3
    max
    maxdec=4;

    var

        RawResidual
        PearsonResidual
        DevianceResidual;

run;


/**************************************************************************
* Diagnostic Plots
**************************************************************************/

ods pdf startpage=now;

title1 "Observed versus Predicted";

proc sgplot

    data=work.Gamma_Reduced_Pred;

    scatter

        x=PredictedSeverity

        y=Severity

        / transparency=0.60;

    lineparm

        x=0
        y=0
        slope=1;

run;



title1 "Distribution of Deviance Residuals";

proc sgplot

    data=work.Gamma_Reduced_Pred;

    histogram DevianceResidual;

    density DevianceResidual / type=kernel;

run;


/**************************************************************************
* Tariff Relativities
**************************************************************************/

ods pdf startpage=now;

title1 "Tariff Relativities";

proc print

    data=work.Gamma_Relativities

    noobs

    label;

run;


/**************************************************************************
* Final Summary
**************************************************************************/

ods pdf startpage=now;

title1 "Summary";

proc odstext;

    p "Severity modelling completed successfully.";
    p " ";
    p "Generated Outputs:";
    p " ";
    p " • Gamma GLM";
    p " • Inverse Gaussian GLM";
    p " • Model Comparison";
    p " • Balance Correction";
    p " • Diagnostic Plots";
    p " • Tariff Relativities";
    p " ";
    p "End of Report.";

run;


/*-----------------------------------------------------------------------
* Close ODS
*-----------------------------------------------------------------------*/

ods pdf close;

ods graphics off;

ods listing;

title;
footnote;
