/**************************************************************************
 * Projekt      : freMTPL Claim Frequency Modelling
 * Phase        : SHAP Phase 4 Analysis
 * Abschnitt    : 10 – Visualisierungen
 *
 * Beschreibung:
 * Grafische Modellbewertung mittels PROC SGPLOT.
 *
 **************************************************************************/

ods graphics on / reset imagename="Phase4" imagefmt=png;


/**************************************************************************
 * 1. Beobachtet vs. Prognostiziert (Poisson-GLM)
 **************************************************************************/

title1 "Poisson GLM";
title2 "Beobachtete vs. prognostizierte Schadenanzahl";

proc sgplot data=work.GLM_FREQ_TEST_PRED;

    scatter
        x=ClaimNb
        y=PredictedClaimNb
        / transparency=0.30
          markerattrs=(symbol=circlefilled size=7);

    lineparm
        x=0
        y=0
        slope=1
        / lineattrs=(pattern=solid thickness=2);

    xaxis label="Beobachtete Schadenanzahl";
    yaxis label="Prognostizierte Schadenanzahl";

run;


/**************************************************************************
 * 2. Histogramm der Vorhersagen
 **************************************************************************/

title1 "Verteilung der Vorhersagen";

proc sgplot data=work.GLM_FREQ_TEST_PRED;

    histogram PredictedClaimNb
        / nbins=30;

    density PredictedClaimNb;

    xaxis label="Vorhergesagte Schadenanzahl";

run;


/**************************************************************************
 * 3. Residuenanalyse
 **************************************************************************/

title1 "Poisson GLM";
title2 "Pearson-Residuen";

proc sgplot data=work.GLM_FREQ_TRAIN_PRED;

    scatter

        x=PredictedClaimNb

        y=PearsonResidual

        / transparency=.35;

    refline 0
        / axis=y;

    xaxis
        label="Vorhersage";

    yaxis
        label="Pearson-Residuum";

run;


/**************************************************************************
 * 4. Variable Importance
 **************************************************************************/

proc sort
    data=work.GB_FREQ_IMPORTANCE
    out=work.VarImp;

    by descending Importance;

run;


title1 "Gradient Boosting";
title2 "Variable Importance";

proc sgplot
    data=work.VarImp;

    hbarparm

        category=Variable

        response=Importance

        / datalabel;

    xaxis label="Importance";

run;


/**************************************************************************
 * 5. Portfolio-Kalibrierung
 **************************************************************************/

data work.Calibration;

    length Model $25;

    set

        work.GLM_FREQ_BALANCE(in=a)

        work.GB_FREQ_CALIBRATION(in=b)

        work.XGB_PORTFOLIO(in=c);

    if a then Model="Poisson GLM";
    if b then Model="Gradient Boosting";
    if c then Model="XGBoost Ersatz";

run;


title1 "Portfolio-Kalibrierung";

proc sgplot
    data=work.Calibration;

    vbar Model
        / response=CalibrationRatio
          datalabel;

    refline 1
        / axis=y
          lineattrs=(pattern=shortdash);

    yaxis
        label="Calibration Ratio";

run;


/**************************************************************************
 * 6. Modellvergleich
 **************************************************************************/

title1 "Vergleich der Modellgüte";

proc sgplot
    data=work.MODEL_COMPARISON;

    vbar Model
        / response=RMSE
          groupdisplay=cluster
          datalabel;

    yaxis label="RMSE";

run;


/**************************************************************************
 * 7. MAE Vergleich
 **************************************************************************/

title1 "Vergleich MAE";

proc sgplot
    data=work.MODEL_COMPARISON;

    vbar Model

        / response=MAE

          datalabel;

    yaxis label="MAE";

run;


/**************************************************************************
 * 8. Gini Vergleich
 **************************************************************************/

title1 "Vergleich Gini";

proc sgplot
    data=work.MODEL_COMPARISON;

    vbar Model

        / response=Gini

          datalabel;

    yaxis label="Normalized Gini";

run;


/**************************************************************************
 * 9. Laufzeiten
 **************************************************************************/

title1 "Modelllaufzeiten";

proc sgplot
    data=work.MODEL_COMPARISON;

    vbar Model

        / response=Runtime

          datalabel;

    yaxis
        label="Sekunden";

run;


/**************************************************************************
 * 10. Grafikoptionen zurücksetzen
 **************************************************************************/

title;
footnote;

ods graphics off;
