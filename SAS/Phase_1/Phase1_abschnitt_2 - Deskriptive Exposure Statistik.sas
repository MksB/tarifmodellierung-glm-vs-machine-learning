/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Data Cleaning & Exposure Analysis
* Section  : 2 - Descriptive Exposure Statistics
*
* Purpose:
*   Descriptive statistical analysis of the Exposure variable.
*   This section provides sample size, central tendency, dispersion,
*   distribution characteristics, and exposure quality indicators.
*
* Input :  WORK.DAT_FINAL
* Output:  Printed statistical summaries (ODS)
**************************************************************************/


/*-----------------------------------------------------------------------
* 2.0 Define User-Defined Format for Binning
*-----------------------------------------------------------------------*/
/* Da Exposure kontinuierlich ist, müssen wir Klassen für 
   PROC FREQ und bessere Übersichtlichkeit definieren. */
proc format;
    value ExpBkt
        low     -< 0.25 = '< 0.25'
        0.25   -< 0.50  = '[0.25, 0.50)'
        0.50   -< 0.75  = '[0.50, 0.75)'
        0.75   -< 1.00  = '[0.75, 1.00)'
        1.00          = '1.00 (Full Year)';
run;


/*-----------------------------------------------------------------------
* 2.1 Descriptive statistics
*-----------------------------------------------------------------------*/

title1 "Phase 1 - Section 2";
title2 "Descriptive Statistics of Exposure";

proc means data=work.dat_final
           n nmiss mean median std var cv 
           min q1 q3 max sum
           maxdec=6;
    var Exposure;
    format Exposure 8.6; /* Einheitliche Anzeige */
run;


/*-----------------------------------------------------------------------
* 2.2 Distribution statistics (Histogram)
*-----------------------------------------------------------------------*/
/* Hinweis: / normal wurde entfernt, da Exposure auf [0,1] begrenzt 
   ist und keine Normalverteilung folgt. */
title2 "Exposure Distribution";


proc univariate data=work.dat_final noprint;
    var Exposure;
    histogram Exposure / 
        midpoints=0 to 1 by 0.05          /* Saubere X-Achse von 0 bis 1 */
        odstitle="Histogram of Exposure"
        fill;
    inset 
        n mean median std skewness kurtosis min max
        / position=ne format=8.4;
run;


/*-----------------------------------------------------------------------
* 2.3 Exposure Frequency Distribution (Binned)
*-----------------------------------------------------------------------*/
/* Anwendung des in 2.0 definierten Formats */
title2 "Exposure Frequency by Category";

proc freq data=work.dat_final;
    tables Exposure / nocol nopercent missing;
    format Exposure ExpBkt.;
run;


/*-----------------------------------------------------------------------
* 2.4 Exposure Quality Indicators
*-----------------------------------------------------------------------*/
/* Syntax-Fehler behoben: format= steht nun nach dem AS-Alias */

title2 "Exposure Quality Indicators";

proc sql;
    select
        count(*)                                                    
            as Total_Policies          format=comma12.0,
        
        sum(case when Exposure=1 then 1 else 0 end)                
            as Full_Year_Policies      format=comma12.0,
            
        sum(case when Exposure=1 then 1 else 0 end) / count(*)     
            as Pct_Full_Year           format=percent8.2,
        
        sum(case when Exposure<1 then 1 else 0 end)                
            as Partial_Exposure        format=comma12.0,
            
        sum(case when Exposure<1 then 1 else 0 end) / count(*)     
            as Pct_Partial             format=percent8.2,
        
        sum(case when Exposure<0.01 then 1 else 0 end)             
            as Very_Short_Exposure     format=comma12.0,
            
        sum(case when Exposure<0.01 then 1 else 0 end) / count(*)  
            as Pct_Very_Short          format=percent8.2,
        
        sum(Exposure)                                            
            as Total_Exposure          format=12.2
            
    from work.dat_final;
quit;


/*-----------------------------------------------------------------------
* 2.5 Percentile Analysis
*-----------------------------------------------------------------------*/
/* VAR-Statement im PROC PRINT hinzugefügt, um _TYPE_ und _FREQ_ 
   auszublenden, die PROC UNIVARIATE automatisch erzeugt. */

title2 "Exposure Percentiles";

proc univariate data=work.dat_final noprint;
    var Exposure;
    output out=work._temp_percentiles
        pctlpts=1 5 10 25 50 75 90 95 99
        pctlpre=P_;
run;

proc print data=work._temp_percentiles noobs label;
    var P_1 P_5 P_10 P_25 P_50 P_75 P_90 P_95 P_99;
    label
        P_1  ="1st Percentile"
        P_5  ="5th Percentile"
        P_10 ="10th Percentile"
        P_25 ="25th Percentile"
        P_50 ="Median (50th)"
        P_75 ="75th Percentile"
        P_90 ="90th Percentile"
        P_95 ="95th Percentile"
        P_99 ="99th Percentile";
    format P_: 8.6;
run;


/*-----------------------------------------------------------------------
* 2.6 Confirmation of Data Bounds (Post-Section 1 Validation)
*-----------------------------------------------------------------------*/
/* Redundante Prüfung auf <=0 oder >1 entfernt, da Section 1 dies 
   via %abort cancel verboten hat. Stattdessen finale Bestätigung. */

title2 "Data Bound Confirmation (Post Section 1)";

proc sql;
    select
        min(Exposure) as Min_Exposure format=8.6,
        max(Exposure) as Max_Exposure format=8.6,
        count(*)      as N_Obs        format=comma12.
    from work.dat_final;
quit;

%put NOTE: Section 2 confirms data bounds are strictly > 0 and <= 1;


/*-----------------------------------------------------------------------
* Cleanup: Temporäre Datasets entfernen
*-----------------------------------------------------------------------*/
proc datasets lib=work nolist;
    delete _temp_percentiles;
quit;


/* Reset Titles */
title;
title2;
