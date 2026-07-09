/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Data Cleaning & Exposure Analysis
* Section  : 1 - Data Preparation and Offset Construction
*
* Purpose:
*   - Validate the Exposure variable
*   - Ensure actuarial assumptions for Poisson GLMs are satisfied
*   - Construct log(Exposure) as the GLM offset
*   - Perform numerical quality checks
*
* Input :
*   WORK.data
*
* Output:
*   WORK.dat_final
*
* Notes:
*   The Poisson GLM models
*
*      E(ClaimNb) = lambda x Exposure
*
*   Therefore
*
*      log(E(ClaimNb))
*         = log(lambda) + log(Exposure)
*
*   The variable LOG_EXPOSURE is later used as
*
*      OFFSET=LOG_EXPOSURE
*
*   in PROC GENMOD.
*
* Revision Log:
*   - Step 1: N_ZERO_NEG / N_OVER_ONE now explicitly exclude missing
*     Exposure values (SAS ranks missing below every non-missing
*     number, so "Exposure <= 0" alone also counted missing values)
*   - Step 1: four separate COUNT(*) passes replaced by a single
*     PROC SQL pass using conditional SUM() aggregation
**************************************************************************/
options mprint mlogic symbolgen;

/*-----------------------------------------------------------------------
  Step 1 : Basic validation of Exposure
-----------------------------------------------------------------------*/


proc sql noprint;

    select count(*),
           sum(missing(Exposure)),
           sum(not missing(Exposure) and Exposure <= 0),
           sum(not missing(Exposure) and Exposure > 1)
        into :N_OBS      trimmed,
             :N_MISSING  trimmed,
             :N_ZERO_NEG trimmed,
             :N_OVER_ONE trimmed
    from work.Data;

quit;


/*-----------------------------------------------------------------------
  Stop execution if Exposure contains invalid values
-----------------------------------------------------------------------*/

%macro ValidateExposure;

    %put NOTE: ================================================;
    %put NOTE: Exposure Validation;
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
        %put WARNING: Exposure values greater than 1 detected.;
        %put WARNING: Values will be capped at 1.0.;

    %end;

%mend ValidateExposure;

%ValidateExposure;


/*-----------------------------------------------------------------------
  Step 2 : Build offset variable
-----------------------------------------------------------------------*/

data work.dat_final;

    set work.Data;

    /*--------------------------------------------------------------
      Defensive programming:
      Exposure should never exceed one policy year.
    --------------------------------------------------------------*/

    Exposure=min(Exposure,1);

    /*--------------------------------------------------------------
      Construct Poisson offset
    --------------------------------------------------------------*/

    Log_Exposure=log(Exposure);

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
        %put ERROR: LOG_EXPOSURE contains missing values.;
        %put ERROR: Offset construction failed.;
        %abort cancel;

    %end;

%mend ValidateOffset;

%ValidateOffset;


/*-----------------------------------------------------------------------
  Step 4 : Exposure summary
-----------------------------------------------------------------------*/

title1 "Exposure Validation Summary";

proc means
    data=work.dat_final
    n
    nmiss
    mean
    median
    std
    min
    q1
    q3
    max
    sum
    maxdec=6;
    var Exposure Log_Exposure;
run;


/*-----------------------------------------------------------------------
  Step 5 : Frequency table
-----------------------------------------------------------------------*/

proc freq data=work.dat_final;

    tables Exposure / missing;

    where Exposure=1;

run;


/*-----------------------------------------------------------------------
  Step 6 : Final confirmation
-----------------------------------------------------------------------*/

%put NOTE:;
%put NOTE: ================================================;
%put NOTE: Offset construction completed successfully.;
%put NOTE: Dataset created : WORK.DAT_FINAL;
%put NOTE: Offset variable : LOG_EXPOSURE;
%put NOTE: Dataset is ready for PROC GENMOD.;
%put NOTE: ================================================;

title;
