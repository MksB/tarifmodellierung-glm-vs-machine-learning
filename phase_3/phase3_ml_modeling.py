"""
Phase 3 – ML Modeling: French MTPL Insurance Claims
=====================================================
Targets
  • ClaimNb    – claim frequency  → LightGBM Poisson + XGBoost Poisson
  • ClaimTotal – claim severity   → LightGBM Gamma   + XGBoost Gamma
                                    (on the sub-set where ClaimNb > 0)

Pipeline
  1. Data loading & sanity checks
  2. Feature engineering  (numerical transforms, binning, encodings)
  3. Monotonicity constraints  (regulatory-critical features)
  4. Stratified 5-fold cross-validation wrapper
  5. Bayesian hyper-parameter search via Optuna
  6. Final model fitting on full training set
  7. Serialisation  (pickle for all models)
  8. Unit tests (run with  python phase3_ml_modeling.py --test)

Requirements
  lightgbm>=4.0, xgboost>=2.0, optuna>=3.0,
  scikit-learn>=1.3, pandas>=2.0, numpy>=1.24
"""

# ---------------------------------------------------------------------------
# Imports
# ---------------------------------------------------------------------------
from __future__ import annotations

import argparse
import logging
import os
import pickle
import sys
import warnings
from pathlib import Path
from typing import Any

import numpy as np
import optuna
import pandas as pd
from lightgbm import LGBMModel, LGBMRegressor, early_stopping, log_evaluation
from sklearn.model_selection import StratifiedKFold
from sklearn.preprocessing import LabelEncoder
from xgboost import XGBRegressor

warnings.filterwarnings("ignore", category=UserWarning)
optuna.logging.set_verbosity(optuna.logging.WARNING)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

# Paths
DATA_PATH = Path("/mnt/project/freMTPLfreq_sev_data_1000.csv")
MODEL_DIR = Path("/mnt/user-data/outputs/models")
MODEL_DIR.mkdir(parents=True, exist_ok=True)


# Reproducibility
SEED = 42
N_SPLITS = 5          # stratified K-fold
N_TRIALS = 30         # Optuna trials per model (increase for production)
EARLY_STOP = 50       # LightGBM early-stopping rounds

# ---------------------------------------------------------------------------
# 1. Data loading and validation
# ---------------------------------------------------------------------------

def load_data(path: Path) -> pd.DataFrame:
    """Load CSV, validate schema, drop rows with non-positive Exposure."""
    df = pd.read_csv(path)

    required = {
        "Exposure", "VehPower", "VehAge", "DrivAge",
        "BonusMalus", "VehBrand", "VehGas", "Area",
        "Density", "Region", "ClaimTotal", "ClaimNb",
    }
    missing_cols = required - set(df.columns)
    if missing_cols:
        raise ValueError(f"Missing columns: {missing_cols}")

    # Drop degenerate rows
    n_before = len(df)
    df = df[df["Exposure"] > 0].copy()
    log.info("Loaded %d rows (%d dropped for Exposure<=0)", len(df), n_before - len(df))

    assert (df["ClaimNb"] >= 0).all(), "Negative ClaimNb detected"
    assert (df["ClaimTotal"] >= 0).all(), "Negative ClaimTotal detected"
    assert (df["Exposure"] > 0).all(),  "Non-positive Exposure after filter"
    return df


# ---------------------------------------------------------------------------
# 2. Feature engineering
# ---------------------------------------------------------------------------

# Categorical columns that need label-encoding for tree models
CATEGORICALS = ["VehBrand", "VehGas", "Area", "Region"]

# Monotonicity constraints – direction sign for LightGBM / XGBoost:
#   +1 = feature must produce non-decreasing predictions
#   -1 = non-increasing
#    0 = unconstrained
#
# Regulatory rationale (EU / EIOPA guidelines):
#   • BonusMalus  ↑ → higher risk → claim frequency must be non-decreasing (+1)
#   • DrivAge     ↑ → older driver → risk generally decreases then plateaus (-1 / 0)
#     We use 0 here because the relationship is non-monotone (young & very old = risky).
#   • VehAge      ↑ → older vehicle → lower value, lower claim severity (-1)
MONOTONE_CONSTRAINTS_FREQ: dict[str, int] = {
    "BonusMalus": 1,   # higher bonus-malus ↑ frequency
    "DrivAge":    0,   # U-shaped – cannot enforce global direction
    "VehAge":     0,   # mixed effect on frequency
    "VehPower":   1,   # more powerful car ↑ frequency
}

MONOTONE_CONSTRAINTS_SEV: dict[str, int] = {
    "BonusMalus": 1,   # proxy for driver risk – also affects severity
    "VehAge":    -1,   # older vehicle → lower repair/replacement cost
    "VehPower":   1,   # more powerful car → higher repair cost
    "DrivAge":    0,
}


class FeatureEngineer:
    """
    Stateful transformer: fit on train, apply to train/test.
    Stores label encoders to prevent data leakage.
    """

    def __init__(self) -> None:
        self.label_encoders: dict[str, LabelEncoder] = {}
        self.fitted = False

    # ------------------------------------------------------------------
    def fit_transform(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        df = self._numerical_transforms(df)
        df = self._binning(df)
        df = self._encode_categoricals(df, fit=True)
        self.fitted = True
        return df

    def transform(self, df: pd.DataFrame) -> pd.DataFrame:
        if not self.fitted:
            raise RuntimeError("Call fit_transform first.")
        df = df.copy()
        df = self._numerical_transforms(df)
        df = self._binning(df)
        df = self._encode_categoricals(df, fit=False)
        return df

    # ------------------------------------------------------------------
    @staticmethod
    def _numerical_transforms(df: pd.DataFrame) -> pd.DataFrame:
        """Log and ratio transforms that linearise skewed distributions."""

        # Log-density: Density is highly right-skewed
        df["log_Density"] = np.log1p(df["Density"])

        # Exposure-adjusted rate proxy (for information; offset is used in model)
        df["log_Exposure"] = np.log(df["Exposure"].clip(lower=1e-6))

        # BonusMalus squared term – captures non-linear risk acceleration
        df["BonusMalus_sq"] = df["BonusMalus"] ** 2

        # Driver age inverse (young drivers have very high risk)
        df["inv_DrivAge"] = 1.0 / df["DrivAge"].clip(lower=18)

        return df

    @staticmethod
    def _binning(df: pd.DataFrame) -> pd.DataFrame:
        """Coarse-class bins for regulatory reporting / monotonicity checkpoints."""

        # Vehicle age band: new / mid / old
        df["VehAge_band"] = pd.cut(
            df["VehAge"],
            bins=[-1, 3, 10, 200],
            labels=[0, 1, 2],
        ).astype(int)

        # Driver age band: young / middle / senior
        df["DrivAge_band"] = pd.cut(
            df["DrivAge"],
            bins=[0, 25, 55, 120],
            labels=[0, 1, 2],
        ).astype(int)

        # Bonus-Malus band: bonus / neutral / malus
        df["BonusMalus_band"] = pd.cut(
            df["BonusMalus"],
            bins=[0, 95, 105, 500],
            labels=[0, 1, 2],
        ).astype(int)

        return df

    def _encode_categoricals(self, df: pd.DataFrame, fit: bool) -> pd.DataFrame:
        for col in CATEGORICALS:
            if col not in df.columns:
                continue
            le = LabelEncoder()
            if fit:
                df[col] = le.fit_transform(df[col].astype(str))
                self.label_encoders[col] = le
            else:
                known = set(self.label_encoders[col].classes_)
                df[col] = df[col].astype(str).apply(
                    lambda x: x if x in known else "__unknown__"
                )
                # add unseen class if needed
                if "__unknown__" not in known:
                    self.label_encoders[col].classes_ = np.append(
                        self.label_encoders[col].classes_, "__unknown__"
                    )
                df[col] = self.label_encoders[col].transform(df[col])
        return df


# ---------------------------------------------------------------------------
# Helper: build monotonicity constraint vector for LightGBM / XGBoost
# ---------------------------------------------------------------------------

def build_monotone_constraint_vector(
    feature_names: list[str],
    constraint_map: dict[str, int],
) -> list[int]:
    """Return per-feature constraint list aligned with feature_names."""
    return [constraint_map.get(f, 0) for f in feature_names]


# ---------------------------------------------------------------------------
# 3. Feature columns (after engineering)
# ---------------------------------------------------------------------------

BASE_FEATURES = [
    "VehPower", "VehAge", "DrivAge", "BonusMalus",
    "VehBrand", "VehGas", "Area", "Density", "Region",
    # Engineered
    "log_Density", "BonusMalus_sq", "inv_DrivAge",
    "VehAge_band", "DrivAge_band", "BonusMalus_band",
]

# Offset column (log-exposure) is passed separately to the objective
OFFSET_COL = "log_Exposure"


# ---------------------------------------------------------------------------
# 4. Stratified 5-fold cross-validation
# ---------------------------------------------------------------------------

def stratified_kfold_indices(
    y: np.ndarray,
    n_splits: int = N_SPLITS,
    seed: int = SEED,
) -> list[tuple[np.ndarray, np.ndarray]]:
    """
    Return (train_idx, val_idx) pairs.
    Stratification key: ClaimNb clipped at 2 so rare events stay balanced.
    """
    strat_key = np.clip(y.astype(int), 0, 2).astype(str)
    skf = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=seed)
    return list(skf.split(np.zeros(len(y)), strat_key))


def cross_val_score_lgbm(
    params: dict[str, Any],
    X: pd.DataFrame,
    y: np.ndarray,
    offset: np.ndarray,
    objective: str,          # "poisson" or "gamma"
    folds: list[tuple],
    metric: str,             # "poisson" | "gamma" | "rmse"
) -> float:
    """
    Run stratified K-fold CV with LightGBM and return mean validation loss.
    Lower is better.
    """
    import lightgbm as lgb

    scores = []
    for train_idx, val_idx in folds:
        X_tr, X_val = X.iloc[train_idx], X.iloc[val_idx]
        y_tr, y_val = y[train_idx], y[val_idx]
        off_tr, off_val = offset[train_idx], offset[val_idx]

        dtrain = lgb.Dataset(X_tr, label=y_tr, init_score=off_tr)
        dval   = lgb.Dataset(X_val, label=y_val, init_score=off_val,
                             reference=dtrain)

        booster = lgb.train(
            {**params, "objective": objective, "metric": metric,
             "verbosity": -1, "seed": SEED},
            dtrain,
            num_boost_round=500,
            valid_sets=[dval],
            callbacks=[early_stopping(EARLY_STOP, verbose=False),
                       log_evaluation(-1)],
        )
        # Best validation score
        scores.append(booster.best_score["valid_0"][metric])

    return float(np.mean(scores))


def cross_val_score_xgb(
    params: dict[str, Any],
    X: pd.DataFrame,
    y: np.ndarray,
    offset: np.ndarray,
    objective: str,          # "count:poisson" or "reg:gamma"
    folds: list[tuple],
) -> float:
    """
    Run stratified K-fold CV with XGBoost and return mean validation RMSE.
    """
    import xgboost as xgb

    scores = []
    for train_idx, val_idx in folds:
        X_tr, X_val = X.iloc[train_idx], X.iloc[val_idx]
        y_tr, y_val = y[train_idx], y[val_idx]
        off_tr, off_val = offset[train_idx], offset[val_idx]

        dtrain = xgb.DMatrix(X_tr, label=y_tr, base_margin=off_tr,
                             feature_names=list(X.columns))
        dval   = xgb.DMatrix(X_val, label=y_val, base_margin=off_val,
                             feature_names=list(X.columns))

        booster = xgb.train(
            {**params, "objective": objective, "seed": SEED,
             "eval_metric": "rmse", "verbosity": 0},
            dtrain,
            num_boost_round=500,
            evals=[(dval, "val")],
            early_stopping_rounds=EARLY_STOP,
            verbose_eval=False,
        )
        scores.append(booster.best_score)

    return float(np.mean(scores))


# ---------------------------------------------------------------------------
# 5. Bayesian hyper-parameter search via Optuna
# ---------------------------------------------------------------------------

def tune_lgbm(
    X: pd.DataFrame,
    y: np.ndarray,
    offset: np.ndarray,
    objective: str,
    metric: str,
    folds: list[tuple],
    monotone: list[int],
    n_trials: int = N_TRIALS,
    model_tag: str = "",
) -> dict[str, Any]:
    """
    Bayesian optimisation for LightGBM using Optuna TPE sampler.
    Returns best hyper-parameter dictionary.
    """

    def objective_fn(trial: optuna.Trial) -> float:
        params = {
            "learning_rate":      trial.suggest_float("learning_rate", 0.01, 0.2, log=True),
            "num_leaves":         trial.suggest_int("num_leaves", 20, 150),
            "max_depth":          trial.suggest_int("max_depth", 3, 10),
            "min_child_samples":  trial.suggest_int("min_child_samples", 10, 100),
            "subsample":          trial.suggest_float("subsample", 0.5, 1.0),
            "colsample_bytree":   trial.suggest_float("colsample_bytree", 0.5, 1.0),
            "reg_alpha":          trial.suggest_float("reg_alpha", 1e-4, 10.0, log=True),
            "reg_lambda":         trial.suggest_float("reg_lambda", 1e-4, 10.0, log=True),
            "monotone_constraints": monotone,
        }
        return cross_val_score_lgbm(params, X, y, offset, objective, folds, metric)

    sampler = optuna.samplers.TPESampler(seed=SEED)
    study = optuna.create_study(direction="minimize", sampler=sampler)
    study.optimize(objective_fn, n_trials=n_trials, show_progress_bar=False)

    log.info("[%s] Best Optuna score=%.6f | params=%s",
             model_tag, study.best_value, study.best_params)
    return study.best_params


def tune_xgb(
    X: pd.DataFrame,
    y: np.ndarray,
    offset: np.ndarray,
    objective: str,
    folds: list[tuple],
    monotone: list[int],
    n_trials: int = N_TRIALS,
    model_tag: str = "",
) -> dict[str, Any]:
    """Bayesian optimisation for XGBoost using Optuna."""

    feature_names = list(X.columns)

    def objective_fn(trial: optuna.Trial) -> float:
        params = {
            "learning_rate":        trial.suggest_float("learning_rate", 0.01, 0.2, log=True),
            "max_depth":            trial.suggest_int("max_depth", 3, 10),
            "min_child_weight":     trial.suggest_float("min_child_weight", 1.0, 20.0),
            "subsample":            trial.suggest_float("subsample", 0.5, 1.0),
            "colsample_bytree":     trial.suggest_float("colsample_bytree", 0.5, 1.0),
            "reg_alpha":            trial.suggest_float("reg_alpha", 1e-4, 10.0, log=True),
            "reg_lambda":           trial.suggest_float("reg_lambda", 1e-4, 10.0, log=True),
            # Monotone constraints passed as dict for XGBoost
            "monotone_constraints": {
                name: val
                for name, val in zip(feature_names, monotone)
                if val != 0
            },
        }
        return cross_val_score_xgb(params, X, y, offset, objective, folds)

    sampler = optuna.samplers.TPESampler(seed=SEED)
    study = optuna.create_study(direction="minimize", sampler=sampler)
    study.optimize(objective_fn, n_trials=n_trials, show_progress_bar=False)

    log.info("[%s] Best Optuna score=%.6f | params=%s",
             model_tag, study.best_value, study.best_params)
    return study.best_params


# ---------------------------------------------------------------------------
# 6. Final model training
# ---------------------------------------------------------------------------

def train_lgbm_final(
    params: dict[str, Any],
    X: pd.DataFrame,
    y: np.ndarray,
    offset: np.ndarray,
    objective: str,
    metric: str,
    monotone: list[int],
) -> Any:
    """Train LightGBM on the full dataset with the tuned parameters."""
    import lightgbm as lgb

    dtrain = lgb.Dataset(X, label=y, init_score=offset)

    final_params = {
        **params,
        "objective": objective,
        "metric": metric,
        "verbosity": -1,
        "seed": SEED,
        "monotone_constraints": monotone,
    }

    booster = lgb.train(
        final_params,
        dtrain,
        num_boost_round=500,
        callbacks=[log_evaluation(-1)],
    )
    return booster


def train_xgb_final(
    params: dict[str, Any],
    X: pd.DataFrame,
    y: np.ndarray,
    offset: np.ndarray,
    objective: str,
    monotone: list[int],
) -> Any:
    """Train XGBoost on the full dataset with the tuned parameters."""
    import xgboost as xgb

    feature_names = list(X.columns)
    dtrain = xgb.DMatrix(X, label=y, base_margin=offset,
                         feature_names=feature_names)

    final_params = {
        **params,
        "objective": objective,
        "eval_metric": "rmse",
        "verbosity": 0,
        "seed": SEED,
        "monotone_constraints": {
            name: val
            for name, val in zip(feature_names, monotone)
            if val != 0
        },
    }

    booster = xgb.train(final_params, dtrain, num_boost_round=200)
    return booster


# ---------------------------------------------------------------------------
# 7. Serialisation
# ---------------------------------------------------------------------------

def save_model(obj: Any, name: str) -> Path:
    """Persist any Python object with pickle and return the path."""
    path = MODEL_DIR / f"{name}.pkl"
    with open(path, "wb") as fh:
        pickle.dump(obj, fh, protocol=pickle.HIGHEST_PROTOCOL)
    log.info("Saved → %s", path)
    return path


def load_model(name: str) -> Any:
    """Load a pickled model by name."""
    path = MODEL_DIR / f"{name}.pkl"
    with open(path, "rb") as fh:
        return pickle.load(fh)


# ---------------------------------------------------------------------------
# 8. Main pipeline
# ---------------------------------------------------------------------------

def run_pipeline(data_path: Path = DATA_PATH, n_trials: int = N_TRIALS) -> dict[str, Any]:
    """
    Full Phase-3 pipeline.
    Returns dict of trained models and metadata.
    """

    # ── 1. Load ──────────────────────────────────────────────────────────
    log.info("=== Phase 3 ML Modeling ===")
    df = load_data(data_path)

    # ── 2. Feature engineering ───────────────────────────────────────────
    fe = FeatureEngineer()
    df_eng = fe.fit_transform(df)

    # Frequency dataset: all rows
    X_freq = df_eng[BASE_FEATURES].copy()
    y_freq = df_eng["ClaimNb"].values.astype(float)
    offset_freq = df_eng[OFFSET_COL].values  # log-exposure

    # Severity dataset: only rows with at least one claim
    sev_mask = df_eng["ClaimNb"] > 0
    X_sev    = df_eng.loc[sev_mask, BASE_FEATURES].copy()
    # Average cost per claim (Gamma target must be > 0)
    y_sev    = (df_eng.loc[sev_mask, "ClaimTotal"] /
                df_eng.loc[sev_mask, "ClaimNb"]).values.astype(float)
    offset_sev = np.zeros(sev_mask.sum())  # no exposure offset for severity

    log.info("Frequency rows: %d | Severity rows: %d", len(X_freq), len(X_sev))

    # ── 3. Monotonicity constraints ──────────────────────────────────────
    mono_freq = build_monotone_constraint_vector(BASE_FEATURES, MONOTONE_CONSTRAINTS_FREQ)
    mono_sev  = build_monotone_constraint_vector(BASE_FEATURES, MONOTONE_CONSTRAINTS_SEV)

    log.info("Monotone FREQ: %s", dict(zip(BASE_FEATURES, mono_freq)))
    log.info("Monotone SEV:  %s", dict(zip(BASE_FEATURES, mono_sev)))

    # ── 4. Cross-validation folds ────────────────────────────────────────
    folds_freq = stratified_kfold_indices(y_freq, n_splits=N_SPLITS)
    # For severity, stratify on clipped ClaimNb (always 1 or 2 here)
    folds_sev  = stratified_kfold_indices(
        df_eng.loc[sev_mask, "ClaimNb"].values, n_splits=min(N_SPLITS, sev_mask.sum() // 2)
    )

    # ── 5. Bayesian hyper-parameter search ───────────────────────────────

    # LightGBM – Frequency (Poisson)
    log.info("Tuning LightGBM Frequency (Poisson)...")
    best_params_lgbm_freq = tune_lgbm(
        X_freq, y_freq, offset_freq,
        objective="poisson", metric="poisson",
        folds=folds_freq, monotone=mono_freq,
        n_trials=n_trials, model_tag="LGB-Freq",
    )

    # LightGBM – Severity (Gamma)
    log.info("Tuning LightGBM Severity (Gamma)...")
    best_params_lgbm_sev = tune_lgbm(
        X_sev, y_sev, offset_sev,
        objective="gamma", metric="gamma",
        folds=folds_sev, monotone=mono_sev,
        n_trials=n_trials, model_tag="LGB-Sev",
    )

    # XGBoost – Frequency (count:poisson)
    log.info("Tuning XGBoost Frequency (count:poisson)...")
    best_params_xgb_freq = tune_xgb(
        X_freq, y_freq, offset_freq,
        objective="count:poisson",
        folds=folds_freq, monotone=mono_freq,
        n_trials=n_trials, model_tag="XGB-Freq",
    )

    # XGBoost – Severity (reg:gamma)
    log.info("Tuning XGBoost Severity (reg:gamma)...")
    best_params_xgb_sev = tune_xgb(
        X_sev, y_sev, offset_sev,
        objective="reg:gamma",
        folds=folds_sev, monotone=mono_sev,
        n_trials=n_trials, model_tag="XGB-Sev",
    )

    # ── 6. Final training ────────────────────────────────────────────────
    log.info("Training final models on full data...")

    lgbm_freq = train_lgbm_final(
        best_params_lgbm_freq, X_freq, y_freq, offset_freq,
        objective="poisson", metric="poisson", monotone=mono_freq,
    )
    lgbm_sev = train_lgbm_final(
        best_params_lgbm_sev, X_sev, y_sev, offset_sev,
        objective="gamma", metric="gamma", monotone=mono_sev,
    )
    xgb_freq = train_xgb_final(
        best_params_xgb_freq, X_freq, y_freq, offset_freq,
        objective="count:poisson", monotone=mono_freq,
    )
    xgb_sev = train_xgb_final(
        best_params_xgb_sev, X_sev, y_sev, offset_sev,
        objective="reg:gamma", monotone=mono_sev,
    )

    # ── 7. Serialise ─────────────────────────────────────────────────────
    save_model(lgbm_freq,             "lgbm_frequency_poisson")
    save_model(lgbm_sev,              "lgbm_severity_gamma")
    save_model(xgb_freq,              "xgb_frequency_poisson")
    save_model(xgb_sev,               "xgb_severity_gamma")
    save_model(fe,                    "feature_engineer")
    save_model(best_params_lgbm_freq, "best_params_lgbm_freq")
    save_model(best_params_lgbm_sev,  "best_params_lgbm_sev")
    save_model(best_params_xgb_freq,  "best_params_xgb_freq")
    save_model(best_params_xgb_sev,   "best_params_xgb_sev")
    save_model({"feature_names": BASE_FEATURES,
                "mono_freq": mono_freq,
                "mono_sev": mono_sev}, "pipeline_metadata")

    log.info("=== Pipeline complete. All models saved to %s ===", MODEL_DIR)

    return {
        "lgbm_freq": lgbm_freq,
        "lgbm_sev":  lgbm_sev,
        "xgb_freq":  xgb_freq,
        "xgb_sev":   xgb_sev,
        "feature_engineer": fe,
        "X_freq": X_freq,
        "y_freq": y_freq,
        "X_sev":  X_sev,
        "y_sev":  y_sev,
        "offset_freq": offset_freq,
    }


# ---------------------------------------------------------------------------
# 9. Unit tests
# ---------------------------------------------------------------------------

def run_tests() -> None:
    """
    Lightweight unit tests that do NOT require the real dataset.
    Run with:  python phase3_ml_modeling.py --test
    """
    import traceback

    PASS = "\033[92mPASS\033[0m"
    FAIL = "\033[91mFAIL\033[0m"
    results = []

    def check(name: str, expr: bool, detail: str = "") -> None:
        status = PASS if expr else FAIL
        print(f"  [{status}] {name}" + (f" — {detail}" if detail else ""))
        results.append(expr)

    print("\n=== Unit Tests ===\n")

    # ── Test 1: FeatureEngineer produces expected columns ────────────────
    print("Test 1: FeatureEngineer columns")
    try:
        dummy = pd.DataFrame({
            "Exposure": [0.5, 1.0, 0.8],
            "VehPower": [6, 8, 5],
            "VehAge":   [2, 7, 15],
            "DrivAge":  [22, 45, 65],
            "BonusMalus": [100, 85, 120],
            "VehBrand": ["B1", "B2", "B1"],
            "VehGas":   ["Regular", "Diesel", "Regular"],
            "Area":     ["A", "B", "C"],
            "Density":  [100, 5000, 300],
            "Region":   ["R1", "R2", "R1"],
            "ClaimTotal": [0.0, 500.0, 0.0],
            "ClaimNb":    [0,   1,      0],
        })
        fe = FeatureEngineer()
        out = fe.fit_transform(dummy)
        for col in ["log_Density", "log_Exposure", "BonusMalus_sq",
                    "inv_DrivAge", "VehAge_band", "DrivAge_band", "BonusMalus_band"]:
            check(f"  column '{col}' present", col in out.columns)
        check("  log_Density >= 0", (out["log_Density"] >= 0).all())
        check("  BonusMalus_sq == BonusMalus^2",
              np.allclose(out["BonusMalus_sq"], out["BonusMalus"].values  # already encoded
                          if False else dummy["BonusMalus"].values ** 2))
        check("  inv_DrivAge > 0", (out["inv_DrivAge"] > 0).all())
    except Exception:
        traceback.print_exc()
        results.append(False)

    # ── Test 2: FeatureEngineer transform (no re-fit) ────────────────────
    print("\nTest 2: FeatureEngineer transform consistency")
    try:
        fe2 = FeatureEngineer()
        fe2.fit_transform(dummy)
        out2 = fe2.transform(dummy)
        check("  transform shape matches fit_transform", out2.shape == out.shape)
    except Exception:
        traceback.print_exc()
        results.append(False)

    # ── Test 3: Monotone constraint vector length ────────────────────────
    print("\nTest 3: Monotone constraint vector")
    try:
        vec = build_monotone_constraint_vector(
            BASE_FEATURES, MONOTONE_CONSTRAINTS_FREQ
        )
        check("  length == len(BASE_FEATURES)", len(vec) == len(BASE_FEATURES))
        check("  all values in {-1,0,1}", all(v in {-1, 0, 1} for v in vec))
        idx_bm = BASE_FEATURES.index("BonusMalus")
        check("  BonusMalus constraint == +1", vec[idx_bm] == 1)
    except Exception:
        traceback.print_exc()
        results.append(False)

    # ── Test 4: Stratified K-fold shape ─────────────────────────────────
    print("\nTest 4: Stratified K-fold")
    try:
        y_dummy = np.array([0] * 90 + [1] * 8 + [2] * 2)
        folds = stratified_kfold_indices(y_dummy, n_splits=5)
        check("  5 folds returned", len(folds) == 5)
        all_val = np.concatenate([v for _, v in folds])
        check("  all indices covered exactly once",
              len(np.unique(all_val)) == len(y_dummy))
    except Exception:
        traceback.print_exc()
        results.append(False)

    # ── Test 5: load_data filters non-positive Exposure ──────────────────
    print("\nTest 5: load_data Exposure filter")
    try:
        tmp_path = Path("/tmp/test_phase3.csv")
        test_df = dummy.copy()
        test_df.loc[0, "Exposure"] = 0.0
        test_df.to_csv(tmp_path, index=False)
        loaded = load_data(tmp_path)
        check("  row with Exposure=0 dropped", len(loaded) == 2)
        tmp_path.unlink()
    except Exception:
        traceback.print_exc()
        results.append(False)

    # ── Test 6: save / load model round-trip ────────────────────────────
    print("\nTest 6: Pickle round-trip")
    try:
        test_obj = {"key": [1, 2, 3], "nested": {"a": "b"}}
        test_path = MODEL_DIR / "test_roundtrip.pkl"
        with open(test_path, "wb") as f:
            pickle.dump(test_obj, f)
        with open(test_path, "rb") as f:
            loaded_obj = pickle.load(f)
        check("  loaded object equals original", loaded_obj == test_obj)
        test_path.unlink()
    except Exception:
        traceback.print_exc()
        results.append(False)

    # ── Summary ──────────────────────────────────────────────────────────
    n_pass = sum(results)
    n_total = len(results)
    colour = "\033[92m" if n_pass == n_total else "\033[91m"
    print(f"\n{colour}Results: {n_pass}/{n_total} passed\033[0m\n")
    sys.exit(0 if n_pass == n_total else 1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Phase 3 – ML Modeling")
    parser.add_argument("--test",     action="store_true", help="Run unit tests and exit")
    parser.add_argument("--trials",   type=int, default=N_TRIALS,
                        help=f"Optuna trials per model (default {N_TRIALS})")
    parser.add_argument("--data",     type=str, default=str(DATA_PATH),
                        help="Path to input CSV")
    args = parser.parse_args()

    if args.test:
        run_tests()
    else:
        run_pipeline(Path(args.data), n_trials=args.trials)
