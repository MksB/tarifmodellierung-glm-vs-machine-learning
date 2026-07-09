proc sql noprint;
    select 
        count(*)                                                  as N_OBS format=12.,
        sum(case when missing(Exposure) then 1 else 0 end)       as N_MISSING format=12.,
        sum(case when not missing(Exposure) and Exposure <= 0 
                 then 1 else 0 end)                              as N_ZERO_NEG format=12.,
        sum(case when Exposure > 1 then 1 else 0 end)            as N_OVER_ONE format=12.
    into 
        :N_OBS trimmed, 
        :N_MISSING trimmed, 
        :N_ZERO_NEG trimmed, 
        :N_OVER_ONE trimmed
    from work.Data_clean_sevfreq_agg;
quit;

%put NOTE: ================================================;
%put NOTE: Exposure Validation;
%put NOTE: ================================================;
%put NOTE: Total observations      = &N_OBS;
%put NOTE: Missing Exposure        = &N_MISSING;
%put NOTE: Exposure <= 0           = &N_ZERO_NEG;
%put NOTE: Exposure > 1            = &N_OVER_ONE;

/*-----------------------------------------------------------------------
  Stop execution if Exposure contains invalid values
-----------------------------------------------------------------------*/

%macro ValidateExposure;

    %put NOTE: ================================================;
    %put NOTE: Exposure Validation (Input Data);
    %put NOTE: ================================================;

    %put NOTE: Total observations      = &N_OBS;
    %put NOTE: Missing Exposure        = &N_MISSING;
    %put NOTE: Exposure <= 0           = &N_ZERO_NEG;
    %put NOTE: Exposure > 1            = &N_OVER_ONE;

    %if &N_MISSING > 0 %then %do;
        %put ERROR:;
        %put ERROR: Exposure contains missing values.;
        %put ERROR: Offset cannot be constructed.;
        %abort cancel;
    %end;

    %if &N_ZERO_NEG > 0 %then %do;
        %put ERROR:;
        %put ERROR: Exposure contains zero or negative values.;
        %put ERROR: log(Exposure) is undefined.;
        %abort cancel;
    %end;

    %if &N_OVER_ONE > 0 %then %do;
        %put WARNING:;
        %put WARNING: Exposure values greater than 1 detected (&N_OVER_ONE records).;
        %put WARNING: Values will be capped at 1.0.;
    %end;

%mend ValidateExposure;

%ValidateExposure;


data work.dat_final;

    set work.Data_clean_sevfreq_agg;

    /*--------------------------------------------------------------
      Defensive programming:
      Exposure should never exceed one policy year.
    --------------------------------------------------------------*/
    Exposure = min(Exposure, 1);

    /*--------------------------------------------------------------
      Construct Poisson offset with explicit validation
    --------------------------------------------------------------*/
    if missing(Exposure) or Exposure <= 0 then do;
        put 'ERROR: Invalid Exposure after transformation at _N_=' _N_ 
            ' Exposure=' Exposure;
        Log_Exposure = .;
    end;
    else do;
        Log_Exposure = log(Exposure);
    end;

    label 
        Exposure     = "Policy Exposure (capped at 1.0)"
        Log_Exposure = "Log(Exposure) - Poisson GLM Offset";

run;


/*-----------------------------------------------------------------------
  Step 3 : Numerical validation of Log_Exposure
-----------------------------------------------------------------------*/

proc sql noprint;

    select count(*)
        into :N_LOG_MISSING trimmed
    from work.dat_final
    where missing(Log_Exposure);
quit;


%macro ValidateOffset;

    %if &N_LOG_MISSING > 0 %then %do;
        %put ERROR:;
        %put ERROR: LOG_EXPOSURE contains missing values (&N_LOG_MISSING records).;
        %put ERROR: Offset construction failed.;
        %abort cancel;
    %end;
    %else %do;
        %put NOTE: LOG_EXPOSURE validation passed - no missing values.;
    %end;

%mend ValidateOffset;

%ValidateOffset;


/*-----------------------------------------------------------------------
  Step 4 : Exposure summary (on OUTPUT data)
-----------------------------------------------------------------------*/

title1 "Exposure Validation Summary (After Capping)";

proc means
    data=work.dat_final
    n nmiss mean median std min q1 q3 max sum
    maxdec=6;
    var Exposure Log_Exposure;
    format Exposure 8.6 Log_Exposure 10.6;
run;

title;


/*-----------------------------------------------------------------------
  Step 5 : Exposure distribution analysis
-----------------------------------------------------------------------*/

title1 "Exposure Distribution";

proc freq data=work.dat_final;
    tables Exposure / nocol nopercent missing;
    format Exposure 8.4;
run;

title;


/*-----------------------------------------------------------------------
  Step 6 : Claim frequency sanity check
-----------------------------------------------------------------------*/

/* Prüfe ob ClaimNb oder ähnliche Variable existiert */
%let CLAIM_VAR = ;

proc sql noprint;
    select name into :CLAIM_VAR trimmed
    from dictionary.columns
    where libname = 'WORK'
      and memname = 'DAT_FINAL'
      and upcase(name) in ('CLAIMNB', 'CLAIM_COUNT', 'NBRCLAIM', 
                           'NBCLAIM', 'NB_CLAIM', 'NCLAIMS', 'CLAIMS');
quit;

%put NOTE: Claim variable detected: >&CLAIM_VAR<;


%macro FrequencyCheck;

    %if %length(&CLAIM_VAR) > 0 %then %do;
    
        title1 "Claim Frequency Sanity Check";
        
        proc sql;
            select 
                count(*) as N_Obs format=comma12. label='Observations',
                sum(&CLAIM_VAR) as Total_Claims format=comma12. label='Total Claims',
                sum(Exposure) as Total_Exposure format=12.4 label='Total Exposure',
                calculated Total_Claims / calculated Total_Exposure 
                    as Overall_Frequency format=8.6 label='Overall Frequency'
            from work.dat_final;
        quit;
        
        title;
    
    %end;
    %else %do;
    
        %put NOTE: ============================================;
        %put NOTE: No claim count variable found in dataset.;
        %put NOTE: Skipping frequency sanity check.;
        %put NOTE: Expected variable names: CLAIMNB, CLAIM_COUNT,;
        %put NOTE:   NBRCLAIM, NBCLAIM, NB_CLAIM, NCLAIMS, CLAIMS;
        %put NOTE: ============================================;
    
    %end;

%mend FrequencyCheck;

%FrequencyCheck;
