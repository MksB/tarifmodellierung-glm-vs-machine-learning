/*============================================================================*/
/* SECTION 3                                                                  */
/* Feature Encoding                                                           */
/* Corresponds to Python: encode_features()                                   */
/*============================================================================*/

%put NOTE: ============================================================;
%put NOTE: SECTION 3 - FEATURE ENCODING;
%put NOTE: ============================================================;

/*---------------------------------------------------------------------------
Create working copy
---------------------------------------------------------------------------*/

data work.freMTPL_encoded;
    set work.freMTPL_prepared;
run;

/*---------------------------------------------------------------------------
Macro:
Label encode one categorical variable
Equivalent to sklearn.preprocessing.LabelEncoder
---------------------------------------------------------------------------*/

%macro label_encode(var);

    proc sort
        data=work.freMTPL_encoded(keep=&var)
        out=work._levels_&var nodupkey;
        by &var;
    run;

    data work._levels_&var;
        set work._levels_&var;
        &var._ENC = _N_ - 1;
    run;

    proc sql;
        create table work.freMTPL_encoded as
        select
            a.*,
            b.&var._ENC
        from work.freMTPL_encoded as a

        left join work._levels_&var as b
        on a.&var=b.&var;
    quit;

%mend;

/*---------------------------------------------------------------------------
Encode all categorical variables
---------------------------------------------------------------------------*/

%label_encode(VehBrand);
%label_encode(VehGas);
%label_encode(Area);
%label_encode(Region);

/*---------------------------------------------------------------------------
Remove original character variables
---------------------------------------------------------------------------*/

data work.freMTPL_encoded;

    set work.freMTPL_encoded;

    drop
        VehBrand
        VehGas
        Area
        Region;

    rename
        VehBrand_ENC = VehBrand
        VehGas_ENC   = VehGas
        Area_ENC     = Area
        Region_ENC   = Region;

run;

/*---------------------------------------------------------------------------
Verify encoded variables
---------------------------------------------------------------------------*/

proc contents
    data=work.freMTPL_encoded
    varnum;
run;

proc means
    data=work.freMTPL_encoded
    n nmiss min max;
    var
        VehBrand
        VehGas
        Area
        Region;
run;

%put NOTE: Feature encoding completed successfully.;
