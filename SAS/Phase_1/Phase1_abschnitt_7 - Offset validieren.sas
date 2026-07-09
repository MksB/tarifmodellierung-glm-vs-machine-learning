/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Data Cleaning & Exposure Analysis
* Section  : 7 - Offset Validation
*
* Purpose:
*   Validate the Exposure variable and the derived offset variable
*   Log_Exposure before GLM estimation.
*
* Input:
*      WORK.DAT_FINAL
*
**************************************************************************/

title1 "Phase 1 - Offset Validation";

/*-----------------------------------------------------------------------
* Validation Summary
*-----------------------------------------------------------------------*/

proc sql noprint;

    select count(*) into :NOBS trimmed
    from work.dat_final;

    select count(*) into :N_EXP_MISS trimmed
    from work.dat_final
    where missing(Exposure);

    select count(*) into :N_EXP_ZERO trimmed
    from work.dat_final
    where Exposure <= 0;

    select count(*) into :N_EXP_GT1 trimmed
    from work.dat_final
    where Exposure > 1;

    select count(*) into :N_LOG_MISS trimmed
    from work.dat_final
    where missing(Log_Exposure);

    select count(*) into :N_LOG_POS trimmed
    from work.dat_final
    where Log_Exposure > 0;

    select count(*) into :N_LOG_ZERO trimmed
    from work.dat_final
    where Exposure ne 1 and Log_Exposure = 0;

    select count(*) into :N_LOG_NEG trimmed
    from work.dat_final
    where Exposure < 1 and Log_Exposure >= 0;

quit;


/*-----------------------------------------------------------------------
* Print Validation Results
*-----------------------------------------------------------------------*/

%put;
%put ============================================================;
%put Offset Validation Report;
%put ============================================================;
%put Total observations                  : &NOBS;
%put Missing Exposure                    : &N_EXP_MISS;
%put Exposure <= 0                       : &N_EXP_ZERO;
%put Exposure > 1                        : &N_EXP_GT1;
%put Missing Log_Exposure                : &N_LOG_MISS;
%put Positive Log_Exposure               : &N_LOG_POS;
%put Exposure<1 but Log_Exposure = 0     : &N_LOG_ZERO;
%put Exposure<1 but Log_Exposure >= 0    : &N_LOG_NEG;
%put ============================================================;


/*-----------------------------------------------------------------------
* Stop Program if Validation Fails
*-----------------------------------------------------------------------*/

%macro CheckOffset;

    %if &N_EXP_MISS > 0 %then %do;
        %put ERROR: Missing values detected in Exposure.;
        %abort cancel;
    %end;

    %if &N_EXP_ZERO > 0 %then %do;
        %put ERROR: Exposure contains values <= 0.;
        %abort cancel;
    %end;

    %if &N_EXP_GT1 > 0 %then %do;
        %put ERROR: Exposure contains values greater than 1.;
        %abort cancel;
    %end;

    %if &N_LOG_MISS > 0 %then %do;
        %put ERROR: Missing values detected in Log_Exposure.;
        %abort cancel;
    %end;

    %if &N_LOG_POS > 0 %then %do;
        %put ERROR: Positive Log_Exposure values detected.;
        %abort cancel;
    %end;

    %if &N_LOG_ZERO > 0 %then %do;
        %put ERROR: Exposure < 1 with Log_Exposure = 0 detected.;
        %abort cancel;
    %end;

    %if &N_LOG_NEG > 0 %then %do;
        %put ERROR: Invalid Log_Exposure values detected.;
        %abort cancel;
    %end;

    %put NOTE:;
    %put NOTE: ***********************************************;
    %put NOTE: Offset validation successfully completed.;
    %put NOTE: Dataset WORK.DAT_FINAL is ready for PROC GENMOD.;
    %put NOTE: ***********************************************;

%mend CheckOffset;

%CheckOffset;


/*-----------------------------------------------------------------------
* Display observations with invalid values (if any)
*-----------------------------------------------------------------------*/

proc print data=work.dat_final;

    where missing(Exposure)
       or Exposure <= 0
       or Exposure > 1
       or missing(Log_Exposure)
       or Log_Exposure > 0;

    var IDpol Exposure Log_Exposure;

    title2 "Invalid Observations (if present)";

run;

title;
