/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Data Cleaning & Exposure Analysis
* Section  : 4 - Recording Precision Analysis
*
* Purpose:
*   Classify the precision of the recorded Exposure values.
*
*   Exposure values are classified into:
*
*      - Full Year        (Exposure = 1)
*      - Monthly          (k / 12)
*      - Daily            (k / 365)
*      - Decimal          (other values)
*
* Input:
*      WORK.DAT_FINAL
*
* Output:
*      WORK.EXPOSURE_PRECISION
*
**************************************************************************/

%macro RecordingPrecision(
        data=work.dat_final,
        out=work.exposure_precision);

data &out;

    set &data;

    length RecordingPrecision $20;

    /*---------------------------------------------------------------
      Full policy year
    ---------------------------------------------------------------*/

    if Exposure = 1 then
        RecordingPrecision = "Full Year";

    /*---------------------------------------------------------------
      Monthly recording precision
      (Exposure = k / 12)
    ---------------------------------------------------------------*/

    else if abs(Exposure*12 - round(Exposure*12,1)) < 1E-8 then
        RecordingPrecision = "Monthly";

    /*---------------------------------------------------------------
      Daily recording precision
      (Exposure = k / 365)
    ---------------------------------------------------------------*/

    else if abs(Exposure*365 - round(Exposure*365,1)) < 1E-8 then
        RecordingPrecision = "Daily";

    /*---------------------------------------------------------------
      Other decimal values
    ---------------------------------------------------------------*/

    else
        RecordingPrecision = "Decimal";

run;


/*-----------------------------------------------------------------------
* Frequency Table
*-----------------------------------------------------------------------*/

title1 "Phase 1 - Recording Precision";
title2 "Classification of Exposure Recording Precision";

proc freq data=&out;

    tables RecordingPrecision / nocum missing;

run;


/*-----------------------------------------------------------------------
* Percentage Distribution
*-----------------------------------------------------------------------*/

proc freq data=&out;

    tables RecordingPrecision /
           nocum
           out=RecordingPrecision_Freq;

run;


/*-----------------------------------------------------------------------
* Bar Chart
*-----------------------------------------------------------------------*/

title2 "Distribution of Recording Precision";

proc sgplot data=RecordingPrecision_Freq;

    vbar RecordingPrecision /
         response=percent
         stat=sum
         datalabel;

    xaxis label="Recording Precision";

    yaxis label="Percent of Policies";

run;


/*-----------------------------------------------------------------------
* Cross-check with Exposure Values
*-----------------------------------------------------------------------*/

title2 "Recording Precision by Exposure";

proc means data=&out
           n
           mean
           median
           min
           max
           maxdec=6;

    class RecordingPrecision;

    var Exposure;

run;

%mend RecordingPrecision;


/*-----------------------------------------------------------------------
* Execute Macro
*-----------------------------------------------------------------------*/

%RecordingPrecision();
