# =============================================================================
# GLM-Analyse: freMTPL Schadenhäufigkeit und Schadenhöhe
# Referenz: Wüthrich & Merz, "Statistical Foundations of Actuarial Learning"
#           Kapitel 5: Generalized Linear Models
#
# =============================================================================

# ---- 0. Pakete laden -------------------------------------------------------
# Alle benötigten Pakete werden geladen. Falls nicht vorhanden: install.packages()
required_packages <- c("ggplot2", "dplyr", "MASS", "car", "broom",
                       "gridExtra", "scales", "AER", "lmtest")
for (pkg in required_packages) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    install.packages(pkg, repos = "https://cran.r-project.org")
    library(pkg, character.only = TRUE)
  }
}

# ---- 1. Datenvorbereitung --------------------------------------------------
# Einlesen der freMTPL-Frequenz-/Schadendaten (1000 Beobachtungen)
# Quelle: CASdatasets / R-Paket freMTPLfreq
cat("=== 1. Datenvorbereitung ===\n")

data_path <- "freMTPLfreq_sev_data_1000.csv"
df_raw <- read.csv(data_path, stringsAsFactors = FALSE)

# Umbenennen des Index-Spalte (R-Konvention: Punkt statt Leerzeichen)
names(df_raw)[1] <- "row_idx"

cat(sprintf("Geladene Beobachtungen: %d\n", nrow(df_raw)))
cat(sprintf("Spalten: %s\n", paste(names(df_raw), collapse = ", ")))

# ---- 2. Explorative Datenanalyse (EDA) -------------------------------------
cat("\n=== 2. Explorative Datenanalyse ===\n")

# Zusammenfassung der numerischen Variablen
print(summary(df_raw[, c("Exposure", "VehPower", "VehAge", "DrivAge",
                           "BonusMalus", "Density", "ClaimNb", "ClaimTotal")]))

# Schadenquoten
cat(sprintf("\nAnteil Policen ohne Schaden:     %.2f%%\n",
            mean(df_raw$ClaimNb == 0) * 100))
cat(sprintf("Anteil Policen mit >= 1 Schaden: %.2f%%\n",
            mean(df_raw$ClaimNb > 0) * 100))
cat(sprintf("Max. Schadenzahl pro Police:     %d\n", max(df_raw$ClaimNb)))

# Verteilung der Schadenanzahl
cat("\nVerteilung ClaimNb:\n")
print(table(df_raw$ClaimNb))

# Expositionsstatistik
cat(sprintf("\nExposure: min=%.3f, median=%.3f, mean=%.3f, max=%.3f\n",
            min(df_raw$Exposure), median(df_raw$Exposure),
            mean(df_raw$Exposure), max(df_raw$Exposure)))

# ---- 3. Faktorenkodierung --------------------------------------------------
# Wüthrich & Merz Kap. 5.1: Kategoriale Variablen als Faktoren mit
# definierten Referenzlevels. contr.treatment (Standard) bedeutet:
# Referenzlevel = erstes Level → alle anderen Level werden als Abweichung
# vom Referenz kodiert. Für Tarifraumanalysen üblich.
cat("\n=== 3. Faktorenkodierung ===\n")

# Kopie für Modellierung
df <- df_raw

# --- Kategoriale Variablen als Faktor konvertieren ---
# VehBrand: Referenz = B1 (häufigste / günstigste Klasse)
df$VehBrand <- factor(df$VehBrand)
df$VehBrand <- relevel(df$VehBrand, ref = "B1")

# VehGas: Referenz = Diesel (Baseline für Kraftstoffart)
df$VehGas <- factor(df$VehGas)
df$VehGas <- relevel(df$VehGas, ref = "Diesel")

# Area: Referenz = A (ländlichste Zone, geringstes Risiko)
df$Area <- factor(df$Area, levels = c("A", "B", "C", "D", "E", "F"))

# Region: Referenz = Centre (mittleres Risiko)
df$Region <- factor(df$Region)
df$Region <- relevel(df$Region, ref = "Centre")

# Kontraste: contr.treatment (Standard, Dummy-Kodierung)
# → Interpretation: jeder Koeffizient gibt Abweichung vom Referenzlevel an
options(contrasts = c("contr.treatment", "contr.poly"))
cat("Kontrast-Typ: contr.treatment (Dummy-Kodierung)\n")
cat("Referenzlevels:\n")
cat(sprintf("  VehBrand: %s\n", levels(df$VehBrand)[1]))
cat(sprintf("  VehGas:   %s\n", levels(df$VehGas)[1]))
cat(sprintf("  Area:     %s\n", levels(df$Area)[1]))
cat(sprintf("  Region:   %s\n", levels(df$Region)[1]))

# Anzahl der Levels prüfen
cat("\nAnzahl der Faktor-Levels:\n")
for (v in c("VehBrand", "VehGas", "Area", "Region")) {
  cat(sprintf("  %-10s: %d Levels\n", v, nlevels(df[[v]])))
}

# ---- 4. EDA-Plots ----------------------------------------------------------
cat("\n=== 4. EDA-Plots ===\n")

# Plot 1: Verteilung ClaimNb
p1 <- ggplot(df, aes(x = factor(ClaimNb))) +
  geom_bar(fill = "#2C6FAC", color = "white", alpha = 0.85) +
  geom_text(stat = "count", aes(label = after_stat(count)),
            vjust = -0.3, size = 3.5) +
  labs(title = "Verteilung der Schadenhäufigkeit",
       subtitle = "freMTPL-Daten (n=1000)",
       x = "Anzahl Schäden", y = "Häufigkeit") +
  theme_minimal(base_size = 12)

# Plot 2: ClaimNb vs. BonusMalus
p2 <- ggplot(df, aes(x = BonusMalus, y = ClaimNb)) +
  geom_jitter(alpha = 0.3, width = 0, height = 0.1, color = "#E05A2B") +
  geom_smooth(method = "gam", se = TRUE, color = "#2C6FAC") +
  labs(title = "Schadenhäufigkeit vs. BonusMalus",
       x = "BonusMalus", y = "Anzahl Schäden") +
  theme_minimal(base_size = 12)

# Plot 3: ClaimNb vs. DrivAge
p3 <- ggplot(df, aes(x = DrivAge, y = ClaimNb)) +
  geom_jitter(alpha = 0.3, width = 0, height = 0.1, color = "#E05A2B") +
  geom_smooth(method = "loess", se = TRUE, color = "#2C6FAC") +
  labs(title = "Schadenhäufigkeit vs. Fahreralter",
       x = "Fahreralter", y = "Anzahl Schäden") +
  theme_minimal(base_size = 12)

# Plot 4: Exposure-Verteilung
p4 <- ggplot(df, aes(x = Exposure)) +
  geom_histogram(bins = 30, fill = "#2C6FAC", color = "white", alpha = 0.85) +
  labs(title = "Verteilung der Exposure",
       x = "Exposure (Jahre)", y = "Häufigkeit") +
  theme_minimal(base_size = 12)

# Plot 5: ClaimTotal Verteilung (nur positive Schäden)
df_claims <- df[df$ClaimTotal > 0, ]
p5 <- ggplot(df_claims, aes(x = ClaimTotal)) +
  geom_histogram(bins = 20, fill = "#E05A2B", color = "white", alpha = 0.85) +
  scale_x_log10(labels = scales::comma) +
  labs(title = "Verteilung der Schadenhöhe (log-Skala)",
       subtitle = sprintf("Nur positive Schäden (n=%d)", nrow(df_claims)),
       x = "Schadenhöhe (log)", y = "Häufigkeit") +
  theme_minimal(base_size = 12)

# Plot 6: Mittlere Schadenhäufigkeit nach Region
region_rates <- df %>%
  group_by(Region) %>%
  summarise(
    claim_rate = sum(ClaimNb) / sum(Exposure),
    n = n(),
    .groups = "drop"
  ) %>%
  arrange(desc(claim_rate))

p6 <- ggplot(region_rates, aes(x = reorder(Region, claim_rate), y = claim_rate)) +
  geom_col(fill = "#2C6FAC", alpha = 0.85) +
  coord_flip() +
  labs(title = "Mittlere Schadenhäufigkeit nach Region",
       x = "Region", y = "Schäden / Exposure-Jahr") +
  theme_minimal(base_size = 10)

# Plots speichern
ggsave("plots/eda_claimnb_distribution.png", p1, width = 7, height = 5, dpi = 150)
ggsave("plots/eda_claimnb_bonusmalus.png", p2, width = 7, height = 5, dpi = 150)
ggsave("plots/eda_claimnb_drivage.png", p3, width = 7, height = 5, dpi = 150)
ggsave("plots/eda_exposure.png", p4, width = 7, height = 5, dpi = 150)
ggsave("plots/eda_claimtotal.png", p5, width = 7, height = 5, dpi = 150)
ggsave("plots/eda_region_rates.png", p6, width = 9, height = 6, dpi = 150)

cat("EDA-Plots gespeichert.\n")

# ---- 5. Poisson GLM – Vollständiges Modell ---------------------------------
# Wüthrich & Merz Kap. 5.2: Schadenhäufigkeitsmodellierung
# Y_i ~ Poisson(lambda_i * t_i), wobei t_i = Exposure
# log(E[Y_i]) = log(t_i) + x_i' beta  (Offset = log(Exposure))
cat("\n=== 5. Poisson GLM – Schadenhäufigkeit ===\n")
cat("Modell: ClaimNb ~ Poisson(mu), log(mu) = offset(log(Exposure)) + X*beta\n")

n <- nrow(df)

# Vollständiges Modell mit allen relevanten Prädiktoren
poisson_full <- glm(
  ClaimNb ~ offset(log(Exposure)) +
    VehPower + VehAge + DrivAge + BonusMalus +
    VehBrand + VehGas + Area + Density + Region,
  family = poisson(link = "log"),
  data = df
)

cat("\n--- Vollständiges Poisson-Modell ---\n")
cat(sprintf("Nulldeviance:     %.2f  (df = %d)\n",
            poisson_full$null.deviance, poisson_full$df.null))
cat(sprintf("Residualdeviance: %.2f  (df = %d)\n",
            deviance(poisson_full), df.residual(poisson_full)))
cat(sprintf("AIC:              %.2f\n", AIC(poisson_full)))

# ---- 6. AIC/BIC-basierte Variablenselektion --------------------------------
# Schrittweise Selektion mit BIC (k = log(n)) ist konservativer als AIC (k=2)
# und verhindert Überanpassung bei kleinen Stichproben.
# Referenz: Wüthrich & Merz Kap. 5.4 – Modellselektion
cat("\n=== 6. Variablenselektion (AIC und BIC) ===\n")

# AIC-basierte Selektion (k = 2)
cat("\n--- AIC-Selektion (k=2, bidirektional) ---\n")
poisson_aic <- step(poisson_full, direction = "both", k = 2, trace = 1)
cat(sprintf("\nFinales AIC-Modell AIC: %.2f\n", AIC(poisson_aic)))
cat("Verbleibende Variablen (AIC):\n")
print(attr(terms(poisson_aic), "term.labels"))

# BIC-basierte Selektion (k = log(n))
cat(sprintf("\n--- BIC-Selektion (k=log(%d)=%.2f, bidirektional) ---\n", n, log(n)))
poisson_bic <- step(poisson_full, direction = "both", k = log(n), trace = 1)
cat(sprintf("\nFinales BIC-Modell AIC: %.2f\n", AIC(poisson_bic)))
cat("Verbleibende Variablen (BIC):\n")
print(attr(terms(poisson_bic), "term.labels"))

# Vergleich: AIC vs. BIC-Modell
cat("\n--- Modellvergleich AIC vs. BIC ---\n")
cat(sprintf("%-20s  AIC=%8.2f  BIC=%8.2f  df=%d\n",
            "Volles Modell",
            AIC(poisson_full), BIC(poisson_full), df.residual(poisson_full)))
cat(sprintf("%-20s  AIC=%8.2f  BIC=%8.2f  df=%d\n",
            "AIC-Modell",
            AIC(poisson_aic), BIC(poisson_aic), df.residual(poisson_aic)))
cat(sprintf("%-20s  AIC=%8.2f  BIC=%8.2f  df=%d\n",
            "BIC-Modell",
            AIC(poisson_bic), BIC(poisson_bic), df.residual(poisson_bic)))

# Das bessere Modell für weitere Analyse verwenden
# Wahl: BIC-Modell (sparsamer, robuster für Prognose)
poisson_selected <- poisson_bic
cat("\nGewähltes Modell für weitere Analyse: BIC-Modell\n")

# ---- 7. Interaktionsterme --------------------------------------------------
# Wüthrich & Merz Kap. 5.3: Interaktionen zwischen Risikovariablen
# Theoretische Begründung:
#   - DrivAge * BonusMalus: Junge Fahrer mit hohem BM haben überproportional
#     höhere Schadenwahrscheinlichkeit (nicht-additiver Effekt)
#   - Region * VehPower: Regionale Unterschiede im Einfluss der Motorleistung
cat("\n=== 7. Interaktionsterme ===\n")

# Basis-Formel aus BIC-Selektion extrahieren
base_formula <- formula(poisson_selected)
base_terms <- attr(terms(poisson_selected), "term.labels")

# Test 1: DrivAge * BonusMalus
cat("\n--- Test: DrivAge * BonusMalus ---\n")
formula_ia1 <- update(base_formula, . ~ . + DrivAge:BonusMalus)
poisson_ia1 <- glm(formula_ia1, family = poisson(link = "log"), data = df)
anova_ia1 <- anova(poisson_selected, poisson_ia1, test = "Chisq")
print(anova_ia1)
p_ia1 <- anova_ia1[2, "Pr(>Chi)"]
cat(sprintf("p-Wert DrivAge:BonusMalus = %.4f %s\n",
            p_ia1, ifelse(p_ia1 < 0.05, "→ SIGNIFIKANT", "→ nicht signifikant")))

# Test 2: Region * VehPower (falls Region im Modell)
if ("Region" %in% base_terms) {
  cat("\n--- Test: Region * VehPower ---\n")
  formula_ia2 <- update(base_formula, . ~ . + Region:VehPower)
  poisson_ia2 <- glm(formula_ia2, family = poisson(link = "log"), data = df)
  anova_ia2 <- anova(poisson_selected, poisson_ia2, test = "Chisq")
  print(anova_ia2)
  p_ia2 <- anova_ia2[2, "Pr(>Chi)"]
  cat(sprintf("p-Wert Region:VehPower = %.4f %s\n",
              p_ia2, ifelse(p_ia2 < 0.05, "→ SIGNIFIKANT", "→ nicht signifikant")))
}

# Test 3: VehAge * DrivAge
cat("\n--- Test: VehAge * DrivAge ---\n")
formula_ia3 <- update(base_formula, . ~ . + VehAge:DrivAge)
poisson_ia3 <- glm(formula_ia3, family = poisson(link = "log"), data = df)
anova_ia3 <- anova(poisson_selected, poisson_ia3, test = "Chisq")
print(anova_ia3)
p_ia3 <- anova_ia3[2, "Pr(>Chi)"]
cat(sprintf("p-Wert VehAge:DrivAge = %.4f %s\n",
            p_ia3, ifelse(p_ia3 < 0.05, "→ SIGNIFIKANT", "→ nicht signifikant")))

# Nur signifikante Interaktionen aufnehmen (p < 0.05)
# Modell aktualisieren
poisson_final_formula <- base_formula
interactions_added <- character(0)

if (p_ia1 < 0.05) {
  poisson_final_formula <- update(poisson_final_formula, . ~ . + DrivAge:BonusMalus)
  interactions_added <- c(interactions_added, "DrivAge:BonusMalus")
  cat("\n→ DrivAge:BonusMalus aufgenommen\n")
}
if (exists("p_ia2") && p_ia2 < 0.05) {
  poisson_final_formula <- update(poisson_final_formula, . ~ . + Region:VehPower)
  interactions_added <- c(interactions_added, "Region:VehPower")
  cat("→ Region:VehPower aufgenommen\n")
}
if (p_ia3 < 0.05) {
  poisson_final_formula <- update(poisson_final_formula, . ~ . + VehAge:DrivAge)
  interactions_added <- c(interactions_added, "VehAge:DrivAge")
  cat("→ VehAge:DrivAge aufgenommen\n")
}

if (length(interactions_added) == 0) {
  cat("\n→ Keine Interaktionen signifikant. Haupteffekt-Modell wird beibehalten.\n")
  poisson_final <- poisson_selected
} else {
  poisson_final <- glm(poisson_final_formula, family = poisson(link = "log"), data = df)
  cat(sprintf("\nFinales Poisson-Modell mit Interaktionen: AIC=%.2f\n",
              AIC(poisson_final)))
}

cat(sprintf("Verbesserung AIC: %.2f → %.2f (Δ=%.2f)\n",
            AIC(poisson_selected), AIC(poisson_final),
            AIC(poisson_final) - AIC(poisson_selected)))

# ---- 8. Overdispersion-Test ------------------------------------------------
cat("\n=== 8. Overdispersion-Test ===\n")

# Pearson-Chi² / df als Dispersionsschätzer
pearson_resid <- residuals(poisson_final, type = "pearson")
dispersion <- sum(pearson_resid^2) / df.residual(poisson_final)
cat(sprintf("Pearson χ² / df = %.4f\n", dispersion))

if (dispersion > 1.5) {
  cat("→ ACHTUNG: Overdispersion vorhanden (Dispersion > 1.5)!\n")
  cat("  Empfehlung: Quasi-Poisson oder Negativ-Binomial erwägen\n")
  # AER::dispersiontest
  disp_test <- dispersiontest(poisson_final)
  print(disp_test)
} else if (dispersion > 1.0) {
  cat("→ Leichte Overdispersion (1.0 < Dispersion ≤ 1.5). Poisson akzeptabel.\n")
} else {
  cat("→ Kein Overdispersionsproblem. Poisson-Modell angemessen.\n")
}

# ---- 9. Modelldiagnose – Poisson -------------------------------------------
cat("\n=== 9. Modelldiagnose (Poisson) ===\n")

# Deviance-Residuen
dev_resid <- residuals(poisson_final, type = "deviance")
fitted_vals <- fitted(poisson_final)
hat_vals <- hatvalues(poisson_final)
cook_vals <- cooks.distance(poisson_final)

cat(sprintf("Deviance-Residuen: Min=%.3f, Median=%.3f, Max=%.3f\n",
            min(dev_resid), median(dev_resid), max(dev_resid)))

# Plot 1: Deviance-Residuen vs. Fitted
diag_df <- data.frame(
  fitted = fitted_vals,
  dev_resid = dev_resid,
  pearson_resid = pearson_resid,
  leverage = hat_vals,
  cooks_d = cook_vals
)

p_diag1 <- ggplot(diag_df, aes(x = log(fitted + 1e-8), y = dev_resid)) +
  geom_point(alpha = 0.4, color = "#2C6FAC", size = 1.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  geom_smooth(method = "loess", se = FALSE, color = "#E05A2B", linewidth = 0.8) +
  labs(title = "Deviance-Residuen vs. Fitted (log)",
       subtitle = "Poisson GLM – Schadenhäufigkeit",
       x = "log(Fitted Values)", y = "Deviance-Residuen") +
  theme_minimal(base_size = 12)

# Plot 2: QQ-Plot der Deviance-Residuen
p_diag2 <- ggplot(diag_df, aes(sample = dev_resid)) +
  stat_qq(alpha = 0.5, color = "#2C6FAC") +
  stat_qq_line(color = "red", linetype = "dashed") +
  labs(title = "QQ-Plot der Deviance-Residuen",
       subtitle = "Poisson GLM",
       x = "Theoretische Quantile", y = "Empirische Quantile") +
  theme_minimal(base_size = 12)

# Plot 3: Cook's Distance
diag_df$obs_idx <- seq_len(nrow(diag_df))
p_diag3 <- ggplot(diag_df, aes(x = obs_idx, y = cooks_d)) +
  geom_col(fill = "#2C6FAC", alpha = 0.7) +
  geom_hline(yintercept = 4 / nrow(df), color = "red", linetype = "dashed") +
  annotate("text", x = nrow(df) * 0.8, y = 4 / nrow(df) * 1.1,
           label = sprintf("Schwellenwert: 4/n=%.4f", 4 / nrow(df)),
           color = "red", size = 3) +
  labs(title = "Cook's Distance – Einflussreiche Beobachtungen",
       subtitle = "Poisson GLM",
       x = "Beobachtungsindex", y = "Cook's Distance") +
  theme_minimal(base_size = 12)

# Einflussreiche Beobachtungen
influential <- which(cook_vals > 4 / nrow(df))
cat(sprintf("Einflussreiche Beobachtungen (Cook > 4/n): %d\n",
            length(influential)))
if (length(influential) > 0 && length(influential) <= 20) {
  cat("Indices:", paste(influential, collapse = ", "), "\n")
}

# Plot 4: Residuen vs. Leverage
p_diag4 <- ggplot(diag_df, aes(x = leverage, y = dev_resid)) +
  geom_point(alpha = 0.4, color = "#2C6FAC", size = 1.5) +
  geom_hline(yintercept = c(-2, 0, 2), linetype = c("dashed", "solid", "dashed"),
             color = c("orange", "red", "orange")) +
  geom_vline(xintercept = 2 * length(coef(poisson_final)) / nrow(df),
             linetype = "dashed", color = "gray50") +
  labs(title = "Residuen vs. Leverage",
       subtitle = "Poisson GLM",
       x = "Leverage (Hat-Werte)", y = "Deviance-Residuen") +
  theme_minimal(base_size = 12)

# Diagnose-Plots speichern
ggsave("plots/poisson_diag_resid_vs_fitted.png", p_diag1, width = 7, height = 5, dpi = 150)
ggsave("plots/poisson_diag_qqplot.png", p_diag2, width = 7, height = 5, dpi = 150)
ggsave("plots/poisson_diag_cooks.png", p_diag3, width = 8, height = 5, dpi = 150)
ggsave("plots/poisson_diag_leverage.png", p_diag4, width = 7, height = 5, dpi = 150)

cat("Diagnose-Plots für Poisson gespeichert.\n")

# ---- 10. Poisson GLM – Koeffizienten-Tabelle --------------------------------
cat("\n=== 10. Poisson GLM – Koeffizienten mit Konfidenzintervallen ===\n")

# Konfidenzintervalle (Wald-Methode, schneller; Profil-Likelihood via confint())
coef_table <- broom::tidy(poisson_final, conf.int = TRUE, conf.level = 0.95,
                           exponentiate = FALSE)
# Signifikanz-Stern
coef_table$signif <- ifelse(coef_table$p.value < 0.001, "***",
                     ifelse(coef_table$p.value < 0.01,  "**",
                     ifelse(coef_table$p.value < 0.05,  "*",
                     ifelse(coef_table$p.value < 0.10,  ".",  ""))))

# Formatierte Ausgabe
cat(sprintf("\n%-40s  %8s  %8s  %7s  %10s  %8s  %8s  %s\n",
            "Variable", "Estimate", "Std.Err", "z-Wert", "p-Wert",
            "CI_lower", "CI_upper", "Sign."))
cat(strrep("-", 110), "\n")

for (i in seq_len(nrow(coef_table))) {
  row <- coef_table[i, ]
  cat(sprintf("%-40s  %8.4f  %8.4f  %7.3f  %10.4f  %8.4f  %8.4f  %s\n",
              row$term, row$estimate, row$std.error, row$statistic,
              row$p.value, row$conf.low, row$conf.high, row$signif))
}

# Signifikante Koeffizienten zusammenfassen
sig_coefs <- coef_table[coef_table$signif != "" & coef_table$term != "(Intercept)", ]
cat(sprintf("\nSignifikante Koeffizienten (p < 0.05): %d von %d\n",
            nrow(sig_coefs), nrow(coef_table) - 1))

# ---- 11. Gamma GLM – Schadenhöhe --------------------------------------------
# Wüthrich & Merz Kap. 5.5: Schadenhöhenmodellierung
# Nur Policen mit mindestens einem Schaden (ClaimTotal > 0)
# Y_i ~ Gamma(mu_i, phi), log(mu_i) = x_i' gamma
cat("\n=== 11. Gamma GLM – Schadenhöhe ===\n")

df_sev <- df[df$ClaimTotal > 0, ]
n_sev <- nrow(df_sev)
cat(sprintf("Beobachtungen mit Schäden: %d\n", n_sev))

# Mittlere Schadenhöhe pro Claim (falls ClaimNb > 1)
df_sev$AvgClaimSev <- df_sev$ClaimTotal / df_sev$ClaimNb
cat(sprintf("Mittlere Schadenhöhe: %.2f EUR\n", mean(df_sev$AvgClaimSev)))
cat(sprintf("Std.-abw. Schadenhöhe: %.2f EUR\n", sd(df_sev$AvgClaimSev)))

# Vollständiges Gamma-Modell
# Kein Offset notwendig (Schadenhöhe ist nicht expositionsabhängig)
gamma_full <- glm(
  AvgClaimSev ~ VehPower + VehAge + DrivAge + BonusMalus +
    VehBrand + VehGas + Area + Density + Region,
  family = Gamma(link = "log"),
  data = df_sev
)

cat(sprintf("\nGamma-Vollmodell AIC: %.2f\n", AIC(gamma_full)))
cat(sprintf("Residualdeviance:     %.4f (df=%d)\n",
            deviance(gamma_full), df.residual(gamma_full)))

# AIC-Selektion für Gamma-Modell
cat("\n--- BIC-Selektion Gamma (k=log(n_sev)) ---\n")
gamma_bic <- step(gamma_full, direction = "both",
                  k = log(n_sev), trace = 1)
cat(sprintf("\nFinales Gamma-Modell AIC: %.2f\n", AIC(gamma_bic)))

gamma_final <- gamma_bic

# Gamma-Dispersion (Formparameter)
gamma_disp <- summary(gamma_final)$dispersion
cat(sprintf("Gamma Dispersionsparameter (1/shape): %.4f\n", gamma_disp))
cat(sprintf("Shape-Parameter (k): %.4f\n", 1 / gamma_disp))

# ---- 12. Gamma GLM – Diagnose -----------------------------------------------
cat("\n=== 12. Gamma GLM – Modelldiagnose ===\n")

dev_resid_g <- residuals(gamma_final, type = "deviance")
pearson_resid_g <- residuals(gamma_final, type = "pearson")
fitted_g <- fitted(gamma_final)
cook_g <- cooks.distance(gamma_final)
hat_g <- hatvalues(gamma_final)

diag_g <- data.frame(
  fitted = fitted_g,
  dev_resid = dev_resid_g,
  leverage = hat_g,
  cooks_d = cook_g,
  obs_idx = seq_len(n_sev)
)

# Pearson-Dispersion für Gamma
disp_gamma <- sum(pearson_resid_g^2) / df.residual(gamma_final)
cat(sprintf("Pearson χ² / df (Gamma) = %.4f\n", disp_gamma))

pg1 <- ggplot(diag_g, aes(x = log(fitted), y = dev_resid)) +
  geom_point(alpha = 0.5, color = "#E05A2B", size = 2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  geom_smooth(method = "loess", se = FALSE, color = "#2C6FAC") +
  labs(title = "Deviance-Residuen vs. Fitted (Gamma)",
       x = "log(Fitted Values)", y = "Deviance-Residuen") +
  theme_minimal(base_size = 12)

pg2 <- ggplot(diag_g, aes(sample = dev_resid)) +
  stat_qq(alpha = 0.6, color = "#E05A2B") +
  stat_qq_line(color = "red", linetype = "dashed") +
  labs(title = "QQ-Plot Deviance-Residuen (Gamma)",
       x = "Theoretische Quantile", y = "Empirische Quantile") +
  theme_minimal(base_size = 12)

pg3 <- ggplot(diag_g, aes(x = obs_idx, y = cooks_d)) +
  geom_col(fill = "#E05A2B", alpha = 0.7) +
  geom_hline(yintercept = 4 / n_sev, color = "red", linetype = "dashed") +
  labs(title = "Cook's Distance (Gamma)",
       x = "Beobachtungsindex", y = "Cook's Distance") +
  theme_minimal(base_size = 12)

pg4 <- ggplot(diag_g, aes(x = leverage, y = dev_resid)) +
  geom_point(alpha = 0.5, color = "#E05A2B", size = 2) +
  geom_hline(yintercept = c(-2, 0, 2),
             linetype = c("dashed", "solid", "dashed"),
             color = c("orange", "red", "orange")) +
  labs(title = "Residuen vs. Leverage (Gamma)",
       x = "Leverage", y = "Deviance-Residuen") +
  theme_minimal(base_size = 12)

ggsave("plots/gamma_diag_resid_vs_fitted.png", pg1, width = 7, height = 5, dpi = 150)
ggsave("plots/gamma_diag_qqplot.png", pg2, width = 7, height = 5, dpi = 150)
ggsave("plots/gamma_diag_cooks.png", pg3, width = 7, height = 5, dpi = 150)
ggsave("plots/gamma_diag_leverage.png", pg4, width = 7, height = 5, dpi = 150)
cat("Gamma-Diagnose-Plots gespeichert.\n")

# ---- 13. Gamma GLM – Koeffizienten-Tabelle ----------------------------------
cat("\n=== 13. Gamma GLM – Koeffizienten mit Konfidenzintervallen ===\n")

coef_table_g <- broom::tidy(gamma_final, conf.int = TRUE, conf.level = 0.95)
coef_table_g$signif <- ifelse(coef_table_g$p.value < 0.001, "***",
                       ifelse(coef_table_g$p.value < 0.01,  "**",
                       ifelse(coef_table_g$p.value < 0.05,  "*",
                       ifelse(coef_table_g$p.value < 0.10,  ".",  ""))))

cat(sprintf("\n%-40s  %8s  %8s  %7s  %10s  %8s  %8s  %s\n",
            "Variable", "Estimate", "Std.Err", "t-Wert", "p-Wert",
            "CI_lower", "CI_upper", "Sign."))
cat(strrep("-", 110), "\n")

for (i in seq_len(nrow(coef_table_g))) {
  row <- coef_table_g[i, ]
  cat(sprintf("%-40s  %8.4f  %8.4f  %7.3f  %10.4f  %8.4f  %8.4f  %s\n",
              row$term, row$estimate, row$std.error, row$statistic,
              row$p.value, row$conf.low, row$conf.high, row$signif))
}

# ---- 14. Modelle speichern -------------------------------------------------
cat("\n=== 14. Modelle speichern ===\n")

saveRDS(poisson_final, "models/poisson_glm.rds")
saveRDS(gamma_final,   "models/gamma_glm.rds")

cat("poisson_glm.rds gespeichert.\n")
cat("gamma_glm.rds   gespeichert.\n")

# Verifikation: Laden und kurzer Check
poisson_loaded <- readRDS("models/poisson_glm.rds")
gamma_loaded   <- readRDS("models/gamma_glm.rds")
cat(sprintf("Verifikation Poisson: AIC=%.2f ✓\n", AIC(poisson_loaded)))
cat(sprintf("Verifikation Gamma:   AIC=%.2f ✓\n", AIC(gamma_loaded)))

# ---- 15. Modellvergleich (Vorbereitung ML – Phase 3) -----------------------
cat("\n=== 15. Vergleich GLM vs. ML (Ausblick Phase 3) ===\n")

# In-sample Vorhersagen Poisson
df$pred_freq_glm <- predict(poisson_final, type = "response") / df$Exposure
df$pred_nb_glm   <- predict(poisson_final, type = "response")

# RMSE und MAE als einfache Vergleichsmetriken
rmse_poisson <- sqrt(mean((df$ClaimNb - df$pred_nb_glm)^2))
mae_poisson  <- mean(abs(df$ClaimNb - df$pred_nb_glm))

cat(sprintf("Poisson GLM In-Sample RMSE: %.6f\n", rmse_poisson))
cat(sprintf("Poisson GLM In-Sample MAE:  %.6f\n", mae_poisson))
cat(sprintf("Mittlere Schadenhäufigkeit (beob.):  %.6f\n", mean(df$ClaimNb)))
cat(sprintf("Mittlere Schadenhäufigkeit (Modell): %.6f\n", mean(df$pred_nb_glm)))

# Gini-Koeffizient (Lorenz-Kurve) – wichtige Metrik in Versicherungsmathe
# Hier vereinfacht: Korrelation als Proxy
lorenz_corr <- cor(df$pred_nb_glm, df$ClaimNb, method = "spearman")
cat(sprintf("Spearman-Korrelation (Predicted vs. Actual): %.4f\n", lorenz_corr))

cat("\n--- Erwartete ML-Vorteile (Phase 3) ---\n")
cat("  - Gradient Boosting / Random Forest: Automatische Interaktionen\n")
cat("  - Nicht-lineare Effekte ohne explizite Transformationen\n")
cat("  - Potentiell niedrigerer RMSE, aber schlechtere Interpretierbarkeit\n")
cat("  - GLM bleibt Baseline und Interpretationsanker\n")
cat("  - Referenz: Wüthrich & Merz Kap. 7-8 (Neural Networks, GBM)\n")

cat("\n=== ANALYSE ABGESCHLOSSEN ===\n")
cat(sprintf("Poisson GLM: %d Koeffizienten, AIC=%.2f\n",
            length(coef(poisson_final)), AIC(poisson_final)))
cat(sprintf("Gamma GLM:   %d Koeffizienten, AIC=%.2f\n",
            length(coef(gamma_final)), AIC(gamma_final)))
