/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Data Cleaning & Exposure Analysis
* Section  : 6 - Analysis of Log(Exposure)
*
* Purpose:
*   Analyse the logarithm of the exposure variable used as the offset
*   in the Poisson GLM.
*
*   The offset variable is defined as
*
*       Log_Exposure = log(Exposure)
*
*   and is later incorporated in PROC GENMOD via
*
*       OFFSET = Log_Exposure
*
* Input:
*       WORK.DAT_FINAL
*
**************************************************************************/

ods graphics on;

title1 "Phase 1 - Analysis of Log(Exposure)";

/*-----------------------------------------------------------------------
* 6.1 Descriptive Statistics
*-----------------------------------------------------------------------*/

title2 "Descriptive Statistics of Log(Exposure)";

proc means data=work.dat_final
           n
           nmiss
           mean
           median
           std
           min
           q1
           q3
           max
           skewness
           kurtosis
           maxdec=6;

    var Log_Exposure;

run;


/*-----------------------------------------------------------------------
* 6.2 Distribution Analysis
*-----------------------------------------------------------------------*/

title2 "Distribution of Log(Exposure)";

proc univariate data=work.dat_final normal;

    var Log_Exposure;

    histogram Log_Exposure /
        kernel;

    inset
        n
        mean
        median
        std
        skewness
        kurtosis
        min
        max
        / position=ne;

run;


/*-----------------------------------------------------------------------
* 6.3 Histogram
*-----------------------------------------------------------------------*/

title2 "Histogram of Log(Exposure)";

proc sgplot data=work.dat_final;

    histogram Log_Exposure /
        nbins=30;

    density Log_Exposure /
        type=kernel;

    xaxis label="Log(Exposure)";
    yaxis label="Density";

run;


/*-----------------------------------------------------------------------
* 6.4 Boxplot
*-----------------------------------------------------------------------*/

title2 "Boxplot of Log(Exposure)";

proc sgplot data=work.dat_final;

    vbox Log_Exposure;

    yaxis label="Log(Exposure)";

run;


/*-----------------------------------------------------------------------
* 6.5 Numerical Validation
*-----------------------------------------------------------------------*/

title2 "Validation of Log(Exposure)";

proc sql;

    select

        count(*)                                    as Total_Observations,

        sum(missing(Log_Exposure))                  as Missing_LogExposure,

        sum(Log_Exposure > 0)                       as Positive_LogExposure,

        sum(Log_Exposure = 0)                       as Zero_LogExposure,

        sum(Log_Exposure < 0)                       as Negative_LogExposure,

        min(Log_Exposure) format=10.6              as Minimum_LogExposure,

        max(Log_Exposure) format=10.6              as Maximum_LogExposure

    from work.dat_final;

quit;


/*-----------------------------------------------------------------------
* 6.6 Extreme Values
*-----------------------------------------------------------------------*/

title2 "Lowest Log(Exposure) Values";

proc sort data=work.dat_final
          out=LogExposure_Min;

    by Log_Exposure;

run;

proc print data=LogExposure_Min(obs=20) noobs;

    var IDpol Exposure Log_Exposure;

run;


/*-----------------------------------------------------------------------
* 6.7 Highest Log(Exposure) Values
*-----------------------------------------------------------------------*/

title2 "Highest Log(Exposure) Values";

proc sort data=work.dat_final
          out=LogExposure_Max;

    by descending Log_Exposure;

run;

proc print data=LogExposure_Max(obs=20) noobs;

    var IDpol Exposure Log_Exposure;

run;


/*-----------------------------------------------------------------------
* 6.8 Percentiles
*-----------------------------------------------------------------------*/

title2 "Percentiles of Log(Exposure)";

proc univariate data=work.dat_final;

    var Log_Exposure;

    output out=LogExposure_Pctl

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

proc print data=LogExposure_Pctl noobs;

run;

ods graphics off;

title;
