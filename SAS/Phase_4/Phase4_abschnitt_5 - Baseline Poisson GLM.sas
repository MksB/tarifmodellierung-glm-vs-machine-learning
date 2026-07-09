/*============================================================================*/
/* SECTION 5                                                                  */
/* Baseline Poisson GLM                                                       */
/* Corresponds to Python:                                                     */
/*   - fit_poisson_glm()                                                      */
/*   - extract_glm_coefficients()                                             */
/*============================================================================*/

%put NOTE: ============================================================;
%put NOTE: SECTION 5 - BASELINE POISSON GLM;
%put NOTE: ============================================================;

/*---------------------------------------------------------------------------
Fit Poisson GLM

Python equivalent:

Pipeline(
    StandardScaler(),
    PoissonRegressor(
        alpha=1e-3,
        max_iter=500
    )
)

Target      : ClaimNb
Offset      : log(Exposure)
Link        : Log
Distribution: Poisson
---------------------------------------------------------------------------*/

data work.train_glm;

    set work.train_data;

    /* Offset variable */
    LogExposure = log(Exposure);

run;

proc genmod
    data=work.train_glm;

    class
        VehBrand
        VehGas
        Area
        Region;

    model ClaimNb =
            VehPower
            VehAge
            DrivAge
            BonusMalus
            Density
            VehBrand
            VehGas
            Area
            Region
            LogDensity
            BonusMalusCapped
        /
        dist=poisson
        link=log
        offset=LogExposure
        type3;

    ods output
        ParameterEstimates = work.GLM_ParameterEstimates
        Type3              = work.GLM_Type3;

run;

/*---------------------------------------------------------------------------
Extract GLM coefficients

Equivalent to Python:

coef_
abs(coef_)
direction
---------------------------------------------------------------------------*/

data work.GLM_Coefficients;

    set work.GLM_ParameterEstimates;

    length
        Feature $50
        Direction $20;

    Feature = Parameter;

    GLM_Coef = Estimate;

    Abs_Coef = abs(GLM_Coef);

    if GLM_Coef > 0 then
        Direction = "Positive ?";
    else if GLM_Coef < 0 then
        Direction = "Negative ?";
    else
        Direction = "Neutral";

    keep
        Feature
        GLM_Coef
        Abs_Coef
        Direction
        StdErr
        GLM_Coef
        ProbChiSq;

run;

/*---------------------------------------------------------------------------
Sort by absolute coefficient
Equivalent to:

sort_values(
    "Abs_Coef",
    ascending=False
)
---------------------------------------------------------------------------*/

proc sort
    data=work.GLM_Coefficients;
    by descending Abs_Coef;
run;

/*---------------------------------------------------------------------------
Display coefficient table
---------------------------------------------------------------------------*/

title "Baseline Poisson GLM - Coefficient Summary";

proc print
    data=work.GLM_Coefficients
    label noobs;

    var
        Feature
        GLM_Coef
        Abs_Coef
        Direction
        StdErr
        GLM_Coef
        ProbChiSq;

    label
        GLM_Coef = "Coefficient"
        Abs_Coef = "|Coefficient|"
        StdErr   = "Std Error"
        GLM_Coef= "Wald Chi-Square"
        ProbChiSq= "p-value";

run;

title;

/*---------------------------------------------------------------------------
Model Fit Statistics
---------------------------------------------------------------------------*/

title "Baseline Poisson GLM - Model Fit";

proc print
    data=work.GLM_Type3
    label noobs;
run;

title;

/*---------------------------------------------------------------------------
Log information
---------------------------------------------------------------------------*/

proc sql noprint;

    select Estimate
    into :GLM_INTERCEPT
    from work.GLM_ParameterEstimates
    where Parameter='Intercept';

quit;

%put NOTE: ----------------------------------------------;
%put NOTE: GLM successfully estimated.;
%put NOTE: GLM Intercept = &GLM_INTERCEPT;
%put NOTE: Coefficients stored in WORK.GLM_Coefficients;
%put NOTE: ----------------------------------------------;
