/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 2 - Severity Modelling
* Section  : 2.2 - Descriptive Statistics of Claim Severity
*
* Purpose:
*   Descriptive statistical analysis of the response variable
*   "Severity" prior to Gamma GLM modelling.
*
* Input :
*      WORK.SEVERITY_GLM
*
**************************************************************************/

ods graphics on;

title1 "Phase 2 - Severity Modelling";
title2 "Section 2.2 - Descriptive Statistics of Claim Severity";

/*-----------------------------------------------------------------------
* 2.2.1 Summary Statistics
*-----------------------------------------------------------------------*/

proc means data=work.severity_glm
           n
           nmiss
           mean
           median
           std
           var
           cv
           min
           q1
           q3
           max
           sum
           skewness
           kurtosis
           maxdec=2;

    var Severity;

run;


/*-----------------------------------------------------------------------
* 2.2.2 Detailed Distribution Statistics
*-----------------------------------------------------------------------*/

proc univariate data=work.severity_glm;

    var Severity;

    inset
        n
        mean
        median
        std
        skewness
        kurtosis
        min
        q1
        q3
        max
        / position=ne;

run;


/*-----------------------------------------------------------------------
* 2.2.3 Selected Percentiles
*-----------------------------------------------------------------------*/

proc univariate data=work.severity_glm noprint;

    var Severity;

    output out=work.Severity_Percentiles

        pctlpts=
            1
            5
            10
            25
            50
            75
            90
            95
            99

        pctlpre=P_;

run;


title3 "Selected Percentiles";

proc print
    data=work.Severity_Percentiles
    noobs
    label;

    label

        P_1  ="1st Percentile"
        P_5  ="5th Percentile"
        P_10 ="10th Percentile"
        P_25 ="25th Percentile"
        P_50 ="Median"
        P_75 ="75th Percentile"
        P_90 ="90th Percentile"
        P_95 ="95th Percentile"
        P_99 ="99th Percentile";

run;


/*-----------------------------------------------------------------------
* 2.2.4 Range Validation
*-----------------------------------------------------------------------*/

title3 "Severity Validation";

proc sql;

    select

        count(*)                                   as Number_of_Observations,

        sum(missing(Severity))                     as Missing_Severity,

        sum(Severity<=0)                           as NonPositive_Severity,

        min(Severity)      format=comma14.2        as Minimum_Severity,

        max(Severity)      format=comma14.2        as Maximum_Severity,

        mean(Severity)     format=comma14.2        as Mean_Severity,

        median(Severity)   format=comma14.2        as Median_Severity

    from work.severity_glm;

quit;


/*-----------------------------------------------------------------------
* 2.2.5 Five Largest Claims
*-----------------------------------------------------------------------*/

proc sort
    data=work.severity_glm
    out=work.Severity_Max;

    by descending Severity;

run;


title3 "Five Largest Claim Severities";

proc print
    data=work.Severity_Max(obs=5)
    noobs;

    var

        IDpol
        ClaimNb
        ClaimTotal
        Severity;

run;


/*-----------------------------------------------------------------------
* 2.2.6 Five Smallest Claims
*-----------------------------------------------------------------------*/

proc sort
    data=work.severity_glm
    out=work.Severity_Min;

    by Severity;

run;


title3 "Five Smallest Claim Severities";

proc print
    data=work.Severity_Min(obs=5)
    noobs;

    var

        IDpol
        ClaimNb
        ClaimTotal
        Severity;

run;

ods graphics off;

title;
