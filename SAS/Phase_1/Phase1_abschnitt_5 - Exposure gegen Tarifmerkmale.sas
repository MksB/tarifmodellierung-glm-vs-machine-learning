/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Data Cleaning & Exposure Analysis
* Section  : 5 - Exposure versus Rating Variables
*
* Purpose:
*   Exploratory analysis of the relationship between Exposure and
*   rating variables.
*
*   Categorical variables:
*      - Area
*      - VehGas
*      - VehBrand
*
*   Continuous variables:
*      - DrivAge
*      - VehAge
*      - BonusMalus
*      - Density
*
* Input:
*      WORK.DAT_FINAL
*
**************************************************************************/

ods graphics on;

title1 "Phase 1 - Exposure versus Rating Variables";

/*-----------------------------------------------------------------------
* 5.1 Exposure by Area
*-----------------------------------------------------------------------*/

title2 "Exposure by Area";

proc sgplot data=work.dat_final;

    vbox Exposure /
        category=Area;

    xaxis label="Area";
    yaxis label="Exposure";

run;


/*-----------------------------------------------------------------------
* 5.2 Exposure by Vehicle Fuel Type
*-----------------------------------------------------------------------*/

title2 "Exposure by Vehicle Fuel Type";

proc sgplot data=work.dat_final;

    vbox Exposure /
        category=VehGas;

    xaxis label="Vehicle Fuel";
    yaxis label="Exposure";

run;


/*-----------------------------------------------------------------------
* 5.3 Exposure by Vehicle Brand
*-----------------------------------------------------------------------*/

title2 "Exposure by Vehicle Brand";

proc sgplot data=work.dat_final;

    vbox Exposure /
        category=VehBrand;

    xaxis label="Vehicle Brand";
    yaxis label="Exposure";

run;


/*-----------------------------------------------------------------------
* 5.4 Exposure versus Driver Age
*-----------------------------------------------------------------------*/

title2 "Dichte-Heatmap: Exposure versus Driver Age";

proc sgplot data=work.dat_final;
    heatmap x=DrivAge y=Exposure / xbinsize=1 ybinsize=0.1;
    loess x=DrivAge y=Exposure / nomarkers lineattrs=(color=red thickness=2) transparency=0.3;
    xaxis label="Driver Age";
    yaxis label="Exposure";
run;

/*
title2 "Exposure versus Driver Age";

proc sgplot data=work.dat_final;

    scatter x=DrivAge
            y=Exposure
            / transparency=0.65;

    loess x=DrivAge
          y=Exposure;

    xaxis label="Driver Age";
    yaxis label="Exposure";

run;
*/

/*-----------------------------------------------------------------------
* 5.5 Exposure versus Vehicle Age
*-----------------------------------------------------------------------*/

title2 "Exposure versus Vehicle Age";

/* first graph */
proc sgplot data=work.dat_final;

    scatter x=VehAge
            y=Exposure
            / transparency=0.85;

    loess x=VehAge
          y=Exposure;

    xaxis label="Vehicle Age";
    yaxis label="Exposure";

run;


/* second graph */
proc summary data=work.dat_final nway;
  class DrivAge;
  var Exposure;
  output out=agg mean=meanExp p25=Q1 p75=Q3;
run;

proc sgplot data=agg;
  series x=DrivAge y=meanExp / lineattrs=(thickness=2 color=red);
  band x=DrivAge lower=Q1 upper=Q3 / transparency=0.5;
  xaxis label="Driver Age (bin)";
  yaxis label="Exposure";
run;

/* third graph */
proc sql;
  create table heatagg as
  select floor(DrivAge) as xbin, floor(Exposure*10)/10 as ybin, count(*) as cnt
  from work.dat_final
  group by xbin, ybin;
quit;

proc sgplot data=heatagg;
  heatmapparm x=xbin y=ybin colorresponse=cnt / colormodel=(white blue red) transparency=0.1;
run;


/*-----------------------------------------------------------------------
* 5.6 Exposure versus Bonus-Malus
*-----------------------------------------------------------------------*/

title2 "Exposure versus Bonus-Malus";

proc sgplot data=work.dat_final;

    scatter x=BonusMalus
            y=Exposure
            / transparency=0.85;

    loess x=BonusMalus
          y=Exposure;

    xaxis label="Bonus-Malus";
    yaxis label="Exposure";

run;

/* A */
data work.bins;
  set work.dat_final;
  DrivBM_bin = floor(BonusMalus); /* oder custom bin width */
run;

proc summary data=work.bins nway;
  class DrivBM_bin;
  var Exposure;
  output out=agg mean=meanExp p25=Q1 p75=Q3 n=nObs;
run;

proc sgplot data=agg;
  series x=DrivBM_bin y=meanExp / lineattrs=(color=red thickness=2);
  band x=DrivBM_bin lower=Q1 upper=Q3 / transparency=0.4;
  xaxis label="Bonus-Malus (bin)";
  yaxis label="Exposure";
run;

/* B */
proc sql;
  create table heatagg as
  select floor(BonusMalus*2)/2 as xbin, floor(Exposure*10)/10 as ybin, count(*) as cnt
  from work.dat_final
  group by xbin, ybin;
quit;

proc sgplot data=heatagg;
  heatmapparm x=xbin y=ybin colorresponse=cnt / colormodel=(white blue red) transparency=0.1;
  xaxis label="Bonus-Malus";
  yaxis label="Exposure";
run;

/* C */
proc kde data=work.dat_final out=kde_out;
  var BonusMalus Exposure;
  /* optional: NGRID=80 80 BWM=... */
run;

proc sgplot data=kde_out;
  heatmapparm x=BonusMalus y=Exposure colorresponse=density / colormodel=(white yellow red);
  series x=BonusMalus y=density /; /* or use contour-like series from KDE output */
run;


/*-----------------------------------------------------------------------
* 5.7 Exposure versus Population Density
*-----------------------------------------------------------------------*/

title2 "Exposure versus Population Density";

proc sgplot data=work.dat_final;

    scatter x=Density
            y=Exposure
            / transparency=0.85;

    loess x=Density
          y=Exposure;

    xaxis label="Population Density";
    yaxis label="Exposure";

run;
/* A */
proc sql;
  create table heatagg as
  select floor(Density*2)/2 as xbin, floor(Exposure*10)/10 as ybin, count(*) as cnt
  from work.dat_final
  group by xbin, ybin;
quit;

proc sgplot data=heatagg;
  heatmapparm x=xbin y=ybin colorresponse=cnt / colormodel=(white lightblue blue red) transparency=0.1;
  xaxis label="Population Density";
  yaxis label="Exposure";
run;

/* B */
data work.tmp;
  set work.dat_final;
  Density_bin = floor(Density); /* oder custom width */
run;

proc summary data=work.tmp nway;
  class Density_bin;
  var Exposure;
  output out=agg mean=meanExp p25=Q1 p75=Q3 n=nObs;
run;

proc sgplot data=agg;
  band x=Density_bin lower=Q1 upper=Q3 / transparency=0.4;
  series x=Density_bin y=meanExp / lineattrs=(color=red thickness=2);
  xaxis label="Population Density (bin)";
  yaxis label="Exposure";
run;
/* C */
proc surveyselect data=work.dat_final out=sampled method=srs samprate=0.05 seed=12345;
run;

proc sgplot data=sampled;
  scatter x=Density y=Exposure / transparency=0.6;
  loess x=Density y=Exposure / nomarkers lineattrs=(color=red);
run;

ods graphics off;

title;
