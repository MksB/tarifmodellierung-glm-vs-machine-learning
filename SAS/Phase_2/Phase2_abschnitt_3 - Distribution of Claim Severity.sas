/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.3 - Distribution of Claim Severity
*
* Purpose:
*   Exploratory analysis of the claim severity distribution.
*
*   Analyses include:
*      - Histogram
*      - Histogram with Kernel Density
*      - Empirical CDF
*      - Boxplot
*      - Cube-Root Transformation
*      - Log Transformation
*
* Input :
*      WORK.SEVERITY_GLM
*
**************************************************************************/

ods graphics on;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.3 - Distribution of Claim Severity";

/*-----------------------------------------------------------------------
* 2.3.1 Histogram of Severity
*-----------------------------------------------------------------------*/

proc sgplot data=work.severity_glm;

    histogram Severity /
        nbins=40;

    density Severity /
        type=kernel;

    xaxis label="Claim Severity";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* 2.3.2 Empirical Distribution Function
*-----------------------------------------------------------------------*/

proc univariate data=work.severity_glm;

    cdfplot Severity /
        grid;

run;


/*-----------------------------------------------------------------------
* 2.3.3 Boxplot
*-----------------------------------------------------------------------*/

proc sgplot data=work.severity_glm;

    vbox Severity;

    yaxis label="Claim Severity";

run;


/*-----------------------------------------------------------------------
* 2.3.4 Create Transformed Variables
*-----------------------------------------------------------------------*/

data work.severity_glm;

    set work.severity_glm;

    /* Cube-root transformation */

    Severity_CubeRoot = Severity**(1/3);

    /* Natural logarithm */

    Log_Severity = log(Severity);

run;


/*-----------------------------------------------------------------------
* 2.3.5 Cube-Root Distribution
*-----------------------------------------------------------------------*/

title2 "Cube-Root Transformed Severity";

proc sgplot data=work.severity_glm;

    histogram Severity_CubeRoot /
        nbins=35;

    density Severity_CubeRoot /
        type=kernel;

    xaxis label="Cube-Root(Severity)";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* 2.3.6 Log Severity Distribution
*-----------------------------------------------------------------------*/

title2 "Log Severity";

proc sgplot data=work.severity_glm;

    histogram Log_Severity /
        nbins=35;

    density Log_Severity /
        type=kernel;

    xaxis label="Log(Severity)";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* 2.3.7 Distribution Diagnostics
*-----------------------------------------------------------------------*/

title2 "Distribution Diagnostics";

proc univariate data=work.severity_glm normal;

    var Severity;

    histogram Severity /
        kernel;

    inset

        n
        mean
        median
        std
        skewness
        kurtosis

        / position=ne;

run;


/*-----------------------------------------------------------------------
* 2.3.8 Cube-Root Diagnostics
*-----------------------------------------------------------------------*/

title2 "Cube-Root Distribution Diagnostics";

proc univariate data=work.severity_glm normal;

    var Severity_CubeRoot;

    histogram Severity_CubeRoot /
        kernel;

    inset

        n
        mean
        median
        std
        skewness
        kurtosis

        / position=ne;

run;


/*-----------------------------------------------------------------------
* 2.3.9 Log Distribution Diagnostics
*-----------------------------------------------------------------------*/

title2 "Log Severity Diagnostics";

proc univariate data=work.severity_glm normal;

    var Log_Severity;

    histogram Log_Severity /
        kernel;

    inset

        n
        mean
        median
        std
        skewness
        kurtosis

        / position=ne;

run;

ods graphics off;

title;
