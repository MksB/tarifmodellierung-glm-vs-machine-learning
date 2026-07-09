#!/usr/bin/env python3
# =============================================================================
# GLM-Analyse: freMTPL Schadenhäufigkeit und Schadenhöhe – Python-Äquivalent
# Referenz: Wüthrich & Merz, "Statistical Foundations of Actuarial Learning"
#           Kapitel 5: Generalized Linear Models
#
#          Exakte Reproduktion der R-Analyse mit statsmodels
#          Poisson GLM (Häufigkeit) + Gamma GLM (Schadenhöhe)
# =============================================================================

import warnings
warnings.filterwarnings('ignore')

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import seaborn as sns
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
from itertools import combinations
import os
import pickle

# Ausgabe-Verzeichnisse
os.makedirs("plots", exist_ok=True)
os.makedirs("models", exist_ok=True)
os.makedirs("reports", exist_ok=True)

# Plot-Stil
plt.style.use('seaborn-v0_8-whitegrid')
BLUE  = "#2C6FAC"
ORANGE = "#E05A2B"
sns.set_palette([BLUE, ORANGE, "#27AE60", "#8E44AD"])

print("=" * 70)
print("GLM-ANALYSE: freMTPL – Python mit statsmodels")
print("=" * 70)

# ============================================================================
# 1. DATENVORBEREITUNG
# ============================================================================
print("\n=== 1. Datenvorbereitung ===")

df_raw = pd.read_csv("freMTPLfreq_sev_data_1000.csv")
df_raw = df_raw.rename(columns={"...1": "row_idx"})

print(f"Beobachtungen: {len(df_raw)}")
print(f"Spalten: {list(df_raw.columns)}")
print(f"\nDatentypen:\n{df_raw.dtypes}")

# ============================================================================
# 2. EXPLORATIVE DATENANALYSE
# ============================================================================
print("\n=== 2. Explorative Datenanalyse ===")

df = df_raw.copy()

# Deskriptive Statistik
num_cols = ["Exposure", "VehPower", "VehAge", "DrivAge",
            "BonusMalus", "Density", "ClaimNb", "ClaimTotal"]
print(f"\nDeskriptive Statistik:\n{df[num_cols].describe().round(3)}")

print(f"\nAnteil ohne Schaden:     {(df.ClaimNb == 0).mean() * 100:.2f}%")
print(f"Anteil mit >= 1 Schaden: {(df.ClaimNb > 0).mean() * 100:.2f}%")
print(f"\nVerteilung ClaimNb:\n{df.ClaimNb.value_counts().sort_index()}")

# ============================================================================
# 3. FAKTORENKODIERUNG
# ============================================================================
print("\n=== 3. Faktorenkodierung ===")

# Kategoriale Variablen als pandas Categorical (entspricht R factor())
# Referenzlevel wie in R gesetzt (wird durch drop_first=True in get_dummies
# oder durch statsmodels Formula-API automatisch gehandhabt)

cat_vars = ["VehBrand", "VehGas", "Area", "Region"]
ref_levels = {
    "VehBrand": "B1",
    "VehGas":   "Diesel",
    "Area":     "A",
    "Region":   "Centre"
}

for var in cat_vars:
    # Pandas CategoricalDtype mit expliziten Levels
    levels = sorted(df[var].unique())
    # Referenzlevel an erste Stelle setzen
    if ref_levels[var] in levels:
        levels = [ref_levels[var]] + [l for l in levels if l != ref_levels[var]]
    df[var] = pd.Categorical(df[var], categories=levels, ordered=False)
    print(f"  {var:12s}: {len(levels)} Levels, Referenz = {levels[0]}")

# In statsmodels Formula-API entspricht das erste Kategorie-Level dem
# Referenzlevel (contr.treatment-Äquivalent)
print("\nKontrast: contr.treatment (Dummy-Kodierung, wie in R)")

# ============================================================================
# 4. EDA-PLOTS
# ============================================================================
print("\n=== 4. EDA-Plots ===")

fig, axes = plt.subplots(2, 3, figsize=(16, 10))
fig.suptitle("Explorative Datenanalyse – freMTPL Daten (n=1000)",
             fontsize=14, fontweight="bold")

# Plot 1: ClaimNb Verteilung
ax = axes[0, 0]
counts = df.ClaimNb.value_counts().sort_index()
ax.bar(counts.index.astype(str), counts.values, color=BLUE, edgecolor="white", alpha=0.85)
for i, v in enumerate(counts.values):
    ax.text(i, v + 1, str(v), ha='center', fontsize=10)
ax.set_title("Verteilung der Schadenhäufigkeit")
ax.set_xlabel("Anzahl Schäden"); ax.set_ylabel("Häufigkeit")

# Plot 2: ClaimNb vs. BonusMalus
ax = axes[0, 1]
jitter = np.random.uniform(-0.05, 0.05, len(df))
ax.scatter(df.BonusMalus, df.ClaimNb + jitter, alpha=0.25, s=15, color=ORANGE)
bm_bins = pd.cut(df.BonusMalus, bins=10)
mean_claims = df.groupby(bm_bins, observed=True).ClaimNb.mean()
bm_mid = [iv.mid for iv in mean_claims.index]
ax.plot(bm_mid, mean_claims.values, color=BLUE, linewidth=2, label="Mittelwert")
ax.set_title("Schadenhäufigkeit vs. BonusMalus")
ax.set_xlabel("BonusMalus"); ax.set_ylabel("Anzahl Schäden")
ax.legend()

# Plot 3: ClaimNb vs. DrivAge
ax = axes[0, 2]
age_bins = pd.cut(df.DrivAge, bins=10)
mean_claims_age = df.groupby(age_bins, observed=True).ClaimNb.mean()
age_mid = [iv.mid for iv in mean_claims_age.index]
ax.scatter(df.DrivAge, df.ClaimNb + jitter, alpha=0.25, s=15, color=ORANGE)
ax.plot(age_mid, mean_claims_age.values, color=BLUE, linewidth=2, label="Mittelwert")
ax.set_title("Schadenhäufigkeit vs. Fahreralter")
ax.set_xlabel("Fahreralter"); ax.set_ylabel("Anzahl Schäden")
ax.legend()

# Plot 4: Exposure-Verteilung
ax = axes[1, 0]
ax.hist(df.Exposure, bins=30, color=BLUE, edgecolor="white", alpha=0.85)
ax.set_title("Verteilung der Exposure")
ax.set_xlabel("Exposure (Jahre)"); ax.set_ylabel("Häufigkeit")

# Plot 5: ClaimTotal (positiv)
ax = axes[1, 1]
df_pos = df[df.ClaimTotal > 0]
ax.hist(np.log10(df_pos.ClaimTotal + 1), bins=20, color=ORANGE,
        edgecolor="white", alpha=0.85)
ax.set_title(f"Schadenhöhe log₁₀-Skala (n={len(df_pos)})")
ax.set_xlabel("log₁₀(Schadenhöhe)"); ax.set_ylabel("Häufigkeit")

# Plot 6: Schadenhäufigkeit nach Region
ax = axes[1, 2]
region_rate = (df.groupby("Region", observed=True)
               .apply(lambda g: g.ClaimNb.sum() / g.Exposure.sum())
               .sort_values())
region_rate.plot(kind="barh", ax=ax, color=BLUE, alpha=0.85)
ax.set_title("Schadenhäufigkeit nach Region")
ax.set_xlabel("Schäden / Exposure-Jahr"); ax.set_ylabel("")
ax.tick_params(axis='y', labelsize=7)

plt.tight_layout()
plt.savefig("plots/eda_overview.png", dpi=150, bbox_inches="tight")
plt.close()
print("EDA-Plot gespeichert: plots/eda_overview.png")

# ============================================================================
# 5. POISSON GLM – VOLLSTÄNDIGES MODELL
# ============================================================================
print("\n=== 5. Poisson GLM – Vollständiges Modell ===")

# Offset: log(Exposure) → entspricht R: offset(log(Exposure))
df["log_exposure"] = np.log(df["Exposure"])

# Formel: alle Prädiktoren
# statsmodels Formula-API nutzt automatisch das erste Kategorie-Level
# als Referenz → identisch zu R contr.treatment
formula_full_poisson = (
    "ClaimNb ~ VehPower + VehAge + DrivAge + BonusMalus + "
    "C(VehBrand) + C(VehGas) + C(Area) + Density + C(Region)"
)

poisson_full = smf.glm(
    formula=formula_full_poisson,
    data=df,
    family=sm.families.Poisson(link=sm.families.links.Log()),
    offset=df["log_exposure"]
).fit()

print(f"Null-Deviance:     {poisson_full.null_deviance:.2f}")
print(f"Residual-Deviance: {poisson_full.deviance:.2f}  (df={poisson_full.df_resid:.0f})")
print(f"AIC:               {poisson_full.aic:.2f}")

# ============================================================================
# 6. AIC/BIC-BASIERTE VARIABLENSELEKTION
# ============================================================================
print("\n=== 6. Variablenselektion (AIC/BIC) – Stepwise ===")
print("Hinweis: statsmodels hat keine eingebaute step()-Funktion.")
print("Implementierung: manuelle Rückwärtsselektion mit AIC-Kriterium\n")

def stepwise_selection(formula_full, data, family, offset=None,
                       criterion="bic", direction="backward", verbose=True):
    """
    Schrittweise Modellselektion für statsmodels GLM.
    
    Parameter:
    ----------
    formula_full : str    – vollständige Formel
    data         : df     – Datensatz
    family       : obj    – statsmodels Family-Objekt
    offset       : Series – Offset-Variable (optional)
    criterion    : str    – "aic" oder "bic"
    direction    : str    – "backward" (nur Rückwärtsselektion implementiert)
    verbose      : bool   – Ausgabe des Prozesses
    
    Returns:
    --------
    best_model : fitted GLM
    history    : list of dicts mit Schritt-Protokoll
    """
    n = len(data)
    k_factor = 2 if criterion == "aic" else np.log(n)
    crit_name = criterion.upper()
    
    # Startmodell: vollständiges Modell
    fit_kwargs = {"family": family}
    if offset is not None:
        fit_kwargs["offset"] = offset
    
    current_formula = formula_full
    current_model = smf.glm(formula=current_formula, data=data,
                            **fit_kwargs).fit()
    
    # AIC/BIC manuell berechnen: -2*loglik + k*p
    def compute_crit(model):
        return -2 * model.llf + k_factor * (model.df_model + 1)
    
    current_crit = compute_crit(current_model)
    history = [{"step": 0, "removed": "none", crit_name: current_crit,
                "formula": current_formula}]
    
    if verbose:
        print(f"  Startmodell {crit_name}: {current_crit:.2f}")
    
    # Terme extrahieren (ohne Intercept und Offset)
    terms = [t.strip() for t in current_formula.split("~")[1].split("+")]
    terms = [t for t in terms if t and "offset" not in t.lower()]
    
    improved = True
    step = 0
    while improved and len(terms) > 1:
        improved = False
        best_crit = current_crit
        best_term = None
        best_formula = current_formula
        
        for term in terms:
            # Terme entfernen
            remaining = [t for t in terms if t != term]
            new_formula = formula_full.split("~")[0].strip() + " ~ " + \
                          " + ".join(remaining)
            try:
                new_model = smf.glm(formula=new_formula, data=data,
                                    **fit_kwargs).fit(disp=0)
                new_crit = compute_crit(new_model)
                if new_crit < best_crit:
                    best_crit = new_crit
                    best_term = term
                    best_formula = new_formula
                    best_model_candidate = new_model
            except Exception as e:
                continue
        
        if best_term is not None:
            improved = True
            step += 1
            terms = [t for t in terms if t != best_term]
            current_formula = best_formula
            current_model = best_model_candidate
            current_crit = best_crit
            history.append({
                "step": step,
                "removed": best_term.strip(),
                crit_name: current_crit,
                "formula": current_formula
            })
            if verbose:
                print(f"  Schritt {step}: Entfernt '{best_term.strip()}'  "
                      f"→ {crit_name}={current_crit:.2f}")
    
    if verbose:
        print(f"\n  Finale Terme: {terms}")
        print(f"  Finaler {crit_name}: {current_crit:.2f}")
    
    return current_model, history


# BIC-Selektion für Poisson
print("--- BIC-Selektion (Poisson) ---")
poisson_bic_model, bic_history = stepwise_selection(
    formula_full=formula_full_poisson,
    data=df,
    family=sm.families.Poisson(link=sm.families.links.Log()),
    offset=df["log_exposure"],
    criterion="bic",
    verbose=True
)

print(f"\nFinales Poisson BIC-Modell:")
print(f"  AIC = {poisson_bic_model.aic:.2f}")
print(f"  BIC = {poisson_bic_model.bic:.2f}")
print(f"  Deviance = {poisson_bic_model.deviance:.2f}")

# Selektions-Protokoll
history_df = pd.DataFrame(bic_history)
print(f"\nSelektions-Protokoll:\n{history_df.to_string(index=False)}")

# Ausgewähltes Modell
poisson_selected = poisson_bic_model
selected_formula = list(bic_history)[-1]["formula"]
print(f"\nGewählte Formel:\n{selected_formula}")

# ============================================================================
# 7. INTERAKTIONSTERME
# ============================================================================
print("\n=== 7. Interaktionsterme ===")
print("Test auf relevante Interaktionen mit Likelihood-Ratio-Test\n")

fit_kwargs_pois = {
    "family": sm.families.Poisson(link=sm.families.links.Log()),
    "offset": df["log_exposure"]
}

def lr_test(model_restricted, model_full):
    """Likelihood-Ratio-Test (entspricht anova(..., test='Chisq') in R)"""
    lr_stat = -2 * (model_restricted.llf - model_full.llf)
    df_diff = model_full.df_model - model_restricted.df_model
    p_val = 1 - stats.chi2.cdf(lr_stat, df=max(df_diff, 1))
    return lr_stat, max(df_diff, 1), p_val

interactions_to_test = [
    ("DrivAge:BonusMalus",   "DrivAge * BonusMalus",  "DrivAge * BonusMalus"),
    ("VehAge:DrivAge",       "VehAge * DrivAge",       "VehAge * DrivAge"),
]

interaction_results = []
base_formula_ia = selected_formula

for ia_str, ia_r_name, ia_label in interactions_to_test:
    # Interaktionsterm zur Formel hinzufügen
    test_formula = base_formula_ia + f" + {ia_str}"
    try:
        model_ia = smf.glm(formula=test_formula, data=df,
                           **fit_kwargs_pois).fit(disp=0)
        lr_stat, df_diff, p_val = lr_test(poisson_selected, model_ia)
        sig = "***" if p_val < 0.001 else ("**" if p_val < 0.01 else
              ("*" if p_val < 0.05 else ""))
        print(f"  {ia_label:30s}  LR={lr_stat:.4f}  df={df_diff}  "
              f"p={p_val:.4f}  {sig}")
        interaction_results.append({
            "interaction": ia_str,
            "lr_stat": lr_stat,
            "df": df_diff,
            "p_value": p_val,
            "significant": p_val < 0.05,
            "model": model_ia
        })
    except Exception as e:
        print(f"  {ia_label:30s}  Fehler: {e}")

# Signifikante Interaktionen aufnehmen
final_formula = base_formula_ia
poisson_final = poisson_selected

for res in interaction_results:
    if res["significant"]:
        final_formula = final_formula + f" + {res['interaction']}"
        print(f"  → '{res['interaction']}' aufgenommen (p={res['p_value']:.4f})")

if any(r["significant"] for r in interaction_results):
    poisson_final = smf.glm(formula=final_formula, data=df,
                            **fit_kwargs_pois).fit()
    print(f"\nFinales Modell mit Interaktionen: AIC={poisson_final.aic:.2f}")
else:
    print("\n→ Keine Interaktionen signifikant. Haupteffekt-Modell beibehalten.")
    poisson_final = poisson_selected

print(f"\nFinales Poisson-Modell: AIC={poisson_final.aic:.2f}, "
      f"Deviance={poisson_final.deviance:.2f}")

# ============================================================================
# 8. OVERDISPERSION-TEST
# ============================================================================
print("\n=== 8. Overdispersion-Test ===")

pearson_resid_p = poisson_final.resid_pearson
dispersion_p = np.sum(pearson_resid_p**2) / poisson_final.df_resid
print(f"Pearson χ² / df = {dispersion_p:.4f}")

if dispersion_p > 1.5:
    print("→ ACHTUNG: Overdispersion vorhanden (> 1.5)!")
    print("  Empfehlung: Quasi-Poisson oder Negativ-Binomial")
    # Formaler Test: Dean (1992) / AER dispersiontest-Äquivalent
    # H0: phi=1 (equidispersion)
    mu_hat = poisson_final.fittedvalues
    z_score = (pearson_resid_p**2 - 1) / np.sqrt(2)
    aux_reg = sm.OLS(z_score, mu_hat).fit()
    print(f"  Overdispersion-Koeffizient (AER-Äquivalent): "
          f"alpha={aux_reg.params[0]:.4f}, p={aux_reg.pvalues[0]:.4f}")
elif dispersion_p > 1.0:
    print("→ Leichte Overdispersion (1.0 < φ ≤ 1.5). Poisson akzeptabel.")
else:
    print("→ Kein Overdispersionsproblem.")

# ============================================================================
# 9. MODELLDIAGNOSE – POISSON
# ============================================================================
print("\n=== 9. Modelldiagnose (Poisson) ===")

dev_resid_p = poisson_final.resid_deviance
fitted_p = poisson_final.fittedvalues
influence_p = poisson_final.get_influence()
hat_p = influence_p.hat_matrix_diag
cooks_p = influence_p.cooks_distance[0]

print(f"Deviance-Residuen: Min={dev_resid_p.min():.3f}, "
      f"Median={np.median(dev_resid_p):.3f}, Max={dev_resid_p.max():.3f}")

n = len(df)
influential_idx = np.where(cooks_p > 4 / n)[0]
print(f"Einflussreiche Beobachtungen (Cook > 4/n={4/n:.4f}): "
      f"{len(influential_idx)}")

fig, axes = plt.subplots(2, 2, figsize=(14, 10))
fig.suptitle("Modelldiagnose – Poisson GLM (Schadenhäufigkeit)",
             fontsize=13, fontweight="bold")

# Plot 1: Deviance-Residuen vs. Fitted
ax = axes[0, 0]
ax.scatter(np.log(fitted_p + 1e-10), dev_resid_p, alpha=0.35, s=20, color=BLUE)
ax.axhline(0, color="red", linestyle="--", linewidth=1)
z = np.polyfit(np.log(fitted_p + 1e-10), dev_resid_p, 3)
p_poly = np.poly1d(z)
x_sorted = np.sort(np.log(fitted_p + 1e-10))
ax.plot(x_sorted, p_poly(x_sorted), color=ORANGE, linewidth=1.5, label="Loess")
ax.set_title("Deviance-Residuen vs. log(Fitted)")
ax.set_xlabel("log(Fitted Values)"); ax.set_ylabel("Deviance-Residuen")
ax.legend(fontsize=9)

# Plot 2: QQ-Plot
ax = axes[0, 1]
(osm, osr), (slope, intercept, _) = stats.probplot(dev_resid_p, dist="norm")
ax.scatter(osm, osr, alpha=0.4, s=20, color=BLUE)
ax.plot(osm, slope * np.array(osm) + intercept, color="red",
        linestyle="--", linewidth=1.5)
ax.set_title("QQ-Plot der Deviance-Residuen")
ax.set_xlabel("Theoretische Quantile"); ax.set_ylabel("Empirische Quantile")

# Plot 3: Cook's Distance
ax = axes[1, 0]
ax.bar(range(n), cooks_p, color=BLUE, alpha=0.6, width=1.0)
ax.axhline(4 / n, color="red", linestyle="--", linewidth=1.5,
           label=f"Schwellenwert 4/n={4/n:.4f}")
ax.set_title("Cook's Distance")
ax.set_xlabel("Beobachtungsindex"); ax.set_ylabel("Cook's Distance")
ax.legend(fontsize=9)

# Plot 4: Residuen vs. Leverage
ax = axes[1, 1]
ax.scatter(hat_p, dev_resid_p, alpha=0.35, s=20, color=BLUE)
for y_line in [-2, 0, 2]:
    ax.axhline(y_line, color="orange" if y_line != 0 else "red",
               linestyle="--", linewidth=1)
p_thresh = 2 * poisson_final.df_model / n
ax.axvline(p_thresh, color="gray", linestyle="--", linewidth=1,
           label=f"Leverage-Grenze: {p_thresh:.4f}")
ax.set_title("Residuen vs. Leverage")
ax.set_xlabel("Leverage (Hat-Werte)"); ax.set_ylabel("Deviance-Residuen")
ax.legend(fontsize=9)

plt.tight_layout()
plt.savefig("plots/poisson_diagnostics.png", dpi=150, bbox_inches="tight")
plt.close()
print("Diagnose-Plot gespeichert: plots/poisson_diagnostics.png")

# ============================================================================
# 10. POISSON – KOEFFIZIENTEN-TABELLE
# ============================================================================
print("\n=== 10. Poisson GLM – Koeffizienten-Tabelle ===")

conf_int_p = poisson_final.conf_int(alpha=0.05)
coef_df_p = pd.DataFrame({
    "Estimate":  poisson_final.params,
    "Std_Error": poisson_final.bse,
    "z_Wert":    poisson_final.tvalues,
    "p_Wert":    poisson_final.pvalues,
    "CI_lower":  conf_int_p.iloc[:, 0],
    "CI_upper":  conf_int_p.iloc[:, 1],
})

def signif_stars(p):
    if p < 0.001: return "***"
    elif p < 0.01: return "**"
    elif p < 0.05: return "*"
    elif p < 0.10: return "."
    return ""

coef_df_p["Signif"] = coef_df_p["p_Wert"].apply(signif_stars)
coef_df_p = coef_df_p.round(4)

# Ausgabe formatieren
print(f"\n{'Variable':<42} {'Estimate':>8} {'Std.Err':>8} {'z-Wert':>8} "
      f"{'p-Wert':>10} {'CI_low':>8} {'CI_up':>8} {'Sign.':>5}")
print("-" * 110)
for idx, row in coef_df_p.iterrows():
    print(f"{str(idx):<42} {row['Estimate']:>8.4f} {row['Std_Error']:>8.4f} "
          f"{row['z_Wert']:>8.3f} {row['p_Wert']:>10.4f} "
          f"{row['CI_lower']:>8.4f} {row['CI_upper']:>8.4f} {row['Signif']:>5}")

sig_count = (coef_df_p["Signif"] != "").sum()
total_count = len(coef_df_p) - 1  # ohne Intercept
print(f"\nSignifikante Koeffizienten (p<0.05): {sig_count} von {total_count}")

# CSV speichern
coef_df_p.to_csv("reports/poisson_coefficients.csv")
print("Koeffizienten gespeichert: reports/poisson_coefficients.csv")

# ============================================================================
# 11. GAMMA GLM – SCHADENHÖHE
# ============================================================================
print("\n=== 11. Gamma GLM – Schadenhöhe ===")

# Nur Policen mit positivem Schaden
df_sev = df[df.ClaimTotal > 0].copy()
df_sev["AvgClaimSev"] = df_sev["ClaimTotal"] / df_sev["ClaimNb"]
n_sev = len(df_sev)

print(f"Beobachtungen mit Schäden: {n_sev}")
print(f"Mittlere Schadenhöhe:      {df_sev.AvgClaimSev.mean():.2f} EUR")
print(f"Std.-abw. Schadenhöhe:     {df_sev.AvgClaimSev.std():.2f} EUR")
print(f"Median Schadenhöhe:        {df_sev.AvgClaimSev.median():.2f} EUR")

# Vollständiges Gamma-Modell
# family=Gamma(link=log) entspricht R: Gamma(link="log")
formula_full_gamma = (
    "AvgClaimSev ~ VehPower + VehAge + DrivAge + BonusMalus + "
    "C(VehBrand) + C(VehGas) + C(Area) + Density + C(Region)"
)

fit_kwargs_gamma = {
    "family": sm.families.Gamma(link=sm.families.links.Log())
}

gamma_full = smf.glm(
    formula=formula_full_gamma,
    data=df_sev,
    **fit_kwargs_gamma
).fit()

print(f"\nGamma Vollmodell AIC:      {gamma_full.aic:.2f}")
print(f"Residual-Deviance:         {gamma_full.deviance:.4f}")
print(f"Dispersionsparameter (φ):  {gamma_full.scale:.4f}")
print(f"Shape-Parameter (k=1/φ):  {1/gamma_full.scale:.4f}")

# BIC-Selektion für Gamma
print("\n--- BIC-Selektion (Gamma) ---")
gamma_bic_model, gamma_bic_history = stepwise_selection(
    formula_full=formula_full_gamma,
    data=df_sev,
    family=sm.families.Gamma(link=sm.families.links.Log()),
    offset=None,
    criterion="bic",
    verbose=True
)

gamma_final = gamma_bic_model
print(f"\nFinales Gamma-Modell: AIC={gamma_final.aic:.2f}, "
      f"φ={gamma_final.scale:.4f}, k={1/gamma_final.scale:.4f}")

# ============================================================================
# 12. GAMMA GLM – DIAGNOSE
# ============================================================================
print("\n=== 12. Gamma GLM – Modelldiagnose ===")

dev_resid_g = gamma_final.resid_deviance
fitted_g = gamma_final.fittedvalues
pearson_resid_g = gamma_final.resid_pearson
influence_g = gamma_final.get_influence()
hat_g = influence_g.hat_matrix_diag
cooks_g = influence_g.cooks_distance[0]

disp_gamma_val = np.sum(pearson_resid_g**2) / gamma_final.df_resid
print(f"Pearson χ² / df (Gamma) = {disp_gamma_val:.4f}")

fig, axes = plt.subplots(2, 2, figsize=(14, 10))
fig.suptitle("Modelldiagnose – Gamma GLM (Schadenhöhe)",
             fontsize=13, fontweight="bold")

# Plot 1
ax = axes[0, 0]
ax.scatter(np.log(fitted_g), dev_resid_g, alpha=0.5, s=25, color=ORANGE)
ax.axhline(0, color="red", linestyle="--")
ax.set_title("Deviance-Residuen vs. log(Fitted)")
ax.set_xlabel("log(Fitted Values)"); ax.set_ylabel("Deviance-Residuen")

# Plot 2: QQ
ax = axes[0, 1]
(osm, osr), (slope, intercept, _) = stats.probplot(dev_resid_g, dist="norm")
ax.scatter(osm, osr, alpha=0.5, s=25, color=ORANGE)
ax.plot(osm, slope * np.array(osm) + intercept, color="red",
        linestyle="--", linewidth=1.5)
ax.set_title("QQ-Plot der Deviance-Residuen (Gamma)")
ax.set_xlabel("Theoretische Quantile"); ax.set_ylabel("Empirische Quantile")

# Plot 3: Cook's Distance
ax = axes[1, 0]
ax.bar(range(n_sev), cooks_g, color=ORANGE, alpha=0.65, width=1.0)
ax.axhline(4 / n_sev, color="red", linestyle="--",
           label=f"4/n={4/n_sev:.4f}")
ax.set_title("Cook's Distance (Gamma)")
ax.set_xlabel("Beobachtungsindex"); ax.set_ylabel("Cook's Distance")
ax.legend(fontsize=9)

# Plot 4: Leverage
ax = axes[1, 1]
ax.scatter(hat_g, dev_resid_g, alpha=0.5, s=25, color=ORANGE)
for y_line in [-2, 0, 2]:
    ax.axhline(y_line, color="orange" if y_line != 0 else "red",
               linestyle="--", linewidth=1)
ax.set_title("Residuen vs. Leverage (Gamma)")
ax.set_xlabel("Leverage"); ax.set_ylabel("Deviance-Residuen")

plt.tight_layout()
plt.savefig("plots/gamma_diagnostics.png", dpi=150, bbox_inches="tight")
plt.close()
print("Gamma-Diagnose gespeichert: plots/gamma_diagnostics.png")

# ============================================================================
# 13. GAMMA GLM – KOEFFIZIENTEN-TABELLE
# ============================================================================
print("\n=== 13. Gamma GLM – Koeffizienten-Tabelle ===")

conf_int_g = gamma_final.conf_int(alpha=0.05)
coef_df_g = pd.DataFrame({
    "Estimate":  gamma_final.params,
    "Std_Error": gamma_final.bse,
    "t_Wert":    gamma_final.tvalues,
    "p_Wert":    gamma_final.pvalues,
    "CI_lower":  conf_int_g.iloc[:, 0],
    "CI_upper":  conf_int_g.iloc[:, 1],
})
coef_df_g["Signif"] = coef_df_g["p_Wert"].apply(signif_stars)
coef_df_g = coef_df_g.round(4)

print(f"\n{'Variable':<42} {'Estimate':>8} {'Std.Err':>8} {'t-Wert':>8} "
      f"{'p-Wert':>10} {'CI_low':>8} {'CI_up':>8} {'Sign.':>5}")
print("-" * 110)
for idx, row in coef_df_g.iterrows():
    print(f"{str(idx):<42} {row['Estimate']:>8.4f} {row['Std_Error']:>8.4f} "
          f"{row['t_Wert']:>8.3f} {row['p_Wert']:>10.4f} "
          f"{row['CI_lower']:>8.4f} {row['CI_upper']:>8.4f} {row['Signif']:>5}")

coef_df_g.to_csv("reports/gamma_coefficients.csv")
print("Gamma-Koeffizienten gespeichert: reports/gamma_coefficients.csv")

# ============================================================================
# 14. MODELLE SPEICHERN
# ============================================================================
print("\n=== 14. Modelle speichern ===")

# statsmodels GLMResults können Probleme beim pickle in isolierten Umgebungen
# haben. Wir speichern daher die Modellparameter und Metadaten als JSON/CSV.
model_info_poisson = {
    "aic": float(poisson_final.aic),
    "deviance": float(poisson_final.deviance),
    "df_resid": float(poisson_final.df_resid),
    "llf": float(poisson_final.llf),
    "formula": final_formula,
    "nobs": float(poisson_final.nobs),
}
model_info_gamma = {
    "aic": float(gamma_final.aic),
    "deviance": float(gamma_final.deviance),
    "df_resid": float(gamma_final.df_resid),
    "scale": float(gamma_final.scale),
    "llf": float(gamma_final.llf),
    "nobs": float(gamma_final.nobs),
}
import json
with open("models/poisson_glm_meta.json", "w") as f:
    json.dump(model_info_poisson, f, indent=2)
with open("models/gamma_glm_meta.json", "w") as f:
    json.dump(model_info_gamma, f, indent=2)

# Koeffizienten separat speichern
coef_df_p.to_csv("models/poisson_glm_coefs.csv")
coef_df_g.to_csv("models/gamma_glm_coefs.csv")

print(f"Poisson GLM Meta: AIC={model_info_poisson['aic']:.2f} ✓")
print(f"Gamma GLM Meta:   AIC={model_info_gamma['aic']:.2f} ✓")
print("Modelle gespeichert als JSON+CSV (statsmodels Serialisierungs-Format)")

# Modell-Summary in Textdatei
with open("reports/poisson_summary.txt", "w") as f:
    f.write(str(poisson_final.summary()))
with open("reports/gamma_summary.txt", "w") as f:
    f.write(str(gamma_final.summary()))
print("Model-Summaries gespeichert.")

# ============================================================================
# 15. VERGLEICH R vs. PYTHON + ML-AUSBLICK
# ============================================================================
print("\n=== 15. Vergleich R vs. Python + ML-Ausblick ===")

# In-sample Vorhersagen
df["pred_nb_glm"] = poisson_final.predict()
df["pred_freq_glm"] = df["pred_nb_glm"] / df["Exposure"]

rmse_p = np.sqrt(np.mean((df["ClaimNb"] - df["pred_nb_glm"])**2))
mae_p  = np.mean(np.abs(df["ClaimNb"] - df["pred_nb_glm"]))
spearman_r = stats.spearmanr(df["pred_nb_glm"], df["ClaimNb"]).statistic

print(f"Poisson GLM In-Sample RMSE:              {rmse_p:.6f}")
print(f"Poisson GLM In-Sample MAE:               {mae_p:.6f}")
print(f"Mittl. Schadenhäufigkeit (beob.):        {df.ClaimNb.mean():.6f}")
print(f"Mittl. Schadenhäufigkeit (Modell):       {df.pred_nb_glm.mean():.6f}")
print(f"Spearman-Korrelation (Pred. vs. Actual): {spearman_r:.4f}")

# Vergleichsplot: Predicted vs. Actual (Frequenz)
fig, axes = plt.subplots(1, 2, figsize=(14, 5))
fig.suptitle("Modellvalidierung – GLM In-Sample",
             fontsize=13, fontweight="bold")

ax = axes[0]
bins = np.linspace(0, df.pred_nb_glm.quantile(0.99), 30)
ax.hist(df["pred_nb_glm"], bins=bins, color=BLUE, alpha=0.7, label="Predicted")
ax.axvline(df.ClaimNb.mean(), color="red", linestyle="--",
           label=f"Beob. Mittel: {df.ClaimNb.mean():.4f}")
ax.axvline(df.pred_nb_glm.mean(), color=ORANGE, linestyle="--",
           label=f"Pred. Mittel: {df.pred_nb_glm.mean():.4f}")
ax.set_title("Verteilung der vorhergesagten Schadenanzahl")
ax.set_xlabel("Vorhergesagte Schadenanzahl"); ax.set_ylabel("Häufigkeit")
ax.legend(fontsize=9)

ax = axes[1]
# Lorenz-Kurve (Gini-Approximation)
sort_idx = np.argsort(df["pred_freq_glm"])
cum_exposure = np.cumsum(df["Exposure"].iloc[sort_idx]) / df["Exposure"].sum()
cum_claims = np.cumsum(df["ClaimNb"].iloc[sort_idx]) / df["ClaimNb"].sum()
ax.plot(cum_exposure, cum_claims, color=BLUE, linewidth=2, label="GLM Lorenz")
ax.plot([0, 1], [0, 1], color="gray", linestyle="--", label="Gleichverteilung")
gini = 1 - 2 * np.trapezoid(cum_claims, cum_exposure)
ax.set_title(f"Lorenz-Kurve (Gini ≈ {gini:.4f})")
ax.set_xlabel("Kumulierter Anteil Exposure")
ax.set_ylabel("Kumulierter Anteil Schäden")
ax.legend(fontsize=9)

plt.tight_layout()
plt.savefig("plots/model_validation.png", dpi=150, bbox_inches="tight")
plt.close()
print("Validierungs-Plot gespeichert: plots/model_validation.png")

# Summary-Tabelle für Report
summary_table = pd.DataFrame({
    "Modell":     ["Poisson GLM", "Gamma GLM"],
    "Zielvariable": ["ClaimNb (Häufigkeit)", "AvgClaimSev (Schwere)"],
    "Family":     ["Poisson(log)", "Gamma(log)"],
    "n":          [len(df), n_sev],
    "AIC":        [round(poisson_final.aic, 2), round(gamma_final.aic, 2)],
    "Deviance":   [round(poisson_final.deviance, 2), round(gamma_final.deviance, 2)],
    "df_resid":   [poisson_final.df_resid, gamma_final.df_resid],
    "Dispersion": [round(dispersion_p, 4), round(disp_gamma_val, 4)],
})
print(f"\nModell-Übersicht:\n{summary_table.to_string(index=False)}")
summary_table.to_csv("reports/model_summary.csv", index=False)

print("\n" + "=" * 70)
print("PYTHON-ANALYSE ABGESCHLOSSEN")
print(f"Poisson GLM: {len(poisson_final.params)} Koeffizienten, AIC={poisson_final.aic:.2f}")
print(f"Gamma GLM:   {len(gamma_final.params)} Koeffizienten, AIC={gamma_final.aic:.2f}")
print("=" * 70)
