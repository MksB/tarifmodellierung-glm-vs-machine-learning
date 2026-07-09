/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Data Cleaning & Exposure Analysis
* Section  : 3 - Exposure Distribution
*
* Purpose:
*   Visual examination of the Exposure distribution.
*   Graphical analyses include:
*      1. Histogram (with fixed bin width)
*      2. Histogram with Kernel Density Estimate
*      3. Empirical Cumulative Distribution Function (ECDF)
*      4. Boxplot (5-number summary)
*      5. Distribution Shape Diagnostics (Skewness/Kurtosis)
*
* Input:   WORK.DAT_FINAL
**************************************************************************/

ods graphics on / reset=index imagemap=on;


/*-----------------------------------------------------------------------
* 3.1 Histogram of Exposure
*-----------------------------------------------------------------------*/
/* Verbesserung: binwidth=0.05 statt nbins=30 für runde Intervalle.
   X-Achse zwingend auf [0, 1] begrenzen. */
title1 "Phase 1 - Exposure Analysis";
title2 "Histogram of Exposure";

proc sgplot data=work.dat_final;
    histogram Exposure / binwidth=0.05 binstart=0 
                        showbins scale=count;
    
    xaxis label="Exposure (Policy Years)" min=0 max=1 
          values=(0 to 1 by 0.1) grid;
    yaxis label="Frequency" grid;
run;


/*-----------------------------------------------------------------------
* 3.2 Histogram with Kernel Density Estimate
*-----------------------------------------------------------------------*/
/* Verbesserung: X-Achse auf [0, 1] begrenzt. */
title2 "Exposure Distribution with Kernel Density";

proc sgplot data=work.dat_final;
    histogram Exposure / binwidth=0.05 binstart=0 transparency=0.7;
    density Exposure / type=kernel lineattrs=(thickness=2 color=CX002060);
    
    xaxis label="Exposure (Policy Years)" min=0 max=1 grid;
    yaxis label="Density" grid;
run;


/*-----------------------------------------------------------------------
* 3.3 Empirical Cumulative Distribution Function (ECDF)
*-----------------------------------------------------------------------*/
/* Wir aggregieren die Daten vorher auf einzigartige Exposure-Stufen.
   Das verhindert, dass SGPLOT bei 500.000 Einzelbeobachtungen 
   einfriert und liefert trotzdem eine mathematisch exakte ECDF. */

/* Schritt 1: Häufigkeiten pro Exposure-Wert zählen */
proc sql noprint;
    create table _temp_freq as
    select Exposure, count(*) as Freq 
    from work.dat_final 
    group by Exposure;
    
    /* Gesamtzahl für die Makro-Variable holen (falls nicht aus Sect 1 bekannt) */
    select count(*) into :N_TOTAL trimmed 
    from work.dat_final;
quit;

/* Schritt 2: Kumulieren und ECDF berechnen */
data _temp_ecdf;
    set _temp_freq;
    by Exposure;
    
    if first.Exposure then CumFreq = 0;
    CumFreq + Freq;
    
    ECDF = CumFreq / &N_TOTAL;
    
    format ECDF 8.6;
    keep Exposure ECDF;
run;

/* Schritt 3: Plotten der wenigen aggregierten Punkte */
title2 "Empirical Cumulative Distribution Function (ECDF)";

proc sgplot data=_temp_ecdf;
    step x=Exposure y=ECDF / legendlabel="ECDF" lineattrs=(thickness=2);
    
    xaxis label="Exposure (Policy Years)" min=0 max=1 grid;
    yaxis label="Cumulative Probability"  min=0 max=0.1 grid;
run;

/* Temporäre Daten sofort wieder aufräumen */
proc datasets lib=work nolist;
    delete _temp_freq _temp_ecdf;
quit;

/*-----------------------------------------------------------------------
* 3.4 Boxplot of Exposure
*-----------------------------------------------------------------------*/
/* Hinweis: Ein Boxplot ohne CATEGORY erzeugt nur eine einzige Box.
   Er dient hier als visuelle Bestätigung der 5-Zahlen-Zusammenfassung. */
title2 "Boxplot of Exposure";

proc sgplot data=work.dat_final;
    
    /* Kein category= nötig, zeichnet automatisch eine einzige Box */
    vbox Exposure / nooutliers fillattrs=(color=CXE0E0E0);
    
    /* X-Achse komplett ausblenden, da sie keine Informationen enthält */
    xaxis display=none;
    
    yaxis label="Exposure (Policy Years)" min=0 max=1 grid;
run;


/*-----------------------------------------------------------------------
* 3.5 Distribution Shape Diagnostics
*-----------------------------------------------------------------------*/
/* WICHTIG: Option 'normal' wurde entfernt! 
   Exposure ist auf [0,1] begrenzt, ein Normalitätstest ist hier 
   mathematisch unangebracht und rechenintensiv bei großen Datenmengen.
   Schiefe und Wölbung (Skewness/Kurtosis) reichen zur Beschreibung. */
title2 "Distribution Shape Diagnostics";

proc univariate data=work.dat_final noprint;
    var Exposure;
    
    histogram Exposure / kernel 
                        odstitle="Exposure Shape Analysis";
    
    inset n mean median std skewness kurtosis min max 
          / position=ne format=8.4;
run;


ods graphics off;

/* Reset global titles */
title;
title2;
