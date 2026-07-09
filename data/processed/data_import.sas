/* 1. Speicherort definieren */
LIBNAME data "SAS\SAS_DATA";

/* 2. Daten einlesen */
PROC IMPORT DATAFILE="data_clean_sev_freq_agg.csv"
    OUT=work.temporaereDaten
    DBMS=CSV
    REPLACE;
RUN;

/* 3. Dauerhaft im zugewiesenen Speicher ablegen */
DATA data.data_clean_sevfreq_agg;
    SET work.temporaereDaten;
RUN;
