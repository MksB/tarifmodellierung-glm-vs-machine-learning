# python_offset_demo.py
# Poisson GLM with offset — Python equivalent of R Listing 5.3
# Reference: Wuethrich & Merz Sections 5.1.5, 5.2.3, 5.2.4

import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf
import warnings
warnings.filterwarnings('ignore')

# --- Load and clean data ---
freq = pd.read_csv('/mnt/user-data/uploads/freMTPL2freq.csv')
freq['Exposure']     = freq['Exposure'].clip(upper=1.0)
freq               = freq[freq['ClaimNb'] <= 5].copy()
freq['log_exposure'] = np.log(freq['Exposure'].clip(lower=1/365))
freq['VehGas']       = freq['VehGas'].astype('category')
freq['Region']       = freq['Region'].astype('category')
freq['AreaGLM']      = freq['Area'].rank(method='dense').astype(int)
freq['BonusMalusGLM'] = freq['BonusMalus'].clip(upper=150)
freq['DensityGLM']   = np.log(freq['Density'])
freq['VehPowerGLM']  = freq['VehPower'].clip(upper=9).astype('category')
freq['VehAgeGLM']    = pd.cut(freq['VehAge'], [0,5,12,101],
                          labels=['0-5','6-12','12+'], include_lowest=True)
freq['DrivAgeGLM']   = pd.cut(freq['DrivAge'],
                          [18,20,25,30,40,50,70,101],
                          labels=['18-20','21-25','26-30','31-40',
                                  '41-50','51-70','71+'],
                          include_lowest=True)

np.random.seed(500)
train_idx = np.random.choice(len(freq), size=int(0.9*len(freq)), replace=False)
test_idx  = np.setdiff1d(np.arange(len(freq)), train_idx)
train, test = freq.iloc[train_idx], freq.iloc[test_idx]

# ===================================================================
# METHOD 1: statsmodels formula API (closest to R glm())
# CORRECT: offset = log(Exposure) via offset= parameter
# ===================================================================
formula = ('ClaimNb ~ C(VehPowerGLM) + C(VehAgeGLM) + C(DrivAgeGLM) +
            BonusMalusGLM + C(VehGas) + DensityGLM + C(Region) + AreaGLM')

fit_with = smf.glm(
    formula = formula,
    data    = train,
    family  = sm.families.Poisson(link=sm.families.links.Log()),
    offset  = train['log_exposure']   # o_i = log(v_i), eq.(5.27)
).fit(disp=False)

mu_train = fit_with.predict(train, offset=train['log_exposure'])
print(f'Balance WITH offset:    {mu_train.sum()/train["ClaimNb"].sum():.8f}  (= 1.0, Corollary 5.7)')

# WRONG: no offset
fit_wrong = smf.glm(
    formula = formula, data = train,
    family  = sm.families.Poisson(link=sm.families.links.Log())
).fit(disp=False)
mu_wrong = fit_wrong.predict(train)
print(f'Balance WITHOUT offset: {mu_wrong.sum()/train["ClaimNb"].sum():.4f}  (biased!)')

# ===================================================================
# METHOD 2: scikit-learn PoissonRegressor
# sklearn has no native offset -> use rate target + sample_weight
# (Noll et al. 2020 approach; equivalent to offset under log-link)
# ===================================================================
from sklearn.linear_model import PoissonRegressor
from sklearn.preprocessing import OneHotEncoder
from sklearn.compose import ColumnTransformer

cat_cols = ['VehPowerGLM','VehAgeGLM','DrivAgeGLM','VehGas','Region']
num_cols = ['BonusMalusGLM','DensityGLM','AreaGLM']
for c in cat_cols:
    train[c] = train[c].astype(str)
    test[c]  = test[c].astype(str)

prep = ColumnTransformer([
    ('cat', OneHotEncoder(drop='first', sparse_output=False,
                          handle_unknown='ignore'), cat_cols),
    ('num', 'passthrough', num_cols)
])
X_tr = prep.fit_transform(train[cat_cols + num_cols])
X_te = prep.transform(test[cat_cols + num_cols])

sk = PoissonRegressor(alpha=0, max_iter=1000)
sk.fit(
    X_tr,
    train['ClaimNb'] / train['Exposure'],  # target = rate Y_i = N_i/v_i
    sample_weight = train['Exposure']       # weight = v_i (eq.5.26)
)
pred_sk = sk.predict(X_tr) * train['Exposure']  # counts = rate * exposure
print(f'Balance sklearn:        {pred_sk.sum()/train["ClaimNb"].sum():.8f}')

# For prediction on new data: always multiply by test exposure
pred_te_rates  = sk.predict(X_te)               # annual rates
pred_te_counts = pred_te_rates * test['Exposure'] # expected counts

print('Key rule: ALWAYS supply offset at prediction time!')
print('  statsmodels: fit.predict(new_data, offset=new_data[log_exposure])')
print('  sklearn:     pred_counts = model.predict(X_test) * test_exposure')
