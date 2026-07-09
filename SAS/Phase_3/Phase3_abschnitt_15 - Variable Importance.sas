/**************************************************************************
* Project  : French MTPL Insurance Pricing
* Phase    : 3 - Machine Learning Modelling
* Section  : 3.15 - Variable Importance
*
* Purpose:
*   Extract and analyze variable importance from Gradient Boosting models.
*
* Method:
*   - PROC GRADBOOST with ODS OUTPUT
*   - Frequency & Severity model interpretation
*
* Input:
*      WORK.FREQ_MODEL
*      WORK.SEV_MODEL
*
* Output:
*      WORK.VARIMP_FREQ
*      WORK.VARIMP_SEV
*
**************************************************************************/

title1 "Phase 3 - Machine Learning Modelling";
title2 "Section 3.15 - Variable Importance";

/*-----------------------------------------------------------------------
* Step 1 : Frequency model variable importance
*-----------------------------------------------------------------------*/

ods output VariableImportance = work.VarImp_Freq;

proc gradboost
    inmodel=work.FREQ_Model
    printimportance;

run;

ods output close;


/*-----------------------------------------------------------------------
* Step 2 : Severity model variable importance
*-----------------------------------------------------------------------*/

ods output VariableImportance = work.VarImp_Sev;

proc gradboost
    inmodel=work.SEV_Model
    printimportance;

run;

ods output close;


/*-----------------------------------------------------------------------
* Step 3 : Clean and standardize importance tables
*-----------------------------------------------------------------------*/

data work.VarImp_Freq_Clean;

    set work.VarImp_Freq;

    Model = "FREQUENCY";

run;


data work.VarImp_Sev_Clean;

    set work.VarImp_Sev;

    Model = "SEVERITY";

run;


/*-----------------------------------------------------------------------
* Step 4 : Combine both models
*-----------------------------------------------------------------------*/

data work.VarImp_All;

    set work.VarImp_Freq_Clean
        work.VarImp_Sev_Clean;

run;


/*-----------------------------------------------------------------------
* Step 5 : Sort by importance (descending)
*-----------------------------------------------------------------------*/

proc sort
    data=work.VarImp_All;

    by descending Importance;

run;


/*-----------------------------------------------------------------------
* Step 6 : Top variable importance summary
*-----------------------------------------------------------------------*/

title3 "Top 20 Most Important Variables";

proc print
    data=work.VarImp_All(obs=20)
    noobs;

run;


/*-----------------------------------------------------------------------
* Step 7 : Optional aggregation by variable
*-----------------------------------------------------------------------*/

proc sql;

    create table work.VarImp_Summary as
    select
        Variable,
        sum(Importance) as Total_Importance
    from work.VarImp_All
    group by Variable
    order by calculated Total_Importance desc;

quit;


/*-----------------------------------------------------------------------
* Step 8 : Completion log
*-----------------------------------------------------------------------*/

data _null_;

    set work.VarImp_All end=eof;

    if eof then do;

        put "========================================================";
        put " VARIABLE IMPORTANCE EXTRACTION COMPLETED";
        put "========================================================";
        put " Frequency Model Importance extracted";
        put " Severity Model Importance extracted";
        put " Combined ranking created in WORK.VARIMP_ALL";
        put "========================================================";
    end;

run;

title;
