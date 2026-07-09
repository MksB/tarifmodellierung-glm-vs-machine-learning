/*============================================================================*/
/* SECTION 4                                                                  */
/* Train / Test Split                                                         */
/* Corresponds to Python: build_matrices()                                    */
/*============================================================================*/

%put NOTE: ============================================================;
%put NOTE: SECTION 4 - TRAIN / TEST SPLIT;
%put NOTE: ============================================================;

/*---------------------------------------------------------------------------
Model features
Equivalent to Python MODEL_FEATURES
---------------------------------------------------------------------------*/

%let MODEL_FEATURES =
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
        BonusMalusCapped;

/*---------------------------------------------------------------------------
Create modelling dataset
Equivalent to:

X = df[MODEL_FEATURES]
y = ClaimNb
w = Exposure
---------------------------------------------------------------------------*/

data work.freMTPL_model;

    retain
        &MODEL_FEATURES
        ClaimNb
        Exposure;

    set work.freMTPL_encoded(
        keep=
            &MODEL_FEATURES
            ClaimNb
            Exposure
    );

run;

/*---------------------------------------------------------------------------
Create reproducible Train/Test split
Equivalent to:

train_test_split(
    test_size = 0.20,
    random_state = 42
)
---------------------------------------------------------------------------*/

proc surveyselect
    data      = work.freMTPL_model
    out       = work.freMTPL_split
    seed      = 42
    samprate  = 0.80
    method    = SRS
    outall;
run;

/*---------------------------------------------------------------------------
Separate Training and Test datasets
---------------------------------------------------------------------------*/

data
    work.train_data
    work.test_data;

    set work.freMTPL_split;

    if Selected then
        output work.train_data;
    else
        output work.test_data;

run;

/*---------------------------------------------------------------------------
Equivalent objects to Python

X_tr
X_te
y_tr
y_te
w_tr
w_te
---------------------------------------------------------------------------*/

data work.X_train;
    set work.train_data;
    keep &MODEL_FEATURES;
run;

data work.y_train;
    set work.train_data;
    keep ClaimNb;
run;

data work.w_train;
    set work.train_data;
    keep Exposure;
run;

data work.X_test;
    set work.test_data;
    keep &MODEL_FEATURES;
run;

data work.y_test;
    set work.test_data;
    keep ClaimNb;
run;

data work.w_test;
    set work.test_data;
    keep Exposure;
run;

/*---------------------------------------------------------------------------
Log dataset sizes
Equivalent to:

log.info(
"Train size: %d | Test size: %d"
)
---------------------------------------------------------------------------*/

proc sql noprint;

    select count(*)
        into :NTRAIN
    from work.train_data;

    select count(*)
        into :NTEST
    from work.test_data;

quit;

%put NOTE: ----------------------------------------------;
%put NOTE: Training observations = &NTRAIN;
%put NOTE: Test observations     = &NTEST;
%put NOTE: Total observations    = %eval(&NTRAIN + &NTEST);
%put NOTE: Train/Test split completed successfully.;
%put NOTE: ----------------------------------------------;

/*---------------------------------------------------------------------------
Optional validation
---------------------------------------------------------------------------*/

proc means
    data=work.train_data
    n mean min max;
    var Exposure ClaimNb;
run;

proc means
    data=work.test_data
    n mean min max;
    var Exposure ClaimNb;
run;
