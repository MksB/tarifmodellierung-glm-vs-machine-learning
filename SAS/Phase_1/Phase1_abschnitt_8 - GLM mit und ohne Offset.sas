/**************************************************************************
* Project  : Actuarial Pricing Model (French MTPL)
* Phase    : 1 - Exposure Analysis
* Section  : 8 - Poisson GLM with and without Offset
*
* Purpose:
*
* Compare two Poisson regression models
*
* Model 1 : without Offset
* Model 2 : with log(Exposure) as Offset
*
* The comparison demonstrates the importance of accounting for
* policy exposure in claim frequency modelling.
*
**************************************************************************/

ods graphics on;


/***********************************************************************
* MODEL 1
* Poisson GLM WITHOUT Offset
***********************************************************************/

title1 "Model 1 - Poisson GLM without Offset";

proc genmod
    data=work.dat_final;

class

    Area
    VehPower
    VehAge
    DrivAge
    BonusMalus
    VehBrand
    VehGas
    Region

    / param=ref ref=first;

model ClaimNb =

      Area
      VehPower
      VehAge
      DrivAge
      BonusMalus
      VehBrand
      VehGas
      Region
      Density

      /

      dist=poisson
      link=log
      type3
      lrci;

ods output

ParameterEstimates = PE_NoOffset
ModelFit           = Fit_NoOffset
Type3              = Type3_NoOffset;

run;



/***********************************************************************
* MODEL 2
* Poisson GLM WITH Offset
***********************************************************************/

title1 "Model 2 - Poisson GLM with Offset";

proc genmod
    data=work.dat_final;

class

    Area
    VehPower
    VehAge
    DrivAge
    BonusMalus
    VehBrand
    VehGas
    Region

    / param=ref ref=first;

model ClaimNb =

      Area
      VehPower
      VehAge
      DrivAge
      BonusMalus
      VehBrand
      VehGas
      Region
      Density

      /

      dist=poisson
      link=log
      offset=Log_Exposure
      type3
      lrci;

ods output

ParameterEstimates = PE_Offset
ModelFit           = Fit_Offset
Type3              = Type3_Offset;

run;



/***********************************************************************
* MODEL COMPARISON
***********************************************************************/

title1 "Comparison of Model Fit Statistics";

data FitComparison;

length Model $25;

set Fit_NoOffset(in=a)
    Fit_Offset(in=b);

if a then Model="Without Offset";
if b then Model="With Offset";

run;


proc print
    data=FitComparison
    noobs
    label;

run;



/***********************************************************************
* PARAMETER COMPARISON
***********************************************************************/

data ParameterComparison;

length Model $20;

set PE_NoOffset(in=a)
    PE_Offset(in=b);

if a then Model="Without Offset";
if b then Model="With Offset";

run;


proc print
    data=ParameterComparison
    label;

run;



/***********************************************************************
* Type III Comparison
***********************************************************************/

data Type3Comparison;

length Model $20;

set Type3_NoOffset(in=a)
    Type3_Offset(in=b);

if a then Model="Without Offset";
if b then Model="With Offset";

run;


proc print
    data=Type3Comparison
    label;

run;

ods graphics off;

title;
