"""
=============================================================================
SHAP Phase 4 Analysis — freMTPL Claim Frequency Modelling
=============================================================================
Purpose  : Perform a full SHAP explainability analysis on a claim-frequency
           XGBoost model trained on the French Motor Third-Party Liability
           (freMTPL) dataset.  The results are written to disk as publication-
           quality PNG plots and a structured text report suitable for
           regulatory or actuarial review.

Workflow
--------
1. Data preparation  – feature engineering + train/test split
2. Baseline GLM      – Poisson GLM (log link, offset = log(Exposure))
3. XGBoost model     – Poisson regression, hyper-parameters tuned lightly
4. SHAP analysis     – Global (beeswarm, bar), dependence, waterfall, GLM
                       comparison
5. Regulatory report – plain-text summary of all findings

Output files (written to ./shap_output/)
-----------------------------------------
01_beeswarm_summary.png
02_bar_summary.png
03_dependence_<feature>.png   (top 5 features)
04_waterfall_case_<n>.png     (3 representative risks)
05_gain_vs_shap_importance.png
06_shap_vs_glm_comparison.png
regulatory_report.txt

Requirements
------------
  pandas, numpy, matplotlib, seaborn, scikit-learn, xgboost, shap, scipy
  Python >= 3.9
=============================================================================
"""

# ---------------------------------------------------------------------------
# Standard imports
# ---------------------------------------------------------------------------
from __future__ import annotations

import logging
import os
import sys
import textwrap
import warnings
from pathlib import Path
from typing import Dict, List, Tuple

import matplotlib
matplotlib.use("Agg")          # headless – no display needed
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
import pandas as pd
import seaborn as sns
import shap
import xgboost as xgb
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", category=UserWarning)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants / paths
# ---------------------------------------------------------------------------
DATA_PATH   = Path("/mnt/project/freMTPLfreq_sev_data_1000.csv")
OUTPUT_DIR  = Path("./shap_output")
RANDOM_SEED = 42
TEST_SIZE   = 0.20

# XGBoost hyper-parameters (Poisson regression)
XGB_PARAMS: Dict = dict(
    objective       = "count:poisson",
    max_depth       = 4,
    learning_rate   = 0.05,
    n_estimators    = 300,
    subsample       = 0.8,
    colsample_bytree= 0.8,
    min_child_weight= 20,        # regularise on small cells
    reg_alpha       = 0.1,
    reg_lambda      = 1.0,
    random_state    = RANDOM_SEED,
    n_jobs          = -1,
)

# Feature columns used for modelling
NUMERIC_FEATURES  = ["VehPower", "VehAge", "DrivAge", "BonusMalus", "Density"]
CATEGORIC_FEATURES = ["VehBrand", "VehGas", "Area", "Region"]
ALL_FEATURES      = NUMERIC_FEATURES + CATEGORIC_FEATURES

# ---------------------------------------------------------------------------
# 1. Data loading & preparation
# ---------------------------------------------------------------------------

def load_and_prepare(path: Path) -> pd.DataFrame:
    """Load CSV, validate schema, engineer features."""
    log.info("Loading dataset: %s", path)
    df = pd.read_csv(path)

    required = {"Exposure", "ClaimNb"} | set(ALL_FEATURES)
    missing  = required - set(df.columns)
    if missing:
        raise ValueError(f"Missing columns: {missing}")

    # Clip exposure to (0, 1] – policy years
    df["Exposure"] = df["Exposure"].clip(lower=1e-6, upper=1.0)

    # Target: claim frequency = ClaimNb / Exposure  (kept for GLM comparison)
    df["ClaimFreq"] = df["ClaimNb"] / df["Exposure"]

    # Log density (strong right skew)
    df["LogDensity"] = np.log1p(df["Density"])

    # BonusMalus capped at 150 (outlier protection)
    df["BonusMalusCapped"] = df["BonusMalus"].clip(upper=150)

    log.info("Dataset shape: %s", df.shape)
    log.info("Claim rate: %.4f", df["ClaimNb"].sum() / df["Exposure"].sum())
    return df


def encode_features(df: pd.DataFrame) -> Tuple[pd.DataFrame, Dict[str, LabelEncoder]]:
    """Label-encode categorical columns; return encoded df and encoders."""
    df_enc   = df.copy()
    encoders = {}
    for col in CATEGORIC_FEATURES:
        le = LabelEncoder()
        df_enc[col] = le.fit_transform(df_enc[col].astype(str))
        encoders[col] = le
    return df_enc, encoders


# Updated feature set used in models
MODEL_FEATURES = NUMERIC_FEATURES + CATEGORIC_FEATURES + ["LogDensity", "BonusMalusCapped"]


def build_matrices(df: pd.DataFrame) -> Tuple[
    pd.DataFrame, pd.DataFrame, pd.Series, pd.Series, pd.Series, pd.Series
]:
    """Split into train / test, return X, y and exposure arrays."""
    X = df[MODEL_FEATURES].copy()
    y = df["ClaimNb"].copy()
    w = df["Exposure"].copy()

    X_tr, X_te, y_tr, y_te, w_tr, w_te = train_test_split(
        X, y, w, test_size=TEST_SIZE, random_state=RANDOM_SEED
    )
    log.info("Train size: %d  |  Test size: %d", len(X_tr), len(X_te))
    return X_tr, X_te, y_tr, y_te, w_tr, w_te


# ---------------------------------------------------------------------------
# 2. Baseline GLM (Poisson, log link)
# ---------------------------------------------------------------------------

def fit_poisson_glm(
    X_tr: pd.DataFrame,
    y_tr: pd.Series,
    w_tr: pd.Series,
) -> "sklearn.linear_model.PoissonRegressor":
    """Fit a Poisson GLM and return fitted model object."""
    from sklearn.linear_model import PoissonRegressor
    from sklearn.pipeline import Pipeline
    from sklearn.preprocessing import StandardScaler

    log.info("Fitting Poisson GLM …")
    pipe = Pipeline([
        ("scaler", StandardScaler()),
        ("glm",    PoissonRegressor(alpha=1e-3, max_iter=500)),
    ])
    pipe.fit(X_tr, y_tr / w_tr, **{"glm__sample_weight": w_tr})
    return pipe


def extract_glm_coefficients(
    pipe, feature_names: List[str]
) -> pd.DataFrame:
    """Extract and format GLM coefficients."""
    glm    = pipe.named_steps["glm"]
    coefs  = glm.coef_
    coef_df = pd.DataFrame({
        "Feature"    : feature_names,
        "GLM_Coef"   : coefs,
        "Abs_Coef"   : np.abs(coefs),
        "Direction"  : np.where(coefs > 0, "Positive ↑", "Negative ↓"),
    }).sort_values("Abs_Coef", ascending=False)
    log.info("GLM intercept: %.4f", glm.intercept_)
    return coef_df


# ---------------------------------------------------------------------------
# 3. XGBoost model
# ---------------------------------------------------------------------------

def fit_xgboost(
    X_tr: pd.DataFrame,
    y_tr: pd.Series,
    w_tr: pd.Series,
    X_te: pd.DataFrame,
    y_te: pd.Series,
    w_te: pd.Series,
) -> xgb.XGBRegressor:
    """Train XGBoost Poisson model with early stopping."""
    log.info("Training XGBoost (Poisson) …")
    model = xgb.XGBRegressor(
        **XGB_PARAMS,
        early_stopping_rounds=30,
        eval_metric="poisson-nloglik",
    )

    # Exposure as base_margin (log link offset)
    base_margin_tr = np.log(w_tr.values)
    base_margin_te = np.log(w_te.values)

    model.fit(
        X_tr, y_tr,
        sample_weight = w_tr,
        base_margin   = base_margin_tr,
        eval_set      = [(X_te, y_te)],
        sample_weight_eval_set = [w_te],
        base_margin_eval_set   = [base_margin_te],
        verbose       = False,
    )
    best = model.best_iteration
    log.info("XGBoost best iteration: %d", best)
    return model


def get_gain_importance(model: xgb.XGBRegressor) -> pd.DataFrame:
    """Return gain-based feature importance as a tidy DataFrame."""
    imp = model.get_booster().get_score(importance_type="gain")
    df  = pd.DataFrame(
        list(imp.items()), columns=["Feature", "Gain"]
    ).sort_values("Gain", ascending=False).reset_index(drop=True)
    df["Gain_Norm"] = df["Gain"] / df["Gain"].sum()
    return df


# ---------------------------------------------------------------------------
# 4. SHAP analysis
# ---------------------------------------------------------------------------

def compute_shap_values(
    model: xgb.XGBRegressor,
    X: pd.DataFrame,
) -> Tuple[shap.Explanation, np.ndarray]:
    """Compute SHAP values using TreeExplainer; return Explanation and raw array."""
    log.info("Computing SHAP values for %d observations …", len(X))
    explainer   = shap.TreeExplainer(model)
    shap_expl   = explainer(X)               # Explanation object (shap >= 0.40)
    shap_values = shap_expl.values           # shape (n, p)
    log.info("SHAP values shape: %s", shap_values.shape)
    return shap_expl, shap_values


def shap_mean_abs(shap_values: np.ndarray, feature_names: List[str]) -> pd.DataFrame:
    """Return mean |SHAP| per feature sorted descending."""
    return pd.DataFrame({
        "Feature"   : feature_names,
        "MeanAbsSHAP": np.abs(shap_values).mean(axis=0),
    }).sort_values("MeanAbsSHAP", ascending=False).reset_index(drop=True)


# ---------------------------------------------------------------------------
# 5. Plotting helpers
# ---------------------------------------------------------------------------

PLOT_STYLE = {
    "figure.facecolor" : "white",
    "axes.facecolor"   : "#f9f9f9",
    "axes.grid"        : True,
    "grid.color"       : "#e0e0e0",
    "font.family"      : "DejaVu Sans",
    "font.size"        : 10,
}
plt.rcParams.update(PLOT_STYLE)
PALETTE = sns.color_palette("muted")


def _save(fig: plt.Figure, name: str, out_dir: Path) -> None:
    path = out_dir / name
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    log.info("Saved: %s", path)


def plot_beeswarm(shap_expl: shap.Explanation, out_dir: Path) -> None:
    """Global beeswarm summary plot (top 15 features)."""
    log.info("Plotting beeswarm …")
    fig, ax = plt.subplots(figsize=(10, 7))
    shap.plots.beeswarm(shap_expl, max_display=15, show=False)
    fig = plt.gcf()
    fig.suptitle(
        "Global SHAP Beeswarm Summary\n(freMTPL Claim Frequency — XGBoost)",
        fontsize=12, fontweight="bold", y=1.01,
    )
    _save(fig, "01_beeswarm_summary.png", out_dir)


def plot_bar_summary(shap_expl: shap.Explanation, out_dir: Path) -> None:
    """Global bar summary (mean |SHAP|)."""
    log.info("Plotting SHAP bar summary …")
    shap.plots.bar(shap_expl, max_display=15, show=False)
    fig = plt.gcf()
    fig.suptitle(
        "Global SHAP Bar Summary — Mean |SHAP Value|\n"
        "(freMTPL Claim Frequency — XGBoost)",
        fontsize=12, fontweight="bold", y=1.01,
    )
    _save(fig, "02_bar_summary.png", out_dir)


def plot_dependence(
    shap_values: np.ndarray,
    X: pd.DataFrame,
    top_features: List[str],
    out_dir: Path,
) -> None:
    """SHAP dependence plots for the top-5 features."""
    log.info("Plotting dependence plots …")
    feat_idx = {f: i for i, f in enumerate(X.columns)}
    for rank, feat in enumerate(top_features[:5], start=1):
        idx  = feat_idx[feat]
        fig, ax = plt.subplots(figsize=(8, 5))
        shap.dependence_plot(
            feat, shap_values, X,
            interaction_index=None,
            ax=ax, show=False,
            dot_size=20, alpha=0.6,
            color="#2196F3",
        )
        ax.set_title(
            f"SHAP Dependence — {feat}  (rank #{rank})",
            fontsize=11, fontweight="bold",
        )
        ax.set_xlabel(feat, fontsize=10)
        ax.set_ylabel(f"SHAP value for {feat}", fontsize=10)
        _save(fig, f"03_dependence_{feat}.png", out_dir)


def plot_waterfall(
    shap_expl: shap.Explanation,
    X_te: pd.DataFrame,
    out_dir: Path,
    n_cases: int = 4,
) -> List[int]:
    """
    Waterfall plots for representative individual risks.
    Selects:
      - 1 zero-claim, low-risk case
      - 1 zero-claim, high-risk case
      - The actual claimant(s) if any exist in test set
    Returns list of chosen row indices.
    """
    log.info("Plotting waterfall plots …")
    # Use mean |SHAP| as a risk proxy (higher = model is more 'active')
    risk_score = np.abs(shap_expl.values).sum(axis=1)
    low_idx    = int(np.argmin(risk_score))
    high_idx   = int(np.argmax(risk_score))
    med_idx    = int(np.argsort(risk_score)[len(risk_score) // 2])
    chosen     = list(dict.fromkeys([low_idx, med_idx, high_idx]))[:n_cases]

    for pos, i in enumerate(chosen, start=1):
        fig, ax = plt.subplots(figsize=(10, 5))
        shap.plots.waterfall(shap_expl[i], max_display=12, show=False)
        fig = plt.gcf()
        label = {low_idx: "Low-Risk", high_idx: "High-Risk", med_idx: "Median-Risk"}
        fig.suptitle(
            f"SHAP Waterfall — Case {pos}: {label.get(i, '')} "
            f"(observation index {i})",
            fontsize=11, fontweight="bold", y=1.02,
        )
        _save(fig, f"04_waterfall_case_{pos}.png", out_dir)
    return chosen


def plot_gain_vs_shap(
    gain_df: pd.DataFrame,
    shap_df: pd.DataFrame,
    out_dir: Path,
) -> None:
    """Bar chart comparing gain importance vs mean |SHAP|, side by side."""
    log.info("Plotting gain vs. SHAP importance …")
    merged = gain_df.merge(shap_df, on="Feature", how="outer").fillna(0)
    merged = merged.sort_values("MeanAbsSHAP", ascending=False).head(12)

    x     = np.arange(len(merged))
    width = 0.38
    fig, ax = plt.subplots(figsize=(12, 6))

    # Normalise gain to [0, 1] for scale comparability
    gain_norm  = merged["Gain_Norm"].values
    shap_norm  = merged["MeanAbsSHAP"].values / merged["MeanAbsSHAP"].sum()

    bars1 = ax.bar(x - width/2, gain_norm,  width, label="Gain (XGBoost)",    color=PALETTE[0], alpha=0.85)
    bars2 = ax.bar(x + width/2, shap_norm,  width, label="Mean |SHAP| (norm)", color=PALETTE[1], alpha=0.85)

    ax.set_xticks(x)
    ax.set_xticklabels(merged["Feature"], rotation=30, ha="right", fontsize=9)
    ax.set_ylabel("Normalised Importance", fontsize=10)
    ax.set_title(
        "Feature Importance: XGBoost Gain vs. Mean |SHAP Value|\n"
        "(freMTPL Claim Frequency)",
        fontsize=12, fontweight="bold",
    )
    ax.legend(fontsize=9)
    _save(fig, "05_gain_vs_shap_importance.png", out_dir)


def plot_shap_vs_glm(
    shap_df: pd.DataFrame,
    glm_df: pd.DataFrame,
    out_dir: Path,
) -> pd.DataFrame:
    """
    Scatter / comparison plot of SHAP mean direction vs GLM coefficient.
    SHAP direction = sign of mean(SHAP) across test set.
    """
    log.info("Plotting SHAP vs. GLM comparison …")
    shap_sign = shap_df.copy()
    # We need signed mean SHAP for direction comparison (already computed externally)
    merged = shap_sign.merge(glm_df[["Feature", "GLM_Coef", "Abs_Coef"]], on="Feature", how="inner")

    # Agreement = both positive or both negative (only meaningful for numeric features)
    merged["Agreement"] = np.where(
        merged["MeanAbsSHAP"] < 1e-6, "Insignificant",
        np.where(
            merged["MeanSHAP"] * merged["GLM_Coef"] >= 0, "Same Direction ✓", "Opposite Direction ✗"
        )
    )

    fig, ax = plt.subplots(figsize=(9, 6))
    palette  = {"Same Direction ✓": "#4CAF50", "Opposite Direction ✗": "#F44336", "Insignificant": "#9E9E9E"}
    for agr, grp in merged.groupby("Agreement"):
        ax.scatter(
            grp["GLM_Coef"], grp["MeanSHAP"],
            c=palette.get(agr, "grey"), label=agr,
            s=80, alpha=0.85, edgecolors="k", linewidths=0.4,
        )
        for _, row in grp.iterrows():
            ax.annotate(
                row["Feature"],
                (row["GLM_Coef"], row["MeanSHAP"]),
                textcoords="offset points", xytext=(6, 3), fontsize=7,
            )

    # Reference line x = 0 and y = 0
    ax.axhline(0, color="black", linewidth=0.7, linestyle="--")
    ax.axvline(0, color="black", linewidth=0.7, linestyle="--")
    ax.set_xlabel("GLM Coefficient (Poisson log-link)", fontsize=10)
    ax.set_ylabel("Mean SHAP Value (XGBoost)", fontsize=10)
    ax.set_title(
        "GLM Coefficient vs. Mean SHAP Value\n"
        "Directional Agreement Analysis (freMTPL Frequency Model)",
        fontsize=11, fontweight="bold",
    )
    ax.legend(fontsize=8, loc="upper left")
    _save(fig, "06_shap_vs_glm_comparison.png", out_dir)
    return merged


# ---------------------------------------------------------------------------
# 6. Regulatory report
# ---------------------------------------------------------------------------

def write_regulatory_report(
    comparison_df: pd.DataFrame,
    gain_df      : pd.DataFrame,
    shap_df      : pd.DataFrame,
    glm_df       : pd.DataFrame,
    top5         : List[str],
    out_dir      : Path,
) -> None:
    """Write a structured plain-text regulatory report."""
    log.info("Writing regulatory report …")
    lines: List[str] = []

    def h1(t: str) -> None: lines.extend(["=" * 78, t, "=" * 78, ""])
    def h2(t: str) -> None: lines.extend(["-" * 60, t, "-" * 60, ""])
    def p(t: str  ) -> None: lines.extend(textwrap.wrap(t, width=78) + [""])

    h1("REGULATORY EXPLAINABILITY REPORT")
    p("Document type  : Phase 4 — SHAP Analysis & Model Comparison")
    p("Dataset        : freMTPL (French MTPL) Claim Frequency — 1,000 observations")
    p("Target         : ClaimNb (Poisson count, offset = log Exposure)")
    p("Models         : (1) Poisson GLM  (2) XGBoost Poisson regression")
    p("Framework      : SHAP TreeExplainer (shap package)")
    lines.append("")

    h2("1. SCOPE AND PURPOSE")
    p(
        "This report provides a structured explanation of a machine-learning claim-"
        "frequency model trained on the freMTPL dataset.  It is intended to support "
        "regulatory review under IFRS 17 / Solvency II model-change processes and to "
        "demonstrate that the ML model's predictions are explainable, auditable, and "
        "directionally consistent with actuarial priors captured in the GLM baseline."
    )

    h2("2. GLOBAL FEATURE IMPORTANCE — TOP 5 FEATURES (SHAP)")
    lines.append(f"  {'Rank':<6} {'Feature':<22} {'Mean|SHAP|':>12}  {'Gain (norm)':>12}")
    lines.append("  " + "-" * 56)
    for i, feat in enumerate(top5, 1):
        shap_val = shap_df.loc[shap_df["Feature"] == feat, "MeanAbsSHAP"].values
        gain_val = gain_df.loc[gain_df["Feature"] == feat, "Gain_Norm"].values
        sv = f"{shap_val[0]:.5f}" if len(shap_val) else "N/A"
        gv = f"{gain_val[0]:.5f}" if len(gain_val) else "N/A"
        lines.append(f"  {i:<6} {feat:<22} {sv:>12}  {gv:>12}")
    lines.append("")
    p(
        "SHAP and gain importance generally agree on the most influential features, "
        "giving confidence that the model's internal structure is consistent.  "
        "Discrepancies (where gain ranks a feature highly but SHAP does not) can "
        "indicate that a feature participates in many weak splits (boosting gain) "
        "without having a large marginal effect on the output (low SHAP)."
    )

    h2("3. GLM vs. SHAP — DIRECTIONAL AGREEMENT")
    same  = comparison_df[comparison_df["Agreement"] == "Same Direction ✓"]
    opp   = comparison_df[comparison_df["Agreement"] == "Opposite Direction ✗"]
    insig = comparison_df[comparison_df["Agreement"] == "Insignificant"]

    lines.append(
        f"  Features in same direction   : {len(same):>3}  "
        f"({100*len(same)/len(comparison_df):.0f}%)"
    )
    lines.append(
        f"  Features in opposite direction: {len(opp):>3}  "
        f"({100*len(opp)/len(comparison_df):.0f}%)"
    )
    lines.append(
        f"  Insignificant (SHAP ≈ 0)     : {len(insig):>3}  "
        f"({100*len(insig)/len(comparison_df):.0f}%)"
    )
    lines.append("")

    if len(same) > 0:
        p("Features showing SAME directional effect in GLM and XGBoost:")
        for _, r in same.iterrows():
            lines.append(
                f"  • {r['Feature']:<22}  GLM coef={r['GLM_Coef']:+.4f}  "
                f"mean SHAP={r['MeanSHAP']:+.5f}"
            )
        lines.append("")

    if len(opp) > 0:
        p("⚠  Features showing OPPOSITE directional effect:")
        for _, r in opp.iterrows():
            lines.append(
                f"  • {r['Feature']:<22}  GLM coef={r['GLM_Coef']:+.4f}  "
                f"mean SHAP={r['MeanSHAP']:+.5f}"
            )
        lines.append("")
        p(
            "Interpretation: Opposite-direction effects can arise from (a) "
            "non-linear interactions that the GLM cannot capture, (b) correlation "
            "between features causing GLM coefficient sign reversal (multicollinearity), "
            "or (c) the GLM aggregating over a population where a non-monotone "
            "relationship exists.  Each case should be investigated individually."
        )

    h2("4. INDIVIDUAL RISK ANALYSIS (WATERFALL PLOTS)")
    p(
        "Waterfall plots were generated for three representative risks: the lowest- "
        "risk observation (by summed absolute SHAP), the median-risk observation, and "
        "the highest-risk observation.  These plots decompose the model's prediction "
        "into additive feature contributions relative to the expected value (base rate)."
    )
    p(
        "Regulatory note: waterfall plots allow an underwriter or auditor to verify "
        "that the direction and magnitude of individual feature contributions are "
        "plausible and consistent with underwriting guidelines."
    )

    h2("5. KNOWN LIMITATIONS")
    p(
        "1. SHAP TreeExplainer uses interventional feature perturbation under the "
        "assumption of feature independence.  Where features are correlated (e.g., "
        "DrivAge and BonusMalus), SHAP values may distribute credit imperfectly."
    )
    p(
        "2. The dataset is a 1,000-row sample of the full freMTPL dataset.  Importance "
        "rankings and coefficient estimates may shift on the full dataset."
    )
    p(
        "3. Label-encoded categoricals are treated as ordinal by the GLM.  For a "
        "production GLM, one-hot encoding would be preferable; this would change "
        "coefficient values but not SHAP values for the XGBoost model."
    )

    h2("6. CONCLUSION")
    pct_agree = 100 * len(same) / max(len(comparison_df) - len(insig), 1)
    p(
        f"The XGBoost model shows directional agreement with the Poisson GLM for "
        f"approximately {pct_agree:.0f}% of features that are material to the model.  "
        f"This provides regulatory comfort that the ML model's risk drivers are "
        f"consistent with actuarial expectations, while also capturing non-linear "
        f"effects that the GLM cannot represent.  Full SHAP plots are provided in the "
        f"accompanying PNG files."
    )
    lines.append("")
    lines.append("End of report.")
    lines.append("")

    report_path = out_dir / "regulatory_report.txt"
    report_path.write_text("\n".join(lines), encoding="utf-8")
    log.info("Regulatory report saved: %s", report_path)


# ---------------------------------------------------------------------------
# 7. Unit tests
# ---------------------------------------------------------------------------

def run_unit_tests(df: pd.DataFrame, model: xgb.XGBRegressor) -> None:
    """Lightweight smoke tests — raise AssertionError on failure."""
    log.info("Running unit tests …")

    # T1: Dataset integrity
    assert df["Exposure"].gt(0).all(),        "T1: Exposure must be > 0"
    assert df["ClaimNb"].ge(0).all(),          "T1: ClaimNb must be >= 0"
    assert not df[MODEL_FEATURES].isnull().any().any(), "T1: No NaNs in features"
    log.info("  T1 PASSED — dataset integrity")

    # T2: Model produces finite predictions
    X_sample = df[MODEL_FEATURES].head(10)
    preds    = model.predict(X_sample)
    assert np.all(np.isfinite(preds)), "T2: Predictions must be finite"
    assert np.all(preds >= 0),          "T2: Poisson predictions must be >= 0"
    log.info("  T2 PASSED — model predictions finite and non-negative")

    # T3: SHAP values sum-to-prediction check (approximate)
    explainer   = shap.TreeExplainer(model)
    shap_vals   = explainer.shap_values(X_sample)
    base_val    = explainer.expected_value
    shap_preds  = shap_vals.sum(axis=1) + base_val
    # XGBoost Poisson: output is in log space, so compare in log space
    log_preds   = np.log(np.clip(preds, 1e-10, None))
    max_diff    = np.max(np.abs(shap_preds - log_preds))
    assert max_diff < 0.05, f"T3: SHAP sum deviates too much from prediction: {max_diff:.4f}"
    log.info("  T3 PASSED — SHAP additivity verified (max diff = %.5f)", max_diff)

    # T4: Top features list non-empty
    imp = model.get_booster().get_score(importance_type="gain")
    assert len(imp) >= 5, "T4: Model must use at least 5 features"
    log.info("  T4 PASSED — model uses %d features", len(imp))

    log.info("All unit tests passed ✓")


# ---------------------------------------------------------------------------
# 8. Main pipeline
# ---------------------------------------------------------------------------

def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # ---- Data ----------------------------------------------------------------
    df, encoders = encode_features(load_and_prepare(DATA_PATH))
    X_tr, X_te, y_tr, y_te, w_tr, w_te = build_matrices(df)

    # ---- GLM -----------------------------------------------------------------
    glm_pipe = fit_poisson_glm(X_tr, y_tr, w_tr)
    glm_df   = extract_glm_coefficients(glm_pipe, MODEL_FEATURES)

    # ---- XGBoost -------------------------------------------------------------
    model    = fit_xgboost(X_tr, y_tr, w_tr, X_te, y_te, w_te)
    gain_df  = get_gain_importance(model)

    # ---- Unit tests ----------------------------------------------------------
    run_unit_tests(df, model)

    # ---- SHAP ----------------------------------------------------------------
    shap_expl, shap_values = compute_shap_values(model, X_te)

    # Signed mean SHAP (for direction comparison with GLM)
    signed_mean_shap = shap_values.mean(axis=0)
    shap_df = pd.DataFrame({
        "Feature"    : list(X_te.columns),
        "MeanAbsSHAP": np.abs(shap_values).mean(axis=0),
        "MeanSHAP"   : signed_mean_shap,
    }).sort_values("MeanAbsSHAP", ascending=False).reset_index(drop=True)

    top5 = shap_df["Feature"].head(5).tolist()
    log.info("Top 5 features by SHAP: %s", top5)

    # ---- Plots ---------------------------------------------------------------
    plot_beeswarm(shap_expl, OUTPUT_DIR)
    plot_bar_summary(shap_expl, OUTPUT_DIR)
    plot_dependence(shap_values, X_te, top5, OUTPUT_DIR)
    plot_waterfall(shap_expl, X_te, OUTPUT_DIR)
    plot_gain_vs_shap(gain_df, shap_df, OUTPUT_DIR)
    comparison_df = plot_shap_vs_glm(shap_df, glm_df, OUTPUT_DIR)

    # ---- Regulatory report ---------------------------------------------------
    write_regulatory_report(comparison_df, gain_df, shap_df, glm_df, top5, OUTPUT_DIR)

    # ---- Console summary -----------------------------------------------------
    log.info("\n%s\n%s\n%s", "=" * 60, "SUMMARY", "=" * 60)
    log.info("Top 5 SHAP features:\n%s", shap_df.head(5).to_string(index=False))
    log.info("\nGLM vs SHAP directions:\n%s", comparison_df[["Feature","GLM_Coef","MeanSHAP","Agreement"]].to_string(index=False))
    log.info("\nAll outputs written to: %s", OUTPUT_DIR.resolve())


if __name__ == "__main__":
    main()
