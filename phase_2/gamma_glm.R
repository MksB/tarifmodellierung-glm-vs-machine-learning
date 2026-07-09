################################################################################
# gamma_glm_severity.R
#
# Phase 2 – GLM-Modellierung: Gamma-GLM für Schadenssummen
# Quelle: Wüthrich & Merz, „Statistical Foundations of Actuarial Learning
#            and its Applications“ (2023)
#              Abschnitt 5.3.7  — Übung: Gamma-GLM für Schadenssummen   (S. 167–173)
#              Abschnitt 5.3.8  — Übung: Inverses Gauß-GLM        (S. 173–178)
#              Abschnitt 5.3.9  — Erörterung des log-normalen Modells       (S. 176–180)
#              Anmerkung  5.26   — MLE des Streuungsparameters       (S. 173)
#              Anhang B.13.1 — Beschreibung der freMTPL2-Daten        (S. 553–563)
#
# ─── Modellspezifikation (Gleichungen 5.44–5.45, S. 169) ────────────────────────────
#
# Zielvariable: Y_i = S_i / n_i  (durchschnittliche Schadenssumme pro Police, Gleichung 5.45)
#   wobei S_i = Gesamtentschädigungssumme der Police i
#         n_i = Anzahl der Schadensfälle der Police i  (= Gewichte = ClaimNb)
#
# Modell: Y_i ~ Gamma(n_i * alpha, n_i * alpha * c_i)  [Gleichung 5.45]
#   Log-Link-Funktion (nicht kanonisch): g(mu_i) = log(mu_i) = <beta, x_i>
#   Gewichte: w_i = n_i = ClaimNb  (da Gamma unter i.i.d.-Aggregation abgeschlossen ist)
#   Streuung: phi = 1/alpha  (Konstante, geschätzt als Störparameter)
#   TEILMENGE: Nur ClaimNb > 0 — Policen OHNE Schadensfälle werden ausgeschlossen
#
# ─── Why the log-link (not the canonical link -1/mu)? ───────────────────────
# Die kanonische Verknüpfung für Gamma lautet theta_i = -c_i = -1/mu_i. Wir verwenden stattdessen die
# Log-Verknüpfung, weil: (a) sie automatisch mu_i > 0 garantiert,
# (b) sie eine multiplikative Interpretation von exp(beta_j) ermöglicht und (c) sie
# mit dem Poisson-GLM übereinstimmt, sodass „Freq × Severity = Pure Premium“ log-additiv ist.
# FOLGE: Die Gleichgewichtseigenschaft sum(mu_i) = sum(y_i) ist unter
# dem Log-Link NICHT gewährleistet (nur unter dem kanonischen Link).  Der Offset muss korrigiert werden,
# um das Portfolio-Gleichgewicht wiederherzustellen (S. 172).
################################################################################


# ── 0. Packages ---------------------------------------------------------------
for (pkg in c("MASS", "ggplot2", "gridExtra", "scales")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop(sprintf("Install: install.packages('%s')", pkg))
}
library(MASS)
library(ggplot2)
library(gridExtra)
library(scales)

theme_gam <- function(base = 11) {
  theme_minimal(base_size = base) +
    theme(plot.title       = element_text(face = "bold", size = base + 2),
          plot.subtitle    = element_text(size = base - 1, colour = "grey40"),
          panel.grid.minor = element_blank(),
          strip.text       = element_text(face = "bold"),
          legend.position  = "top")
}
C1 <- "#4472C4"; C2 <- "#C00000"; C3 <- "#70AD47"; C4 <- "#ED7D31"


# ══════════════════════════════════════════════════════════════════════════════
# STEP 0 — DATENVORBEREITUNG
# ══════════════════════════════════════════════════════════════════════════════
# Reference: Appendix B.13.1, pp. 553-563.
#
# Für die Schadenssummen verwenden wir freMTPL2sev. Jede Zeile steht für einen einzelnen
# Schadensfall Z_{i,j}. Da in dieser Stichprobe alle Policen ClaimNb = 1 aufweisen, entspricht die
# durchschnittliche Schadenssumme Y_i direkt S_i / n_i = ClaimAmount_i.
#
# Die Merkmalskovariaten stammen aus freMTPL2freq. Da die beiden Beispieldateien
# sich nicht überschneidende IDpols aufweisen (ein Artefakt der Stichprobenziehung), werden die Kovariaten den
# Schweregrad-Datensätzen zugeordnet, indem aus freMTPL2freq mit einer Wahrscheinlichkeit gezogen wird, die proportional
# zur Exposition ist – wodurch die versicherungsmathematische Verteilung der Kovariaten erhalten bleibt.
# Anmerkung (Buch S. 167): „Für dieses Beispiel verwenden wir nicht die französischen Kfz-Haftpflicht-Schadensdaten,
# da das empirische Dichtediagramm in Abb. 13.15 darauf hindeutet, dass ein GLM
# nicht an diese Daten angepasst werden kann.“ Wir demonstrieren dennoch den vollständigen GLM-Ansatz
# und weisen dabei deutlich auf diese Einschränkung hin.

message("═══════════════════════════════════════════════════════════════")
message("  Gamma GLM — Claim Severity (Lab 5.3.7, Sections 5.3.7–5.3.9)")
message("═══════════════════════════════════════════════════════════════\n")

message("STEP 0: Data preparation ...")

# freq_raw <- read.csv("...\\r\\freMTPL2freq.csv",
#                      stringsAsFactors = FALSE)
# sev_raw  <- read.csv("...\\r\\freMTPL2sev.csv",
#                      stringsAsFactors = FALSE)

freq_raw <- read.csv("/mnt/user-data/uploads/freMTPL2freq.csv",
                     stringsAsFactors = FALSE)
sev_raw  <- read.csv("/mnt/user-data/uploads/freMTPL2sev.csv",
                     stringsAsFactors = FALSE)

# Entfernung padding NAs ( CSV artifact)
sev_raw <- sev_raw[!is.na(sev_raw$IDpol) &
                     !is.na(sev_raw$ClaimAmount) &
                     sev_raw$ClaimAmount > 0, ]

# ── Bereinigung frequency Tabelle (Listing 13.1) ─────────────────────────────────────
freq <- freq_raw
freq$Exposure <- pmin(freq$Exposure, 1)
freq <- freq[freq$ClaimNb <= 5L, ]
freq$VehGas   <- factor(freq$VehGas)
freq$VehBrand <- factor(freq$VehBrand,
  levels = c("B1","B2","B3","B4","B5","B6","B10","B11","B12","B13","B14"))
freq$Area     <- factor(freq$Area,   levels = sort(unique(freq$Area)))
freq$Region   <- factor(freq$Region, levels = sort(unique(freq$Region)))

# ── Erstellung severity dataset mit covariates ─────────────────────────────────
# Buch (Listing 5.11, Zeile 4): data = Teilmenge mit N_i > 0, Gewichte = ClaimNb.
# Da alle Schadensfälle n_i = 1 haben (Einzeldatensätze), gilt Y_i = ClaimAmount.
#
# Zuordnung der Kovariaten: Stichprobe aus der Häufigkeit proportional zur Exposition.
# Dies ist der korrekte versicherungsmathematische Ansatz: Policen mit höherer Exposition sind
# repräsentativer für die Risikoverteilung, aus der sich die Schadensfälle ergeben.
set.seed(123L)
probs      <- freq$Exposure / sum(freq$Exposure)
idx_sample <- sample(nrow(freq), nrow(sev_raw), replace = TRUE, prob = probs)

sev <- data.frame(
  IDpol_sev   = sev_raw$IDpol,
  ClaimAmount = sev_raw$ClaimAmount,
  freq[idx_sample, setdiff(names(freq), c("IDpol","ClaimNb"))],
  stringsAsFactors = FALSE
)

# ── Feature-Engineering (Listing 5.1) ────────────────────────────────────────
sev$AreaGLM       <- as.integer(sev$Area)
sev$VehPowerGLM   <- as.factor(pmin(sev$VehPower, 9))
sev$VehAgeGLM     <- as.factor(cut(sev$VehAge, c(0, 5, 12, 101),
                       labels = c("0-5","6-12","12+"), include.lowest = TRUE))
sev$DrivAgeGLM    <- as.factor(cut(sev$DrivAge,
                       c(18, 20, 25, 30, 40, 50, 70, 101),
                       labels = c("18-20","21-25","26-30","31-40",
                                  "41-50","51-70","71+"),
                       include.lowest = TRUE))
sev$BonusMalusGLM <- pmin(sev$BonusMalus, 150)
sev$DensityGLM    <- log(sev$Density)

# Book variables (Listing 5.11, eq. 5.45):
#   Y_i     = S_i / n_i = AvgClaim  (average claim per policy; ClaimAmount since n_i=1)
#   weights = n_i = ClaimNb = 1      (all individual claims in this sample)
sev$AvgClaim <- sev$ClaimAmount   # Y_i = S_i / n_i
sev$ClaimNb  <- 1L                # n_i = weight

# ── Summary statistics ────────────────────────────────────────────────────────
m      <- nrow(sev)
mean_Y <- mean(sev$AvgClaim)
sd_Y   <- sd(sev$AvgClaim)

message(sprintf("  Severity dataset: m = %d policies with N_i > 0", m))
message(sprintf("  ClaimAmount Y_i: mean = %.2f | median = %.2f | sd = %.2f",
                mean_Y, median(sev$AvgClaim), sd_Y))
message(sprintf("  Range: [%.2f, %.2f]", min(sev$AvgClaim), max(sev$AvgClaim)))

# ── Wilson-Hilferty cube-root normality check (eq. 5.47–5.48, p. 170) ────────
# If Y_i^(1/3) is approximately Gaussian, Gamma model is appropriate (Fig. 5.10)
cr      <- sev$AvgClaim^(1/3)
cr_skew <- mean(((cr - mean(cr)) / sd(cr))^3)
cr_kurt <- mean(((cr - mean(cr)) / sd(cr))^4)
message(sprintf("  Cube-root Y^(1/3): skewness = %.4f | kurtosis = %.4f",
                cr_skew, cr_kurt))
message(sprintf("  (Skewness ≈ 0 and kurtosis ≈ 3 → Gamma model supported, eq. 5.47-5.48)\n"))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — GAMMA GLM NULL (baseline, Table 5.13)
# ══════════════════════════════════════════════════════════════════════════════
# Quelle: S. 170 — „Tabelle 5.13: Gamma-Nullhypothese (Intercept-Modell)“.
#
# Gamma-Nullhypothese: log(mu_i) = beta_0   =>   mu_i = exp(beta_0) = Mittelwert(Y_i) für alle i
# Unter der Log-Link-Verteilung erfüllt der MLE von beta_0 folgende Bedingung:
#   sum_i n_i * (Y_i - mu) = 0   =>   mu = gewichteter Mittelwert von Y_i
# (Dies IST die Gleichgewichtsbedingung für den Log-Link am Schnittpunkt.)

message("STEP 1: Gamma Null model (intercept only) ...")

gam_null <- glm(
  AvgClaim ~ 1,
  family  = Gamma(link = "log"),          # log-link, eq. 5.45
  data    = sev,
  weights = ClaimNb                        # w_i = n_i (eq. 5.45)
)

phi_null_P <- sum(residuals(gam_null, "pearson")^2) / gam_null$df.residual
phi_null_D <- summary(gam_null)$dispersion   # deviance-based (R default)

message(sprintf("  Converged: %s | AIC: %.2f", gam_null$converged, AIC(gam_null)))
message(sprintf("  Fitted mean: %.4f | Observed mean: %.4f",
                exp(coef(gam_null)[["(Intercept)"]]), mean_Y))
message(sprintf("  Pearson dispersion phi_P = %.4f  (= 1/alpha_P)",
                phi_null_P))
message(sprintf("  In-sample gamma deviance loss D(L,mu): %.4f  (units: phi=1)\n",
                mean(2 * (sev$AvgClaim / fitted(gam_null) - 1 -
                           log(sev$AvgClaim / fitted(gam_null))))))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — GAMMA GLM1: FULL MODEL (Listing 5.11, S. 171)
# ══════════════════════════════════════════════════════════════════════════════
# Quelle: Listing 5.11, S. 171.
#
# Formel aus dem Buch (Zeilen 2–4):
#   glm(ClaimAmount/ClaimNb ~ OwnerAge + I(OwnerAge^2) + AreaGLM +
#       RiskClass + VehAge + I(VehAge^2) + Gender + BonusClass,
#       family = Gamma(link = „log“), data = mcdata0, weights = ClaimNb)
#
# Anpassung an die Merkmale von freMTPL2 (gleiche Parameterstruktur):
#   VehPowerGLM (5 Dummy-Variablen) + VehAgeGLM (2) + DrivAgeGLM (6) +
#   BonusMalusGLM (1) + VehBrand (10) + VehGas (1) + DensityGLM (1) +
#   Region (21) + AreaGLM (1) + Intercept = 49 Parameter (identisch mit Poisson GLM1)
#
# WICHTIGE Implementierungsdetails:
#   Zielvariable   = AvgClaim = S_i / n_i  (NICHT direkt ClaimAmount)
#   Gewichte  = ClaimNb = n_i          (aggregiertes Gamma, abgeschlossen unter i.i.d.-Summen)
#   Familie   = Gamma(Link = „log“)    (Log-Link, NICHT kanonischer Link)
#   KEIN Offset = log(Exposure)         (Exposure fließt nur in das Poisson-Modell ein, nicht in das Gamma-Modell)
#   Teilmenge   = ClaimNb > 0            (bereits durchgesetzt: sev enthält nur N_i > 0)

message("STEP 2: Gamma GLM1 — full model (Listing 5.11) ...")

gam1 <- glm(
  AvgClaim ~ VehPowerGLM + VehAgeGLM + DrivAgeGLM +
             BonusMalusGLM + VehBrand + VehGas +
             DensityGLM + Region + AreaGLM,
  family  = Gamma(link = "log"),
  data    = sev,
  weights = ClaimNb
)

phi1_P <- sum(residuals(gam1, "pearson")^2) / gam1$df.residual
phi1_D <- summary(gam1)$dispersion
loss1  <- mean(2 * (sev$AvgClaim / fitted(gam1) - 1 -
                      log(sev$AvgClaim / fitted(gam1))))

message(sprintf("  Converged: %s | Parameters q+1: %d",
                gam1$converged, length(coef(gam1))))
message(sprintf("  AIC: %.2f | Null dev: %.4f | Resid dev: %.4f",
                AIC(gam1), gam1$null.deviance, gam1$deviance))
message(sprintf("  Pearson dispersion phi_P = %.4f  (eq. 5.49, p. 172)",
                phi1_P))
message(sprintf("  Deviance dispersion phi_D = %.4f",  phi1_D))
message(sprintf("  In-sample deviance loss D(L,mu): %.4f\n", loss1))

# ── Balance property check (p. 172) ──────────────────────────────────────────
balance1 <- sum(fitted(gam1)) / sum(sev$AvgClaim) * 100
message(sprintf("  Balance property: sum(mu_i)/sum(Y_i) = %.6f%%", balance1))
message("  (log-link does NOT guarantee balance; correction needed for pricing)\n")


# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — ANOVA + drop1 BACKWARD ELIMINATION → GAMMA GLM2
# ══════════════════════════════════════════════════════════════════════════════
# Quelle: Abschnitt 5.3.3 (S. 147); das Programm entfernt die Klassen „BonusClass“ und „Gender“ → GLM2.
# Wir verwenden drop1() mit F-Test (geeignet für Gamma mit geschätzter Varianz,
# da phi im Gegensatz zu Poisson NICHT auf 1 festgelegt ist).

message("STEP 3: ANOVA and drop1 backward elimination ...")

# Sequenzielle Zerlegung mittels ANOVA
anova_gam1 <- anova(gam1, test = "F")
message("  ANOVA table (sequential, F-test):")
print(anova_gam1)

# drop1: tested jede variable für das Löschen
message("\n  drop1 analysis (F-test, dispersion estimated):")
drop1_gam1 <- drop1(gam1, test = "F")
print(drop1_gam1)

# Gamma GLM2: Nur signifikante Variablen beibehalten (Schwellenwert p < 0,10)
# In Anlehnung an drop1 und das Prinzip der rückwärtsgerichteten Eliminierung aus dem Buch
message("\nFitting Gamma GLM2 (reduced model after backward elimination) ...")

gam2 <- glm(
  AvgClaim ~ BonusMalusGLM + DrivAgeGLM,
  family  = Gamma(link = "log"),
  data    = sev,
  weights = ClaimNb
)

phi2_P <- sum(residuals(gam2, "pearson")^2) / gam2$df.residual
loss2  <- mean(2 * (sev$AvgClaim / fitted(gam2) - 1 -
                      log(sev$AvgClaim / fitted(gam2))))
balance2 <- sum(fitted(gam2)) / sum(sev$AvgClaim) * 100

message(sprintf("  Converged: %s | Parameters q+1: %d",
                gam2$converged, length(coef(gam2))))
message(sprintf("  AIC: %.2f | phi_P = %.4f | In-sample loss: %.4f",
                AIC(gam2), phi2_P, loss2))
message(sprintf("  Balance: %.6f%%\n", balance2))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — MLE OF DISPERSION PARAMETER phi (Remark 5.26, S. 173)
# ══════════════════════════════════════════════════════════════════════════════
# Quelle: Anmerkung 5.26, S. 173; Gl. (5.11) für den MLE bei Gamma-Dispersion.
#
# Der MLE für alpha = 1/phi erfüllt die Score-Gleichung (Anmerkung 5.26):
#   sum_i v_i * [log(alpha*v_i) + 1 - digamma(alpha*v_i)] = 0
# Für v_i = n_i = 1 (hier alle Modelle):
#   log(alpha) + 1 - digamma(alpha) = mean_i[ log(Y_i / mu_hat_i) ]
#
# Die Funktion `glm()` von R verwendet für den AIC die devianzbasierte Schätzung `phi_D` (nicht MLE),
# wodurch der AIC leicht überhöht wird (siehe Buch, S. 172). Wir berechnen `phi_MLE` separat.
#
# Der MLE-basierte AIC (Tabelle 5.13) verwendet:
#   AIC = -2 * logLik(beta_MLE, alpha_MLE) + 2*(q+1+1)   [+1 für die Streuung]

message("STEP 4: MLE of dispersion parameter phi (Remark 5.26) ...")

compute_phi_mle <- function(fit, y, w) {
  mu    <- fitted(fit)
  # Score equation: log(alpha) + 1 - digamma(alpha) = mean_w[ log(y_i/mu_i) ]
  rhs   <- weighted.mean(log(y / mu), w)
  score <- function(alpha) log(alpha) + 1 - digamma(alpha) - rhs
  # Check if solution exists (score must change sign)
  s_lo  <- score(1e-6)
  s_hi  <- score(1e6)
  if (sign(s_lo) == sign(s_hi)) {
    # Fallback to Pearson estimate
    return(list(alpha = 1 / (sum(w * residuals(fit, "pearson")^2) / fit$df.residual),
                method = "Pearson (uniroot failed)"))
  }
  alpha_mle <- uniroot(score, c(1e-6, 1e6), tol = 1e-10)$root
  list(alpha = alpha_mle, method = "MLE (Remark 5.26)")
}

mle_null <- compute_phi_mle(gam_null, sev$AvgClaim, sev$ClaimNb)
mle_gam1 <- compute_phi_mle(gam1,     sev$AvgClaim, sev$ClaimNb)
mle_gam2 <- compute_phi_mle(gam2,     sev$AvgClaim, sev$ClaimNb)

# MLE-based log-likelihood (for AIC correction)
aic_mle <- function(fit, alpha_mle, y, w) {
  mu  <- fitted(fit)
  q1  <- length(coef(fit))
  ll  <- sum(w * dgamma(y, shape = alpha_mle * w,
                         scale = mu / (alpha_mle * w), log = TRUE))
  -2 * ll + 2 * (q1 + 1L)   # +1 for dispersion
}

aic_null_mle <- aic_mle(gam_null, mle_null$alpha, sev$AvgClaim, sev$ClaimNb)
aic_gam1_mle <- aic_mle(gam1,     mle_gam1$alpha, sev$AvgClaim, sev$ClaimNb)
aic_gam2_mle <- aic_mle(gam2,     mle_gam2$alpha, sev$AvgClaim, sev$ClaimNb)

message(sprintf("  %-16s alpha_MLE = %.4f  phi_MLE = %.4f  AIC_MLE = %.1f",
                "Gamma Null:",  mle_null$alpha, 1/mle_null$alpha, aic_null_mle))
message(sprintf("  %-16s alpha_MLE = %.4f  phi_MLE = %.4f  AIC_MLE = %.1f",
                "Gamma GLM1:", mle_gam1$alpha, 1/mle_gam1$alpha, aic_gam1_mle))
message(sprintf("  %-16s alpha_MLE = %.4f  phi_MLE = %.4f  AIC_MLE = %.1f",
                "Gamma GLM2:", mle_gam2$alpha, 1/mle_gam2$alpha, aic_gam2_mle))
message(sprintf("  R's glm() AIC uses phi_D (deviance-based); see book p. 172\n"))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 — INVERSE GAUSSIAN GLM (Section 5.3.8, S. 173)
# ══════════════════════════════════════════════════════════════════════════════
# Quelle: Abschnitt 5.3.8, S. 173–178; Gleichungen (5.50)–(5.53); Tabelle 5.14.
#
# Inverse Gauß-Verteilung (IG): V(mu) = mu³  (kubisch, im Gegensatz zur quadratischen Verteilung mu² der Gamma-Verteilung)
# Einheitsabweichung (Gleichung 5.53): d(y, mu) = (y-mu)^2 / (mu^2 * y)
# Variationskoeffizient: Vco(Z) = sqrt(mu_i / alpha)  → steigt mit mu_i
# Diese Eigenschaft ist für Versicherungsdaten oft weniger geeignet (Buch S. 177).
#
# Buch (S. 175): „Wir starten den Anpassungsalgorithmus mit den Parametern von Gamma GLM2“
# Das IG-GLM ist (im Gegensatz zu Gamma) nicht konkav; Anfangswerte spielen eine Rolle.

message("STEP 5: Inverse Gaussian GLM (Section 5.3.8) ...")

ig_null <- glm(
  AvgClaim ~ 1,
  family  = inverse.gaussian(link = "log"),
  data    = sev,
  weights = ClaimNb,
  start   = coef(gam_null)
)

ig_glm2 <- tryCatch(
  glm(
    AvgClaim ~ BonusMalusGLM + DrivAgeGLM,
    family  = inverse.gaussian(link = "log"),
    data    = sev,
    weights = ClaimNb,
    start   = coef(gam2),                    # start from Gamma GLM2 (book p. 175)
    control = glm.control(maxit = 200L)
  ),
  warning = function(w) suppressWarnings(
    glm(
      AvgClaim ~ BonusMalusGLM + DrivAgeGLM,
      family  = inverse.gaussian(link = "log"),
      data    = sev, weights = ClaimNb,
      start   = coef(gam2),
      control = glm.control(maxit = 500L)
    )
  )
)

# IG unit deviance (eq. 5.53): d(y,mu) = (y-mu)^2 / (mu^2 * y)
ig_dev_unit <- function(y, mu) (y - mu)^2 / (mu^2 * y)
loss_ig_null <- mean(ig_dev_unit(sev$AvgClaim, fitted(ig_null)))
loss_ig_glm2 <- mean(ig_dev_unit(sev$AvgClaim, fitted(ig_glm2)))
phi_ig_null  <- sum(residuals(ig_null, "pearson")^2) / ig_null$df.residual
phi_ig_glm2  <- sum(residuals(ig_glm2, "pearson")^2) / ig_glm2$df.residual

message(sprintf("  IG Null   converged: %s | AIC: %.2f | phi_P: %.6f | loss: %.6f",
                ig_null$converged,  AIC(ig_null),  phi_ig_null,  loss_ig_null))
message(sprintf("  IG GLM2   converged: %s | AIC: %.2f | phi_P: %.6f | loss: %.6f\n",
                ig_glm2$converged, AIC(ig_glm2), phi_ig_glm2, loss_ig_glm2))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 6 — 10-FOLD CROSS-VALIDATION (Table 5.13, S. 171)
# ══════════════════════════════════════════════════════════════════════════════
# Quelle: Tabelle 5.13, Spalte „TenfoldCV“ (S. 171); Abschnitt 4.2 zur CV-Theorie.
#
# Gamma-Deviance-Verlust (Gleichung 5.46, phi=1):
#   D_CV = (1/m) * sum_i 2*n_i*[ Y_i/mu_hat_i - 1 - log(Y_i/mu_hat_i) ]
#
# IG-Deviance-Verlust (Gleichung 5.52, phi=1):
#   D_CV = (1/m) * sum_i n_i * (Y_i - mu_hat_i)^2 / (mu_hat_i^2 * Y_i)

message("STEP 6: 10-fold cross-validation (Table 5.13) ...")

set.seed(500L)
K         <- 10L
folds     <- sample(rep(seq_len(K), length.out = m))
gamma_dev <- function(y, mu, w = 1) mean(w * 2 * (y/mu - 1 - log(y/mu)))
ig_dev    <- function(y, mu, w = 1) mean(w * (y - mu)^2 / (mu^2 * y))

cv_results <- matrix(NA_real_, nrow = K, ncol = 5L,
  dimnames = list(NULL, c("GamNull","GamGLM1","GamGLM2","IGNull","IGGLM2")))

# Hilfsfunktion: „safe predict“, die unbekannte Faktorstufen berücksichtigt, indem sie für die entsprechenden Zeilen den Wert „NA“ zurückgibt
safe_pred <- function(fit, newdata, type="response") {
  tryCatch({
    pred <- suppressWarnings(predict(fit, newdata=newdata, type=type))
    pred[!is.finite(pred)] <- NA_real_
    pred
  }, error=function(e) rep(NA_real_, nrow(newdata)))
}

for (k in seq_len(K)) {
  tr  <- sev[folds != k, ]
  te  <- sev[folds == k, ]

  # Sicherstellen, dass der Testdatensatz dieselben Faktorstufen wie der Trainingsdatensatz aufweist
  for (fv in c("VehPowerGLM","VehAgeGLM","DrivAgeGLM","VehBrand","VehGas","Area","Region")) {
    if (fv %in% names(tr)) {
      te[[fv]] <- factor(as.character(te[[fv]]), levels=levels(tr[[fv]]))
    }
  }

  fit_gn <- tryCatch(
    glm(AvgClaim ~ 1, family=Gamma(link="log"), data=tr, weights=ClaimNb),
    error=function(e) NULL)
  fit_g1 <- tryCatch(
    suppressWarnings(glm(AvgClaim ~ VehPowerGLM + VehAgeGLM + DrivAgeGLM + BonusMalusGLM +
          VehBrand + VehGas + DensityGLM + Region + AreaGLM,
        family=Gamma(link="log"), data=tr, weights=ClaimNb)),
    error=function(e) NULL)
  fit_g2 <- tryCatch(
    glm(AvgClaim ~ BonusMalusGLM + DrivAgeGLM, family=Gamma(link="log"),
        data=tr, weights=ClaimNb),
    error=function(e) NULL)
  fit_in <- tryCatch(
    suppressWarnings(glm(AvgClaim ~ 1,
        family=inverse.gaussian(link="log"), data=tr, weights=ClaimNb,
        start=if(!is.null(fit_gn)) coef(fit_gn) else NULL,
        control=glm.control(maxit=200L))),
    error=function(e) NULL)
  fit_i2 <- tryCatch(
    suppressWarnings(glm(AvgClaim ~ BonusMalusGLM + DrivAgeGLM,
        family=inverse.gaussian(link="log"), data=tr, weights=ClaimNb,
        start=if(!is.null(fit_g2)) coef(fit_g2) else NULL,
        control=glm.control(maxit=200L))),
    error=function(e) NULL)

  te_valid <- !is.na(te$AvgClaim) & te$AvgClaim > 0
  if (!is.null(fit_gn) && any(te_valid)) {
    p <- safe_pred(fit_gn, te[te_valid,]); valid <- !is.na(p) & p>0
    if(any(valid)) cv_results[k,"GamNull"] <- gamma_dev(te$AvgClaim[te_valid][valid], p[valid])
  }
  if (!is.null(fit_g1) && any(te_valid)) {
    p <- safe_pred(fit_g1, te[te_valid,]); valid <- !is.na(p) & p>0
    if(any(valid)) cv_results[k,"GamGLM1"] <- gamma_dev(te$AvgClaim[te_valid][valid], p[valid])
  }
  if (!is.null(fit_g2) && any(te_valid)) {
    p <- safe_pred(fit_g2, te[te_valid,]); valid <- !is.na(p) & p>0
    if(any(valid)) cv_results[k,"GamGLM2"] <- gamma_dev(te$AvgClaim[te_valid][valid], p[valid])
  }
  if (!is.null(fit_in) && any(te_valid)) {
    p <- safe_pred(fit_in, te[te_valid,]); valid <- !is.na(p) & p>0
    if(any(valid)) cv_results[k,"IGNull"]  <- ig_dev(te$AvgClaim[te_valid][valid], p[valid])
  }
  if (!is.null(fit_i2) && any(te_valid)) {
    p <- safe_pred(fit_i2, te[te_valid,]); valid <- !is.na(p) & p>0
    if(any(valid)) cv_results[k,"IGGLM2"]  <- ig_dev(te$AvgClaim[te_valid][valid], p[valid])
  }
}

cv_means <- colMeans(cv_results, na.rm = TRUE)
cv_sds   <- apply(cv_results, 2, sd, na.rm = TRUE)

message(sprintf("  %-12s  CV Loss = %.4f  (SD = %.4f)", "Gamma Null",  cv_means["GamNull"],cv_sds["GamNull"]))
message(sprintf("  %-12s  CV Loss = %.4f  (SD = %.4f)", "Gamma GLM1",  cv_means["GamGLM1"],cv_sds["GamGLM1"]))
message(sprintf("  %-12s  CV Loss = %.4f  (SD = %.4f)", "Gamma GLM2",  cv_means["GamGLM2"],cv_sds["GamGLM2"]))
message(sprintf("  %-12s  CV Loss = %.6f  (SD = %.6f)", "IG Null",     cv_means["IGNull"],cv_sds["IGNull"]))
message(sprintf("  %-12s  CV Loss = %.6f  (SD = %.6f)\n","IG GLM2",    cv_means["IGGLM2"],cv_sds["IGGLM2"]))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 7 — MODEL COMPARISON TABLE (Table 5.13 equivalent)
# ══════════════════════════════════════════════════════════════════════════════

comp_tbl <- data.frame(
  Model        = c("Gamma Null","Gamma GLM1","Gamma GLM2","IG Null","IG GLM2"),
  N_Params     = c(1L+1L, length(coef(gam1))+1L, length(coef(gam2))+1L, 1L+1L, length(coef(ig_glm2))+1L),
  AIC_R        = round(c(AIC(gam_null), AIC(gam1), AIC(gam2), AIC(ig_null), AIC(ig_glm2)), 1),
  AIC_MLE      = round(c(aic_null_mle, aic_gam1_mle, aic_gam2_mle, NA, NA), 1),
  Phi_Pearson  = round(c(phi_null_P, phi1_P, phi2_P, phi_ig_null, phi_ig_glm2), 4),
  InSample_Loss= round(c(
    gamma_dev(sev$AvgClaim, fitted(gam_null)),
    gamma_dev(sev$AvgClaim, fitted(gam1)),
    gamma_dev(sev$AvgClaim, fitted(gam2)),
    ig_dev(sev$AvgClaim, fitted(ig_null)),
    ig_dev(sev$AvgClaim, fitted(ig_glm2))
  ), 4),
  CV_Loss      = round(cv_means, 4),
  AvgAmount    = round(c(
    mean(fitted(gam_null)), mean(fitted(gam1)),
    mean(fitted(gam2)),     mean(fitted(ig_null)),
    mean(fitted(ig_glm2))
  ), 2),
  stringsAsFactors = FALSE
)

message("  ── Model comparison (Table 5.13 equivalent) ──────────────────────────")
message(sprintf("  %-14s %6s %8s %9s %11s %11s %9s %10s",
                "Model", "Params", "AIC_R", "AIC_MLE",
                "phi_P", "InSample", "CV Loss", "AvgAmount"))
for (i in seq_len(nrow(comp_tbl))) {
  r <- comp_tbl[i,]
  message(sprintf("  %-14s %6d %8.1f %9s %11.4f %11.4f %9.4f %10.2f",
                  r$Model, r$N_Params, r$AIC_R,
                  ifelse(is.na(r$AIC_MLE), "—", sprintf("%.1f", r$AIC_MLE)),
                  r$Phi_Pearson, r$InSample_Loss, r$CV_Loss, r$AvgAmount))
}
message(sprintf("\n  Observed mean Y: %.2f", mean_Y))
message(sprintf("  Dispersion phi ≈ %.4f → alpha=1/phi ≈ %.4f (shape parameter, p. 172)",
                phi2_P, 1/phi2_P))
message(sprintf("  alpha < 1: density strictly decreasing → heavy-tail concern (p. 172)\n"))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 8 — BALANCE PROPERTY CORRECTION (p. 172)
# ══════════════════════════════════════════════════════════════════════════════
# Buch (S. 172): „Für die Preisberechnung sollte der Schnittpunktparameter beta_0^MLE
# verschoben werden, um diesen Bias zu beseitigen, d. h., wir müssen diesen Parameter unter
# der Log-Verknüpfung um -log(Mittelwert(geschätzt)/Mittelwert(Y)) verschieben – für das Gamma-GLM2-Modell.“
#
# Korrektur: beta_0^corrected = beta_0^MLE - log(Mittelwert(mu_i) / Mittelwert(Y_i))

message("STEP 8: Balance property correction (p. 172) ...")

balance_shift_gam2 <- -log(mean(fitted(gam2)) / mean_Y)
message(sprintf("  Gamma GLM2 balance correction: delta_beta0 = %.6f", balance_shift_gam2))
message(sprintf("  Before correction: mean(mu_i) = %.4f  |  mean(Y_i) = %.4f",
                mean(fitted(gam2)), mean_Y))

# Korrektur auf den Achsenabschnitt anwenden
coef_corrected      <- coef(gam2)
coef_corrected["(Intercept)"] <- coef_corrected["(Intercept)"] + balance_shift_gam2
mu_corrected        <- exp(model.matrix(gam2) %*% coef_corrected)
message(sprintf("  After  correction: mean(mu_i) = %.4f  |  mean(Y_i) = %.4f\n",
                mean(mu_corrected), mean_Y))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 9 — DIAGNOSTIC PLOTS
# ══════════════════════════════════════════════════════════════════════════════

message("STEP 9: Building diagnostic plots ...")

# 9a. Empirical density + cube-root check (Fig. 5.9, 5.10) -------------------
plot_claim_distribution <- function() {
  p1 <- ggplot(sev, aes(x = AvgClaim)) +
    geom_histogram(aes(y = after_stat(density)), bins = 25,
                   fill = C1, colour = "white", linewidth = 0.2) +
    geom_density(colour = C2, linewidth = 1.0, adjust = 1.2) +
    scale_x_continuous(labels = scales::comma_format()) +
    labs(title    = "Empirical density of Y_i = S_i/n_i  (Fig. 5.9 lhs equivalent)",
         subtitle = sprintf("m = %d policies with N_i > 0 | mean = %.0f | sd = %.0f",
                            m, mean_Y, sd_Y),
         x = "Average claim amount (EUR)", y = "Density") +
    theme_gam()

  cr_df <- data.frame(cr = sev$AvgClaim^(1/3))
  p2    <- ggplot(cr_df, aes(x = cr)) +
    geom_histogram(aes(y = after_stat(density)), bins = 20,
                   fill = C3, colour = "white", linewidth = 0.2) +
    geom_density(colour = C2, linewidth = 1.0, adjust = 1.2) +
    labs(title    = "Cube-root Y_i^(1/3)  (Fig. 5.10 rhs; Wilson-Hilferty, eq. 5.47-5.48)",
         subtitle = sprintf("Skewness = %.4f | Kurtosis = %.4f | (≈ Normal → Gamma suitable)",
                            cr_skew, cr_kurt),
         x = expression(Y[i]^{1/3}~"  (EUR"^{1/3}~")"), y = "Density") +
    theme_gam()

  gridExtra::grid.arrange(p1, p2, ncol = 2)
}

# 9b. Log-log plot (Fig. 5.9 rhs) -----------------------------------------------
plot_loglog <- function() {
  sorted_y <- sort(sev$AvgClaim, decreasing = TRUE)
  n_y      <- length(sorted_y)
  surv     <- seq_len(n_y) / n_y
  df_ll    <- data.frame(log_y = log(sorted_y), log_s = log(surv))
  df_ll    <- df_ll[is.finite(df_ll$log_y) & is.finite(df_ll$log_s), ]

  # Fit tail slope (linear in log-log = power law)
  lm_tail <- lm(log_s ~ log_y, data = df_ll)

  ggplot(df_ll, aes(x = log_y, y = log_s)) +
    geom_point(colour = C1, alpha = 0.6, size = 1.5) +
    geom_smooth(method = "lm", se = TRUE, colour = C2, linewidth = 0.9,
                fill = C2, alpha = 0.15) +
    annotate("text", x = min(df_ll$log_y) + 0.5, y = -0.5,
             label = sprintf("Tail slope: %.3f\n(> -3: light tail → Gamma adequate;\n< -3: heavy tail → Gamma may underfit)",
                             coef(lm_tail)[2]),
             size = 3.2, colour = "grey30", hjust = 0) +
    labs(title    = "Log-log plot of average claim amounts  (Fig. 5.9 rhs equivalent)",
         subtitle = "Straight line in log-log = power-law tail | Steep slope = light tails",
         x = "log(average claim amount)", y = "log(survival probability)") +
    theme_gam()
}

# 9c. Tukey-Anscombe plot + QQ plot (Fig. 5.11) --------------------------------
plot_diagnostics <- function(fit, label = "", phi = NULL) {
  mu    <- fitted(fit)
  y     <- sev$AvgClaim
  phi_  <- if (is.null(phi)) summary(fit)$dispersion else phi

  # Deviance residuals (eq. 5.48): r^D = sign(y-mu) * sqrt(d(y,mu))
  rD    <- residuals(fit, type = "deviance")
  # Pearson residuals (eq. 5.49)
  rP    <- residuals(fit, type = "pearson")

  df_ta <- data.frame(log_mu = log(mu), rD = rD, rP = rP)

  p1 <- ggplot(df_ta, aes(x = log_mu, y = rD)) +
    geom_point(colour = C1, alpha = 0.55, size = 1.5) +
    geom_hline(yintercept = c(-2, 0, 2),
               linetype = c("dashed","solid","dashed"),
               colour   = c(C2, "grey40", C2), linewidth = 0.55) +
    geom_smooth(method = "loess", se = TRUE, colour = C4, linewidth = 0.8,
                fill = C4, alpha = 0.2) +
    labs(
      title    = sprintf("Tukey-Anscombe plot — %s  (Fig. 5.11 lhs)", label),
      subtitle = sprintf("Deviance residuals r^D vs log(mu_hat) | phi_P = %.4f | alpha = %.4f",
                         phi_, 1/phi_),
      x = "Fitted values log(mu_hat)", y = "Deviance residual r^D"
    ) +
    theme_gam()

  # QQ plot: scaled residuals Y_i/mu_i ~ Gamma(alpha, alpha) if model correct
  alpha_est <- 1 / phi_
  scaled    <- y / mu
  q_theory  <- qgamma(ppoints(length(scaled)),
                       shape = alpha_est, scale = 1 / alpha_est)
  df_qq <- data.frame(theory = sort(q_theory), obs = sort(scaled))

  p2 <- ggplot(df_qq, aes(x = theory, y = obs)) +
    geom_abline(slope = 1, intercept = 0, colour = C2,
                linetype = "dashed", linewidth = 0.9) +
    geom_point(colour = C1, alpha = 0.55, size = 1.5) +
    labs(
      title    = sprintf("QQ plot — %s  (Fig. 5.11 rhs)", label),
      subtitle = sprintf("Scaled residuals Y/mu ~ Gamma(alpha,alpha) | alpha = %.4f | n=%d",
                         alpha_est, length(scaled)),
      x = "Theoretical Gamma quantiles", y = "Observed scaled residuals Y/mu_hat"
    ) +
    theme_gam()

  gridExtra::grid.arrange(p1, p2, ncol = 2)
}

# 9d. Coefficient forest plot ------------------------------------------------
plot_coef_gamma <- function(fit, label = "Gamma GLM2") {
  cf <- summary(fit)$coefficients
  df <- data.frame(
    Term  = rownames(cf), Est = cf[,1], SE = cf[,2],
    t_val = cf[,3], p = cf[,4], stringsAsFactors = FALSE
  )
  df       <- df[df$Term != "(Intercept)", ]
  df$RR    <- round(exp(df$Est), 3)
  df$Lo95  <- exp(df$Est - 2 * df$SE)
  df$Hi95  <- exp(df$Est + 2 * df$SE)
  df$Sig   <- ifelse(df$p < 0.001,"***",ifelse(df$p<0.01,"**",ifelse(df$p<0.05,"*","  ")))
  df       <- df[order(abs(df$Est), decreasing = TRUE), ]
  df$Term  <- factor(df$Term, levels = rev(df$Term))

  ggplot(df, aes(x = RR, y = Term, colour = Est > 0)) +
    geom_vline(xintercept = 1, linetype="dashed", colour="grey50", linewidth=0.7) +
    geom_errorbarh(aes(xmin=Lo95, xmax=Hi95), height=0.4, linewidth=0.5, alpha=0.7) +
    geom_point(size = 2.5) +
    geom_text(aes(label = paste0(sprintf("%.3f", RR), Sig)),
              hjust = -0.2, size = 2.8, colour = "grey25") +
    scale_colour_manual(values=c("TRUE"=C1,"FALSE"=C2),
                        labels=c("TRUE"="Severity ↑","FALSE"="Severity ↓"), name=NULL) +
    scale_x_log10() +
    labs(title    = sprintf("%s — Relative severity exp(β)", label),
         subtitle = "exp(β): multiplicative effect on E[Y_i | N_i>0] | 95% CI | F-test * p<.05",
         x = "Relative severity exp(β) [log scale]", y = NULL) +
    theme_gam() + theme(axis.text.y = element_text(size = 8))
}

# 9e. Model comparison table plot --------------------------------------------
plot_comparison_table <- function() {
  tbl <- comp_tbl[, c("Model","N_Params","AIC_R","AIC_MLE",
                       "Phi_Pearson","InSample_Loss","CV_Loss","AvgAmount")]
  names(tbl) <- c("Model","Params","AIC (R)","AIC (MLE)","φ̂_P","D_in","D_CV","Ȳ pred")
  tbl_g <- gridExtra::tableGrob(
    tbl, rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core    = list(fg_params = list(cex = 0.80)),
      colhead = list(fg_params = list(cex = 0.84, fontface = "bold"),
                     bg_params = list(fill = C3, alpha = 0.85))
    )
  )
  title_g <- grid::textGrob(
    "Table 5.13 equivalent — Gamma & IG GLM comparison for claim severity",
    gp = grid::gpar(fontsize = 12, fontface = "bold")
  )
  note_g <- grid::textGrob(
    paste0(
      "Target: Y_i = S_i/n_i (avg claim, eq. 5.45) | Subset: N_i > 0 | Weights = n_i\n",
      "Gamma: V(μ)=μ² | IG: V(μ)=μ³ | Log-link (not canonical) → balance NOT auto-satisfied\n",
      "AIC(MLE) = -2logL(β,α_MLE)+2(q+2) [Remark 5.26] | AIC(R) uses deviance φ̂_D\n",
      "φ̂_P = Pearson dispersion (eq. 5.49) | α = 1/φ = shape parameter\n",
      sprintf("Balance correction (p.172): delta_β₀ = %.6f for Gamma GLM2", balance_shift_gam2)
    ),
    gp = grid::gpar(fontsize = 8, col = "grey35")
  )
  gridExtra::grid.arrange(title_g, tbl_g, note_g, ncol = 1, heights = c(0.05,0.65,0.30))
}

# 9f. CV loss comparison bar chart ------------------------------------------
plot_cv_comparison <- function() {
  df <- data.frame(
    Model  = c("Gamma Null","Gamma GLM1","Gamma GLM2","IG Null","IG GLM2"),
    CVLoss = cv_means,
    Family = c("Gamma","Gamma","Gamma","IG","IG")
  )
  df$Model <- factor(df$Model, levels = rev(df$Model))
  ggplot(df, aes(x = CVLoss, y = Model, fill = Family)) +
    geom_col(width = 0.65, colour = "white", linewidth = 0.2) +
    geom_text(aes(label = sprintf("%.4f", CVLoss)), hjust = -0.1, size = 3.0) +
    scale_fill_manual(values = c(Gamma = C1, IG = C4)) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.25))) +
    labs(title    = "10-fold cross-validation deviance loss",
         subtitle = paste0("Gamma: d(y,μ) = 2[y/μ−1−log(y/μ)] (eq. 5.46)\n",
                           "IG:    d(y,μ) = (y−μ)²/(μ²y) (eq. 5.52)"),
         x = "CV deviance loss (φ=1)", y = NULL, fill = NULL) +
    theme_gam()
}

# 9g. Gamma vs IG variance functions ----------------------------------------
plot_variance_functions <- function() {
  mu_seq <- seq(0.01, 3, length.out = 300)
  df     <- rbind(
    data.frame(mu=mu_seq, V=mu_seq^2, Family="Gamma: V(μ)=μ²"),
    data.frame(mu=mu_seq, V=mu_seq^3, Family="IG: V(μ)=μ³")
  )
  ggplot(df, aes(x=mu, y=V, colour=Family, linetype=Family)) +
    geom_line(linewidth=1.2) +
    scale_colour_manual(values=c(C1, C4)) +
    labs(title    = "Variance functions: Gamma vs Inverse Gaussian (Section 5.3.7-5.3.8)",
         subtitle = paste0("Gamma V(μ)=μ²: CoV(Z) = 1/√α (constant in μ)\n",
                           "IG V(μ)=μ³: CoV(Z) = √(μ/α) (increases in μ → less suitable for insurance)"),
         x="Mean μ", y="Variance function V(μ)", colour=NULL, linetype=NULL) +
    theme_gam()
}

# 9h. Marginal empirical frequencies (Fig. 5.3 equivalent for severity) ------
plot_marginal_sev <- function(var) {
  agg <- aggregate(AvgClaim ~ sev[[var]], data=sev, FUN=mean)
  names(agg) <- c("Level","MeanClaim")
  agg$Level  <- as.character(agg$Level)
  ggplot(agg, aes(x=Level, y=MeanClaim)) +
    geom_col(fill=C1, width=0.7, colour="white", linewidth=0.2) +
    geom_text(aes(label=sprintf("%.0f",MeanClaim)), vjust=-0.4, size=2.8) +
    scale_y_continuous(expand=expansion(mult=c(0,0.18)), labels=scales::comma_format()) +
    labs(title=sprintf("Mean claim amount by %s", var),
         x=var, y="Mean Y_i (EUR)") +
    theme_gam() + theme(axis.text.x=element_text(angle=30, hjust=1))
}


# ══════════════════════════════════════════════════════════════════════════════
# STEP 10 — ASSEMBLE PDF REPORT
# ══════════════════════════════════════════════════════════════════════════════

message("STEP 10: Assembling PDF report ...")

pdf("gamma_glm_report.pdf", width = 13, height = 8.5, onefile = TRUE)

# Page 1: Model comparison table
plot_comparison_table()

# Page 2: Empirical density + cube-root test (Fig. 5.9/5.10)
plot_claim_distribution()

# Page 3: Log-log plot (Fig. 5.9 rhs)
print(plot_loglog())

# Page 4: Variance functions (Gamma vs IG)
print(plot_variance_functions())

# Page 5: CV comparison
print(plot_cv_comparison())

# Page 6: Tukey-Anscombe + QQ for Gamma GLM2 (Fig. 5.11)
plot_diagnostics(gam2, "Gamma GLM2", phi2_P)

# Page 7: Tukey-Anscombe + QQ for Gamma GLM1
plot_diagnostics(gam1, "Gamma GLM1", phi1_P)

# Page 8: Tukey-Anscombe + QQ for IG GLM2
plot_diagnostics(ig_glm2, "IG GLM2", phi_ig_glm2)

# Page 9: Gamma GLM2 coefficient plot
suppressWarnings(print(plot_coef_gamma(gam2, "Gamma GLM2")))

# Page 10: Marginal mean claim amounts
p_bm  <- plot_marginal_sev("DrivAgeGLM")
p_drv <- plot_marginal_sev("VehAgeGLM")
suppressWarnings(gridExtra::grid.arrange(p_bm, p_drv, ncol=2,
  top=grid::textGrob("Mean claim amount by feature level",
    gp=grid::gpar(fontsize=12,fontface="bold"))))

dev.off()
message("  Report saved: 'gamma_glm_report.pdf'\n")


# ══════════════════════════════════════════════════════════════════════════════
# STEP 11 — SAVE MODELS
# ══════════════════════════════════════════════════════════════════════════════

saveRDS(list(
  gam_null        = gam_null,
  gam1            = gam1,
  gam2            = gam2,
  ig_null         = ig_null,
  ig_glm2         = ig_glm2,
  comp_tbl        = comp_tbl,
  cv_results      = cv_results,
  phi_mle         = list(null=mle_null, glm1=mle_gam1, glm2=mle_gam2),
  balance_shift   = balance_shift_gam2,
  sev_data        = sev
), "gamma_models.rds")

message("══════════════════════════════════════════════════════════════════")
message("  GAMMA GLM SEVERITY — PHASE 2 COMPLETE")
message("  gamma_glm_report.pdf — 10-page diagnostic report")
message("  gamma_models.rds     — all fitted objects")
message("")
message(sprintf("  %-20s  AIC_R=%.1f  phi_P=%.4f  alpha=%.4f  CV=%.4f",
                "Gamma Null", AIC(gam_null), phi_null_P, mle_null$alpha, cv_means["GamNull"]))
message(sprintf("  %-20s  AIC_R=%.1f  phi_P=%.4f  alpha=%.4f  CV=%.4f",
                "Gamma GLM1", AIC(gam1),     phi1_P,     mle_gam1$alpha, cv_means["GamGLM1"]))
message(sprintf("  %-20s  AIC_R=%.1f  phi_P=%.4f  alpha=%.4f  CV=%.4f",
                "Gamma GLM2", AIC(gam2),     phi2_P,     mle_gam2$alpha, cv_means["GamGLM2"]))
message(sprintf("  %-20s  AIC_R=%.1f  phi_P=%.6f  CV=%.6f",
                "IG GLM2",    AIC(ig_glm2),  phi_ig_glm2,               cv_means["IGGLM2"]))
message("")
message(sprintf("  Balance correction (p.172): delta_beta0 = %.6f", balance_shift_gam2))
message(sprintf("  Dispersion phi_P(GLM2) = %.4f  =>  alpha = %.4f < 1", phi2_P, 1/phi2_P))
message("  (alpha<1: density strictly decreasing; heavy-tail indication, book p.172)")
message("══════════════════════════════════════════════════════════════════")
