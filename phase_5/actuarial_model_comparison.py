"""
actuarial_model_comparison.py
=============================
Phase 5 – Performance Comparison: GLM vs LightGBM vs XGBoost
Dataset : freMTPLfreq_sev_data_1000.csv  (French MTPL portfolio)

Covers
------
* Frequency model  – Poisson GLM / LightGBM / XGBoost  (target: ClaimNb, offset: log(Exposure))
* Severity  model  – Gamma  GLM / LightGBM / XGBoost   (target: ClaimTotal / ClaimNb, only rows with claims)
* Metrics  : Poisson deviance, Gamma deviance, Gini coefficient
* Plots    : Lorenz curve, Lift curve, Double-Lift chart, Decile calibration
* Tables   : Training / inference time, Master comparison table (Markdown)
* Unit tests at the bottom (run with  pytest  or  python -m pytest)

Dependencies
------------
pip install pandas numpy scikit-learn lightgbm xgboost matplotlib

"""

# ─────────────────────────────────────────────────────────────────────────────
# 0.  IMPORTS & GLOBAL CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

import time
import warnings
import logging
from pathlib import Path
from typing import Dict, Tuple, List

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")          # non-interactive backend – safe in CI/scripts
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.linear_model import PoissonRegressor, GammaRegressor
import lightgbm as lgb
import xgboost as xgb

warnings.filterwarnings("ignore")
logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

# Output directory for all plots
PLOT_DIR = Path("plots")
PLOT_DIR.mkdir(exist_ok=True)

DATA_PATH = Path("freMTPLfreq_sev_data_1000.csv")
RANDOM_SEED = 42
TEST_SIZE   = 0.2


# ─────────────────────────────────────────────────────────────────────────────
# 1.  DATA LOADING & FEATURE ENGINEERING
# ─────────────────────────────────────────────────────────────────────────────

def load_and_prepare(path: Path) -> pd.DataFrame:
    """
    Load the MTPL dataset and engineer features.

    Parameters
    ----------
    path : Path
        Path to the CSV file.

    Returns
    -------
    pd.DataFrame
        Clean dataframe ready for modelling.
    """
    df = pd.read_csv(path, index_col=0)
    log.info("Loaded %d rows, %d columns from %s", *df.shape, path)

    # Clip exposure to a valid range (avoid log(0))
    df["Exposure"] = df["Exposure"].clip(lower=1e-6, upper=1.0)

    # Log-Exposure: used as offset in Poisson models
    df["LogExposure"] = np.log(df["Exposure"])

    # Severity target (average cost per claim, only for claim rows)
    df["AvgCost"] = np.where(df["ClaimNb"] > 0,
                              df["ClaimTotal"] / df["ClaimNb"],
                              np.nan)

    # Frequency target (pure premium normalised by exposure)
    df["Frequency"] = df["ClaimNb"] / df["Exposure"]

    # Label-encode categorical features
    cat_cols = ["VehBrand", "VehGas", "Area", "Region"]
    for col in cat_cols:
        df[col] = LabelEncoder().fit_transform(df[col].astype(str))

    # Clip BonusMalus to remove extreme outliers
    df["BonusMalus"] = df["BonusMalus"].clip(50, 350)

    log.info("Feature engineering complete. Claim rate: %.2f%%",
             100 * (df["ClaimNb"] > 0).mean())
    return df


NUMERIC_FEATURES = [
    "VehPower", "VehAge", "DrivAge", "BonusMalus",
    "VehBrand", "VehGas", "Area", "Density", "Region"
]


def split_frequency(df: pd.DataFrame) -> Tuple:
    """
    Train / test split for the frequency (Poisson) model.

    Returns X_train, X_test, y_train, y_test, w_train, w_test
    where w = Exposure (used as sample_weight in sklearn, offset in boosters).
    """
    X = df[NUMERIC_FEATURES].copy()
    y = df["ClaimNb"].values
    w = df["Exposure"].values    # exposure weights

    return train_test_split(X, y, w,
                            test_size=TEST_SIZE,
                            random_state=RANDOM_SEED)


def split_severity(df: pd.DataFrame) -> Tuple:
    """
    Train / test split for the severity (Gamma) model.
    Only rows with at least one claim are used.
    """
    mask = df["ClaimNb"] > 0
    sub  = df[mask].copy()
    X    = sub[NUMERIC_FEATURES].copy()
    y    = sub["AvgCost"].values
    w    = sub["ClaimNb"].values   # claim counts as weights

    return train_test_split(X, y, w,
                            test_size=TEST_SIZE,
                            random_state=RANDOM_SEED)


# ─────────────────────────────────────────────────────────────────────────────
# 2.  METRICS
# ─────────────────────────────────────────────────────────────────────────────

def poisson_deviance(y_true: np.ndarray,
                     y_pred: np.ndarray,
                     weights: np.ndarray = None) -> float:
    """
    Compute the (weighted) mean Poisson deviance.

    D(y, ŷ) = 2 * [y * log(y/ŷ) - (y - ŷ)]

    Parameters
    ----------
    y_true   : observed claim counts
    y_pred   : predicted claim counts  (must be > 0)
    weights  : exposure weights  (optional)

    Returns
    -------
    float : mean Poisson deviance
    """
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float).clip(1e-10)

    # Element-wise deviance contribution
    # guard against y_true == 0 (0 * log(0) = 0 by convention)
    with np.errstate(divide="ignore", invalid="ignore"):
        log_term = np.where(y_true > 0,
                            y_true * np.log(y_true / y_pred),
                            0.0)
    dev = 2.0 * (log_term - (y_true - y_pred))

    if weights is not None:
        weights = np.asarray(weights, dtype=float)
        return float(np.average(dev, weights=weights))
    return float(dev.mean())


def gamma_deviance(y_true: np.ndarray,
                   y_pred: np.ndarray,
                   weights: np.ndarray = None) -> float:
    """
    Compute the (weighted) mean Gamma deviance.

    D(y, ŷ) = 2 * [log(ŷ/y) + y/ŷ - 1]

    Parameters
    ----------
    y_true   : observed average claim costs  (must be > 0)
    y_pred   : predicted average claim costs (must be > 0)
    weights  : claim count weights  (optional)

    Returns
    -------
    float : mean Gamma deviance
    """
    y_true = np.asarray(y_true, dtype=float).clip(1e-10)
    y_pred = np.asarray(y_pred, dtype=float).clip(1e-10)

    dev = 2.0 * (np.log(y_pred / y_true) + y_true / y_pred - 1.0)

    if weights is not None:
        weights = np.asarray(weights, dtype=float)
        return float(np.average(dev, weights=weights))
    return float(dev.mean())


def gini_coefficient(y_true: np.ndarray,
                     y_pred: np.ndarray,
                     weights: np.ndarray = None) -> float:
    """
    Compute the Gini coefficient (area between Lorenz curve and diagonal).

    The Gini is derived from the ROC AUC:
        Gini = 2 * AUC - 1

    Here we use the weighted concordance approach (Lorenz area).

    Parameters
    ----------
    y_true  : actual outcomes (e.g. claim counts or costs)
    y_pred  : model scores (higher = riskier)
    weights : exposure or claim weights  (optional)

    Returns
    -------
    float : Gini coefficient in [0, 1]
    """
    order  = np.argsort(y_pred)
    y_s    = y_true[order]
    w_s    = weights[order] if weights is not None else np.ones_like(y_s, dtype=float)
    cum_w  = np.cumsum(w_s) / w_s.sum()
    cum_y  = np.cumsum(y_s * w_s) / (y_s * w_s).sum()

    # Area under Lorenz curve (trapezoid rule)
    # np.trapezoid was introduced in NumPy 2.0; np.trapz is the legacy alias
    trapz = getattr(np, "trapezoid", None) or np.trapz
    auc_lorenz = trapz(cum_y, cum_w)
    gini       = 1.0 - 2.0 * auc_lorenz
    return float(gini)


# ─────────────────────────────────────────────────────────────────────────────
# 3.  MODEL TRAINING  (with timing)
# ─────────────────────────────────────────────────────────────────────────────

class TimingResult:
    """Holds training and inference wall-clock times (seconds)."""
    def __init__(self, train_sec: float, infer_sec: float):
        self.train_sec = train_sec
        self.infer_sec = infer_sec

    def __repr__(self):
        return f"TimingResult(train={self.train_sec:.3f}s, infer={self.infer_sec:.4f}s)"


def train_glm_poisson(X_train, y_train, w_train,
                      X_test) -> Tuple[np.ndarray, np.ndarray, TimingResult]:
    """
    Fit a Poisson GLM (log link) with exposure offset approximated via
    sample_weight (sklearn does not support true offset – we pass Exposure
    as the weight and model the rate ClaimNb/Exposure).

    Returns (y_pred_train, y_pred_test, timing).
    """
    rate_train = y_train / w_train   # frequency rate

    t0 = time.perf_counter()
    model = PoissonRegressor(alpha=1e-4, max_iter=500)
    model.fit(X_train, rate_train, sample_weight=w_train)
    t_train = time.perf_counter() - t0

    t0 = time.perf_counter()
    pred_train = model.predict(X_train) * w_train   # back to counts
    pred_test  = model.predict(X_test)              # rate predictions
    t_infer = time.perf_counter() - t0

    return pred_train, pred_test, TimingResult(t_train, t_infer)


def train_lgbm_poisson(X_train, y_train, w_train,
                       X_test) -> Tuple[np.ndarray, np.ndarray, TimingResult]:
    """
    Fit a LightGBM model with Poisson objective (log link, uses Exposure offset).
    """
    params = {
        "objective":        "poisson",
        "learning_rate":    0.05,
        "num_leaves":       31,
        "min_child_samples": 5,
        "n_estimators":     200,
        "random_state":     RANDOM_SEED,
        "verbose":         -1,
    }

    t0 = time.perf_counter()
    model = lgb.LGBMRegressor(**params)
    # pass log(exposure) as offset through init_score / manually via dataset
    # For LGBMRegressor API we use sample_weight and the rate target
    rate_train = y_train / w_train
    model.fit(X_train, rate_train, sample_weight=w_train)
    t_train = time.perf_counter() - t0

    t0 = time.perf_counter()
    pred_train = model.predict(X_train)
    pred_test  = model.predict(X_test)
    t_infer = time.perf_counter() - t0

    return pred_train, pred_test, TimingResult(t_train, t_infer)


def train_xgb_poisson(X_train, y_train, w_train,
                      X_test) -> Tuple[np.ndarray, np.ndarray, TimingResult]:
    """
    Fit an XGBoost model with count:poisson objective.
    """
    params = {
        "objective":        "count:poisson",
        "learning_rate":    0.05,
        "max_depth":        4,
        "n_estimators":     200,
        "subsample":        0.8,
        "colsample_bytree": 0.8,
        "random_state":     RANDOM_SEED,
        "verbosity":        0,
    }

    t0 = time.perf_counter()
    model = xgb.XGBRegressor(**params)
    rate_train = y_train / w_train
    model.fit(X_train, rate_train, sample_weight=w_train,
              eval_set=[(X_test, y_test_freq_global)],   # logged only if global set
              verbose=False)
    t_train = time.perf_counter() - t0

    t0 = time.perf_counter()
    pred_train = model.predict(X_train)
    pred_test  = model.predict(X_test)
    t_infer = time.perf_counter() - t0

    return pred_train, pred_test, TimingResult(t_train, t_infer)


def train_glm_gamma(X_train, y_train, w_train,
                    X_test) -> Tuple[np.ndarray, np.ndarray, TimingResult]:
    """Gamma GLM (log link) for severity."""
    t0 = time.perf_counter()
    model = GammaRegressor(alpha=1.0, max_iter=500)
    model.fit(X_train, y_train, sample_weight=w_train)
    t_train = time.perf_counter() - t0

    t0 = time.perf_counter()
    pred_train = model.predict(X_train)
    pred_test  = model.predict(X_test)
    t_infer = time.perf_counter() - t0

    return pred_train, pred_test, TimingResult(t_train, t_infer)


def train_lgbm_gamma(X_train, y_train, w_train,
                     X_test) -> Tuple[np.ndarray, np.ndarray, TimingResult]:
    """LightGBM with Gamma regression objective."""
    params = {
        "objective":        "gamma",
        "learning_rate":    0.05,
        "num_leaves":       31,
        "min_child_samples": 3,
        "n_estimators":     200,
        "random_state":     RANDOM_SEED,
        "verbose":         -1,
    }
    t0 = time.perf_counter()
    model = lgb.LGBMRegressor(**params)
    model.fit(X_train, y_train, sample_weight=w_train)
    t_train = time.perf_counter() - t0

    t0 = time.perf_counter()
    pred_train = model.predict(X_train)
    pred_test  = model.predict(X_test)
    t_infer = time.perf_counter() - t0

    return pred_train, pred_test, TimingResult(t_train, t_infer)


def train_xgb_gamma(X_train, y_train, w_train,
                    X_test) -> Tuple[np.ndarray, np.ndarray, TimingResult]:
    """XGBoost with Gamma regression objective."""
    params = {
        "objective":        "reg:gamma",
        "learning_rate":    0.05,
        "max_depth":        4,
        "n_estimators":     200,
        "subsample":        0.8,
        "colsample_bytree": 0.8,
        "random_state":     RANDOM_SEED,
        "verbosity":        0,
    }
    t0 = time.perf_counter()
    model = xgb.XGBRegressor(**params)
    model.fit(X_train, y_train, sample_weight=w_train, verbose=False)
    t_train = time.perf_counter() - t0

    t0 = time.perf_counter()
    pred_train = model.predict(X_train)
    pred_test  = model.predict(X_test)
    t_infer = time.perf_counter() - t0

    return pred_train, pred_test, TimingResult(t_train, t_infer)


# ─────────────────────────────────────────────────────────────────────────────
# 4.  PLOTS
# ─────────────────────────────────────────────────────────────────────────────

def plot_lorenz(y_true: np.ndarray,
                predictions: Dict[str, np.ndarray],
                weights: np.ndarray,
                title: str = "Lorenz Curve",
                filename: str = "lorenz.png") -> None:
    """
    Plot Lorenz curves for multiple models on the same axes.

    Parameters
    ----------
    y_true      : observed outcomes
    predictions : dict  {model_name: y_pred_array}
    weights     : exposure/claim weights
    title       : plot title
    filename    : output file name (saved to PLOT_DIR)
    """
    fig, ax = plt.subplots(figsize=(7, 6))
    ax.plot([0, 1], [0, 1], "k--", lw=1, label="Perfect equality")

    for name, y_pred in predictions.items():
        order  = np.argsort(y_pred)
        y_s    = y_true[order]
        w_s    = weights[order]
        cum_w  = np.cumsum(w_s) / w_s.sum()
        cum_y  = np.cumsum(y_s * w_s) / (y_s * w_s).sum()
        gini   = gini_coefficient(y_true, y_pred, weights)
        ax.plot(cum_w, cum_y, lw=2, label=f"{name}  (Gini={gini:.3f})")

    ax.set_xlabel("Cumulative share of policies (by predicted risk)")
    ax.set_ylabel("Cumulative share of claims")
    ax.set_title(title)
    ax.legend()
    ax.grid(alpha=0.3)
    path = PLOT_DIR / filename
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)
    log.info("Saved Lorenz curve → %s", path)


def plot_lift_curve(y_true: np.ndarray,
                    y_pred: np.ndarray,
                    weights: np.ndarray,
                    model_name: str,
                    n_buckets: int = 10,
                    filename: str = "lift.png") -> None:
    """
    Lift curve: ratio of  (avg observed in bucket) / (avg observed overall).

    Policies are sorted descending by predicted score and grouped into
    ``n_buckets`` equal-weight buckets. A perfect model concentrates
    claims in the top buckets (lift > 1) and the lift curve slopes downward.

    Parameters
    ----------
    y_true     : observed outcomes
    y_pred     : model scores (higher = riskier)
    weights    : exposure weights
    model_name : label for the plot
    n_buckets  : number of quantile buckets  (default 10 = deciles)
    filename   : output file name
    """
    df = pd.DataFrame({
        "y_true":  y_true,
        "y_pred":  y_pred,
        "weight":  weights,
    }).sort_values("y_pred", ascending=False)

    df["cum_weight"] = df["weight"].cumsum()
    total_w = df["weight"].sum()
    df["bucket"] = pd.cut(df["cum_weight"] / total_w,
                          bins=np.linspace(0, 1, n_buckets + 1),
                          labels=False, include_lowest=True)

    overall_avg = np.average(y_true, weights=weights)
    bucket_avg  = df.groupby("bucket").apply(
        lambda g: np.average(g["y_true"], weights=g["weight"])
    )
    lift = bucket_avg / overall_avg

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.bar(range(1, n_buckets + 1), lift.values, color="steelblue", alpha=0.8)
    ax.axhline(1.0, color="red", linestyle="--", lw=1, label="Baseline (lift=1)")
    ax.set_xlabel("Decile (1 = highest predicted risk)")
    ax.set_ylabel("Lift")
    ax.set_title(f"Lift Curve – {model_name}")
    ax.legend()
    ax.grid(axis="y", alpha=0.3)
    path = PLOT_DIR / filename
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)
    log.info("Saved Lift curve → %s", path)


def plot_double_lift(y_true: np.ndarray,
                     pred_a: np.ndarray,
                     pred_b: np.ndarray,
                     weights: np.ndarray,
                     label_a: str = "Model A",
                     label_b: str = "Model B",
                     n_buckets: int = 10,
                     filename: str = "double_lift.png") -> None:
    """
    Double-Lift chart: compare two models head-to-head.

    Policies are sorted by the *ratio* pred_a / pred_b.  In each decile we
    compare the average observed outcome to the predictions of both models.
    This reveals where each model has comparative advantage.

    Parameters
    ----------
    y_true   : observed outcomes
    pred_a   : predictions from model A
    pred_b   : predictions from model B
    weights  : exposure weights
    label_a  : name of model A
    label_b  : name of model B
    n_buckets: number of buckets (default 10)
    filename : output file name
    """
    ratio = np.log1p(pred_a) - np.log1p(pred_b)  # log-ratio for stability

    df = pd.DataFrame({
        "y_true":  y_true,
        "pred_a":  pred_a,
        "pred_b":  pred_b,
        "weight":  weights,
        "ratio":   ratio,
    }).sort_values("ratio")

    df["cum_weight"] = df["weight"].cumsum()
    total_w = df["weight"].sum()
    df["bucket"] = pd.cut(df["cum_weight"] / total_w,
                          bins=np.linspace(0, 1, n_buckets + 1),
                          labels=False, include_lowest=True)

    buckets   = range(1, n_buckets + 1)
    obs_avg   = []
    pred_a_avg = []
    pred_b_avg = []

    for b in range(n_buckets):
        g = df[df["bucket"] == b]
        if len(g) == 0:
            obs_avg.append(np.nan)
            pred_a_avg.append(np.nan)
            pred_b_avg.append(np.nan)
        else:
            obs_avg.append(np.average(g["y_true"],  weights=g["weight"]))
            pred_a_avg.append(np.average(g["pred_a"], weights=g["weight"]))
            pred_b_avg.append(np.average(g["pred_b"], weights=g["weight"]))

    x = np.array(list(buckets))
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(x, obs_avg,    "ko-", lw=2,  label="Observed",    zorder=3)
    ax.plot(x, pred_a_avg, "b^--", lw=2, label=label_a)
    ax.plot(x, pred_b_avg, "rs--", lw=2, label=label_b)
    ax.set_xlabel(f"Decile (sorted by log-ratio {label_a}/{label_b})")
    ax.set_ylabel("Average claim frequency")
    ax.set_title(f"Double-Lift Chart: {label_a} vs {label_b}")
    ax.legend()
    ax.grid(alpha=0.3)
    path = PLOT_DIR / filename
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)
    log.info("Saved Double-Lift chart → %s", path)


def plot_decile_calibration(y_true: np.ndarray,
                             predictions: Dict[str, np.ndarray],
                             weights: np.ndarray,
                             n_buckets: int = 10,
                             title: str = "Decile Calibration",
                             filename: str = "calibration.png") -> pd.DataFrame:
    """
    Decile analysis: group test data by predicted score, compare
    mean predicted vs mean observed in each bucket.

    Parameters
    ----------
    y_true      : observed outcomes
    predictions : dict {model_name: y_pred_array}
    weights     : exposure weights
    n_buckets   : number of deciles
    title       : plot title
    filename    : output file name

    Returns
    -------
    pd.DataFrame with decile statistics for all models.
    """
    records = []

    fig, axes = plt.subplots(1, len(predictions),
                             figsize=(5 * len(predictions), 5),
                             sharey=False)
    if len(predictions) == 1:
        axes = [axes]

    for ax, (name, y_pred) in zip(axes, predictions.items()):
        df = pd.DataFrame({
            "y_true": y_true,
            "y_pred": y_pred,
            "weight": weights,
        })
        # Use rank-based bucketing (always produces n_buckets groups)
        df["decile"] = pd.qcut(df["y_pred"].rank(method="first"),
                               q=n_buckets, labels=False)

        grp_records = []
        for i, (dec_val, g) in enumerate(df.groupby("decile")):
            grp_records.append({"decile": i + 1, "obs_mean": float(np.average(g["y_true"], weights=g["weight"])), "pred_mean": float(np.average(g["y_pred"], weights=g["weight"])), "n_policies": len(g)})
        summary = pd.DataFrame(grp_records)

        for _, row in summary.iterrows():
            records.append({
                "Model":     name,
                "Decile":    int(row["decile"]),
                "Predicted": round(row["pred_mean"], 4),
                "Observed":  round(row["obs_mean"],  4),
                "N":         int(row["n_policies"]),
            })

        x = summary["decile"].values
        ax.bar(x - 0.2, summary["obs_mean"].values,  0.35, label="Observed",  color="steelblue")
        ax.bar(x + 0.2, summary["pred_mean"].values, 0.35, label="Predicted", color="orange", alpha=0.85)
        ax.set_title(name)
        ax.set_xlabel("Decile")
        ax.set_ylabel("Average value")
        ax.legend(fontsize=8)
        ax.grid(axis="y", alpha=0.3)

    fig.suptitle(title, fontsize=13, fontweight="bold")
    path = PLOT_DIR / filename
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)
    log.info("Saved Decile Calibration chart → %s", path)

    return pd.DataFrame(records)


# ─────────────────────────────────────────────────────────────────────────────
# 5.  MASTER COMPARISON TABLE
# ─────────────────────────────────────────────────────────────────────────────

def build_master_table(freq_results: Dict,
                       sev_results: Dict,
                       timing: Dict) -> pd.DataFrame:
    """
    Assemble the final comparison table.

    Parameters
    ----------
    freq_results : dict  {model: {"deviance": float, "gini": float}}
    sev_results  : dict  {model: {"deviance": float, "gini": float}}
    timing       : dict  {model: TimingResult}

    Returns
    -------
    pd.DataFrame : master table with rows=metrics, cols=models
    """
    models = ["GLM", "LightGBM", "XGBoost"]
    rows = []

    # --- Frequency metrics ---
    rows.append({
        "Metric": "Poisson Deviance (freq, test)",
        **{m: f"{freq_results[m]['deviance']:.4f}" for m in models}
    })
    rows.append({
        "Metric": "Gini Coefficient (freq, test)",
        **{m: f"{freq_results[m]['gini']:.4f}"    for m in models}
    })

    # --- Severity metrics ---
    rows.append({
        "Metric": "Gamma Deviance (sev, test)",
        **{m: f"{sev_results[m]['deviance']:.4f}" for m in models}
    })
    rows.append({
        "Metric": "Gini Coefficient (sev, test)",
        **{m: f"{sev_results[m]['gini']:.4f}"    for m in models}
    })

    # --- Timing ---
    rows.append({
        "Metric": "Training Time (s)",
        **{m: f"{timing[m].train_sec:.3f}" for m in models}
    })
    rows.append({
        "Metric": "Inference Time (s)",
        **{m: f"{timing[m].infer_sec:.4f}" for m in models}
    })

    df = pd.DataFrame(rows, columns=["Metric"] + models)
    return df


def df_to_markdown(df: pd.DataFrame) -> str:
    """Convert a DataFrame to a GitHub-Flavoured Markdown table."""
    header = "| " + " | ".join(df.columns) + " |"
    sep    = "| " + " | ".join(["---"] * len(df.columns)) + " |"
    lines  = [header, sep]
    for _, row in df.iterrows():
        lines.append("| " + " | ".join(str(v) for v in row) + " |")
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# 6.  MAIN PIPELINE
# ─────────────────────────────────────────────────────────────────────────────

# Global – needed by XGB eval_set inside function  (will be set in main)
y_test_freq_global: np.ndarray = np.array([])


def main() -> None:
    global y_test_freq_global

    # ── 6.1  Load data ──────────────────────────────────────────────────────
    df = load_and_prepare(DATA_PATH)

    # ── 6.2  Frequency splits ───────────────────────────────────────────────
    (X_tr_f, X_te_f,
     y_tr_f, y_te_f,
     w_tr_f, w_te_f) = split_frequency(df)

    y_test_freq_global = y_te_f / w_te_f   # rate target for XGB eval

    # ── 6.3  Severity splits ─────────────────────────────────────────────────
    sev_available = (df["ClaimNb"] > 0).sum() > 0
    if sev_available:
        (X_tr_s, X_te_s,
         y_tr_s, y_te_s,
         w_tr_s, w_te_s) = split_severity(df)
    else:
        log.warning("No claims found – severity models will be skipped.")

    # ── 6.4  Train frequency models ──────────────────────────────────────────
    log.info("=== FREQUENCY MODELS ===")

    log.info("Training Poisson GLM …")
    glm_f_tr, glm_f_te, glm_f_time = train_glm_poisson(
        X_tr_f, y_tr_f, w_tr_f, X_te_f)

    log.info("Training LightGBM Poisson …")
    lgb_f_tr, lgb_f_te, lgb_f_time = train_lgbm_poisson(
        X_tr_f, y_tr_f, w_tr_f, X_te_f)

    log.info("Training XGBoost Poisson …")
    xgb_f_tr, xgb_f_te, xgb_f_time = train_xgb_poisson(
        X_tr_f, y_tr_f, w_tr_f, X_te_f)

    # ── 6.5  Train severity models ───────────────────────────────────────────
    log.info("=== SEVERITY MODELS ===")

    log.info("Training Gamma GLM …")
    glm_s_tr, glm_s_te, glm_s_time = train_glm_gamma(
        X_tr_s, y_tr_s, w_tr_s, X_te_s)

    log.info("Training LightGBM Gamma …")
    lgb_s_tr, lgb_s_te, lgb_s_time = train_lgbm_gamma(
        X_tr_s, y_tr_s, w_tr_s, X_te_s)

    log.info("Training XGBoost Gamma …")
    xgb_s_tr, xgb_s_te, xgb_s_time = train_xgb_gamma(
        X_tr_s, y_tr_s, w_tr_s, X_te_s)

    # ── 6.6  Compute metrics ─────────────────────────────────────────────────
    log.info("=== COMPUTING METRICS ===")

    # Convert frequency predictions from rate → count for deviance
    glm_counts_te = glm_f_te * w_te_f
    lgb_counts_te = lgb_f_te * w_te_f
    xgb_counts_te = xgb_f_te * w_te_f

    freq_results = {
        "GLM": {
            "deviance": poisson_deviance(y_te_f, glm_counts_te, w_te_f),
            "gini":     gini_coefficient(y_te_f, glm_f_te, w_te_f),
        },
        "LightGBM": {
            "deviance": poisson_deviance(y_te_f, lgb_counts_te, w_te_f),
            "gini":     gini_coefficient(y_te_f, lgb_f_te, w_te_f),
        },
        "XGBoost": {
            "deviance": poisson_deviance(y_te_f, xgb_counts_te, w_te_f),
            "gini":     gini_coefficient(y_te_f, xgb_f_te, w_te_f),
        },
    }

    sev_results = {
        "GLM": {
            "deviance": gamma_deviance(y_te_s, glm_s_te, w_te_s),
            "gini":     gini_coefficient(y_te_s, glm_s_te, w_te_s),
        },
        "LightGBM": {
            "deviance": gamma_deviance(y_te_s, lgb_s_te, w_te_s),
            "gini":     gini_coefficient(y_te_s, lgb_s_te, w_te_s),
        },
        "XGBoost": {
            "deviance": gamma_deviance(y_te_s, xgb_s_te, w_te_s),
            "gini":     gini_coefficient(y_te_s, xgb_s_te, w_te_s),
        },
    }

    # Combined timing (frequency training is dominating phase in production)
    timing = {
        "GLM":      TimingResult(glm_f_time.train_sec + glm_s_time.train_sec,
                                 glm_f_time.infer_sec + glm_s_time.infer_sec),
        "LightGBM": TimingResult(lgb_f_time.train_sec + lgb_s_time.train_sec,
                                 lgb_f_time.infer_sec + lgb_s_time.infer_sec),
        "XGBoost":  TimingResult(xgb_f_time.train_sec + xgb_s_time.train_sec,
                                 xgb_f_time.infer_sec + xgb_s_time.infer_sec),
    }

    # Print interim metric results
    log.info("\n--- Frequency metrics (test) ---")
    for m, v in freq_results.items():
        log.info("  %-10s  Poisson Dev=%.4f  Gini=%.4f", m, v["deviance"], v["gini"])

    log.info("\n--- Severity metrics (test) ---")
    for m, v in sev_results.items():
        log.info("  %-10s  Gamma Dev=%.4f  Gini=%.4f", m, v["deviance"], v["gini"])

    # ── 6.7  Generate plots ──────────────────────────────────────────────────
    log.info("=== GENERATING PLOTS ===")

    # Lorenz – frequency
    plot_lorenz(
        y_true=y_te_f,
        predictions={"GLM": glm_f_te, "LightGBM": lgb_f_te, "XGBoost": xgb_f_te},
        weights=w_te_f,
        title="Lorenz Curve – Claim Frequency",
        filename="lorenz_frequency.png",
    )

    # Lorenz – severity
    plot_lorenz(
        y_true=y_te_s,
        predictions={"GLM": glm_s_te, "LightGBM": lgb_s_te, "XGBoost": xgb_s_te},
        weights=w_te_s,
        title="Lorenz Curve – Claim Severity",
        filename="lorenz_severity.png",
    )

    # Lift curves
    for name, preds in [("GLM", glm_f_te), ("LightGBM", lgb_f_te), ("XGBoost", xgb_f_te)]:
        plot_lift_curve(
            y_true=y_te_f, y_pred=preds, weights=w_te_f,
            model_name=name,
            filename=f"lift_{name.lower()}_freq.png",
        )

    # Double-Lift: GLM vs LightGBM (frequency)
    plot_double_lift(
        y_true=y_te_f,
        pred_a=glm_f_te, pred_b=lgb_f_te,
        weights=w_te_f,
        label_a="GLM", label_b="LightGBM",
        filename="double_lift_glm_vs_lgbm_freq.png",
    )

    # Double-Lift: LightGBM vs XGBoost (frequency)
    plot_double_lift(
        y_true=y_te_f,
        pred_a=lgb_f_te, pred_b=xgb_f_te,
        weights=w_te_f,
        label_a="LightGBM", label_b="XGBoost",
        filename="double_lift_lgbm_vs_xgb_freq.png",
    )

    # Decile calibration – frequency
    decile_df_freq = plot_decile_calibration(
        y_true=y_te_f,
        predictions={"GLM": glm_f_te, "LightGBM": lgb_f_te, "XGBoost": xgb_f_te},
        weights=w_te_f,
        title="Decile Calibration – Claim Frequency",
        filename="calibration_frequency.png",
    )

    # Decile calibration – severity
    decile_df_sev = plot_decile_calibration(
        y_true=y_te_s,
        predictions={"GLM": glm_s_te, "LightGBM": lgb_s_te, "XGBoost": xgb_s_te},
        weights=w_te_s,
        title="Decile Calibration – Claim Severity",
        filename="calibration_severity.png",
    )

    # ── 6.8  Master comparison table ─────────────────────────────────────────
    log.info("=== MASTER TABLE ===")
    master = build_master_table(freq_results, sev_results, timing)
    print("\n" + "=" * 70)
    print("MASTER MODEL COMPARISON TABLE")
    print("=" * 70)
    print(master.to_string(index=False))
    print("\nMarkdown version:\n")
    md = df_to_markdown(master)
    print(md)

    # Save to file
    md_path = PLOT_DIR / "master_comparison.md"
    md_path.write_text(md)
    log.info("Saved master table (Markdown) → %s", md_path)

    csv_path = PLOT_DIR / "master_comparison.csv"
    master.to_csv(csv_path, index=False)
    log.info("Saved master table (CSV) → %s", csv_path)

    # Also save decile tables
    decile_df_freq.to_csv(PLOT_DIR / "decile_frequency.csv", index=False)
    decile_df_sev.to_csv(PLOT_DIR / "decile_severity.csv", index=False)

    log.info("Pipeline complete. All outputs in %s/", PLOT_DIR)


# ─────────────────────────────────────────────────────────────────────────────
# 7.  UNIT TESTS
# ─────────────────────────────────────────────────────────────────────────────

class TestMetrics:
    """
    Unit tests for metric functions.
    Run with:  pytest actuarial_model_comparison.py -v
    """

    def test_poisson_deviance_perfect(self):
        """Perfect predictions → deviance == 0."""
        y = np.array([1.0, 2.0, 3.0])
        assert abs(poisson_deviance(y, y)) < 1e-10

    def test_poisson_deviance_positive(self):
        """Deviance should always be non-negative."""
        rng = np.random.default_rng(0)
        y_true = rng.poisson(lam=2.0, size=500).astype(float)
        y_pred = rng.gamma(shape=2.0, scale=1.0, size=500)
        assert poisson_deviance(y_true, y_pred) >= 0

    def test_poisson_deviance_zeros(self):
        """Should handle y_true == 0 gracefully (no log(0) error)."""
        y_true = np.array([0.0, 0.0, 0.0])
        y_pred = np.array([0.5, 1.0, 2.0])
        val = poisson_deviance(y_true, y_pred)
        assert np.isfinite(val)

    def test_poisson_deviance_weighted(self):
        """Weighted deviance with uniform weights equals unweighted."""
        y_true = np.array([1.0, 2.0, 3.0])
        y_pred = np.array([1.1, 1.9, 3.2])
        w = np.ones(3)
        assert abs(poisson_deviance(y_true, y_pred) -
                   poisson_deviance(y_true, y_pred, w)) < 1e-10

    def test_gamma_deviance_perfect(self):
        """Perfect predictions → deviance == 0."""
        y = np.array([100.0, 200.0, 300.0])
        assert abs(gamma_deviance(y, y)) < 1e-10

    def test_gamma_deviance_positive(self):
        """Gamma deviance ≥ 0."""
        rng = np.random.default_rng(1)
        y_true = rng.gamma(shape=2, scale=100, size=300)
        y_pred = rng.gamma(shape=2, scale=100, size=300)
        assert gamma_deviance(y_true, y_pred) >= 0

    def test_gini_range(self):
        """Gini coefficient in [0, 1]."""
        rng = np.random.default_rng(2)
        y_true = rng.poisson(lam=0.1, size=200).astype(float)
        y_pred = rng.uniform(0, 1, size=200)
        g = gini_coefficient(y_true, y_pred)
        assert 0.0 <= g <= 1.0

    def test_gini_random_zero(self):
        """Random predictions ≈ 0 Gini (symmetric around 0)."""
        rng = np.random.default_rng(3)
        n = 10_000
        y_true = rng.poisson(1.0, size=n).astype(float) + 1e-3
        y_pred = rng.uniform(0, 1, size=n)
        g = gini_coefficient(y_true, y_pred)
        # |Gini| should be small for random scores
        assert abs(g) < 0.15, f"Expected near-zero Gini for random, got {g:.3f}"

    def test_build_master_table_shape(self):
        """Master table has correct dimensions."""
        dummy_freq = {m: {"deviance": 1.0, "gini": 0.1} for m in ["GLM", "LightGBM", "XGBoost"]}
        dummy_sev  = {m: {"deviance": 2.0, "gini": 0.2} for m in ["GLM", "LightGBM", "XGBoost"]}
        dummy_time = {m: TimingResult(0.5, 0.01)         for m in ["GLM", "LightGBM", "XGBoost"]}
        tbl = build_master_table(dummy_freq, dummy_sev, dummy_time)
        assert tbl.shape == (6, 4)   # 6 rows × (Metric + 3 models)
        assert list(tbl.columns) == ["Metric", "GLM", "LightGBM", "XGBoost"]

    def test_markdown_output_format(self):
        """Markdown table starts with a header and separator."""
        dummy_freq = {m: {"deviance": 1.0, "gini": 0.1} for m in ["GLM", "LightGBM", "XGBoost"]}
        dummy_sev  = {m: {"deviance": 2.0, "gini": 0.2} for m in ["GLM", "LightGBM", "XGBoost"]}
        dummy_time = {m: TimingResult(0.5, 0.01)         for m in ["GLM", "LightGBM", "XGBoost"]}
        tbl = build_master_table(dummy_freq, dummy_sev, dummy_time)
        md  = df_to_markdown(tbl)
        lines = md.strip().split("\n")
        assert lines[0].startswith("|")
        assert "---" in lines[1]


# ─────────────────────────────────────────────────────────────────────────────
# 8.  ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    main()
