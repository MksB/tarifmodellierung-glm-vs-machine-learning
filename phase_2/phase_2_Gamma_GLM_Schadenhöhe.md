Gamma GLM für Schadenhöhen (Claim Severity)
================


## Überblick

Dieses Skript implementiert **Phase 2** einer zweiteiligen
versicherungsmathematischen Modellierungspipeline:

| Phase | Modell        | Ziel                                       |
|-------|---------------|--------------------------------------------|
| 1     | Poisson GLM   | Schadenhäufigkeit (Frequency)              |
| **2** | **Gamma GLM** | **Schadenhöhe (Severity) → dieses Skript** |

Das Produkt beider Phasen ergibt die **Pure Premium** (Risikoprämie):

$$\text{Pure Premium}_i = \underbrace{\hat{\lambda}_i}_{\text{Poisson GLM}} \times \underbrace{\hat{\mu}_i}_{\text{Gamma GLM}}$$

**Referenz:** Wüthrich & Merz, *Statistical Foundations of Actuarial
Learning and its Applications* (2023), Abschnitte 5.3.7–5.3.9, S.
167–180.

------------------------------------------------------------------------

## Theoretischer Hintergrund

### Das Gamma-GLM-Modell

**Zielvariable**:

$$Y_i = \frac{S_i}{n_i} \quad \text{(durchschnittliche Schadenhöhe pro Police)}$$

wobei $S_i$ der Gesamtschaden und $n_i = \texttt{ClaimNb}$ die Anzahl
der Schäden auf Police $i$ ist.

**Modellspezifikation:**

$$Y_i \sim \text{Gamma}(n_i \cdot \alpha,\; n_i \cdot \alpha \cdot c_i) \quad \text{(Gl. 5.45)}$$

| Komponente | Wert | Begründung |
|----|----|----|
| Link-Funktion | $g(\mu_i) = \log(\mu_i)$ | Log-Link (nicht kanonisch) |
| Gewichte | $w_i = n_i = \texttt{ClaimNb}$ | Gamma ist abgeschlossen unter i.i.d. Summen |
| Dispersion | $\phi = 1/\alpha$ | Nuisance-Parameter, wird geschätzt |
| Subset | $n_i > 0$ | Nur Policen mit mindestens einem Schaden |

### Warum der Log-Link (nicht der kanonische Link $-\frac{1}{\mu}$)?

Der **kanonische Link** für Gamma ist $\theta_i = -c_i = -1/\mu_i$. Wir
verwenden stattdessen den **Log-Link**, weil:

1.  Er $\mu_i > 0$ automatisch garantiert
2.  Er eine **multiplikative Interpretation** von $\exp(\beta_j)$
    ermöglicht
3.  Er mit dem Poisson-GLM kompatibel ist:
    $\log(\text{Freq}) + \log(\text{Sev}) = \log(\text{Pure Premium})$

> **Konsequenz:** Die **Balance-Eigenschaft**
> $\sum_i \hat{\mu}_i = \sum_i Y_i$ ist unter dem Log-Link **nicht
> automatisch erfüllt** (nur unter dem kanonischen Link). Der Intercept
> muss für Preisstellungszwecke korrigiert werden (Buch S. 172).

### Warum kein `offset(log(Exposure))` im Severity-Modell?

Das Gamma-GLM modelliert die **durchschnittliche** Schadenhöhe
$Y_i = S_i/n_i$, nicht den Gesamtschaden. Das Gewicht $n_i$ trägt
bereits das Schadensvolumen. Die Exposure geht **nur** in das
Häufigkeitsmodell (Poisson) ein — ein Offset im Severity-Modell würde
fälschlicherweise Häufigkeits- und Schwereinformation vermischen.

------------------------------------------------------------------------

## Pakete & Farbpalette

``` r
for (pkg in c("MASS", "ggplot2", "gridExtra", "scales")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop(sprintf("Install: install.packages('%s')", pkg))
}
library(MASS); library(ggplot2); library(gridExtra); library(scales)
```

``` r
# Einheitliches Theme für alle Plots
theme_gam <- function(base = 11) {
  theme_minimal(base_size = base) +
    theme(plot.title       = element_text(face = "bold", size = base + 2),
          plot.subtitle    = element_text(size = base - 1, colour = "grey40"),
          panel.grid.minor = element_blank(),
          strip.text       = element_text(face = "bold"),
          legend.position  = "top")
}

# Vier Farben: Blau / Rot / Grün / Orange
C1 <- "#4472C4"; C2 <- "#C00000"; C3 <- "#70AD47"; C4 <- "#ED7D31"
```

------------------------------------------------------------------------

## Schritt 0 — Datenvorbereitung

**Datenquelle:** `freMTPL2sev` (Schadenhöhen) + `freMTPL2freq`
(Kovariablen), Appendix B.13.1, S. 553–563.

``` r
freq_raw <- read.csv("freMTPL2freq.csv", stringsAsFactors = FALSE)
sev_raw  <- read.csv("freMTPL2sev.csv",  stringsAsFactors = FALSE)

# Zeilen ohne Schaden entfernen
sev_raw <- sev_raw[!is.na(sev_raw$IDpol) &
                   !is.na(sev_raw$ClaimAmount) &
                   sev_raw$ClaimAmount > 0, ]
```

### Kovariablen-Zuweisung

Da `freMTPLsev` und `freMTPLfreq` **nicht überlappende IDpols** haben
(Stichprobenartefakt), werden Kovariablen aus `freMTPLfreq`
**exposure-proportional** zugewiesen:

``` r
set.seed(123L)
probs      <- freq$Exposure / sum(freq$Exposure)
idx_sample <- sample(nrow(freq), nrow(sev_raw), replace = TRUE, prob = probs)

sev <- data.frame(
  IDpol_sev   = sev_raw$IDpol,
  ClaimAmount = sev_raw$ClaimAmount,
  freq[idx_sample, setdiff(names(freq), c("IDpol", "ClaimNb"))],
  stringsAsFactors = FALSE
)
```

> Schwerere Policen (höhere Exposure) sind stärker repräsentiert —
> aktuarisch korrekte Verteilung.

### Feature Engineering (Listing 5.1)

| Variable        | Transformation              | Typ        |
|-----------------|-----------------------------|------------|
| `AreaGLM`       | `as.integer(Area)`          | Ordinal    |
| `VehPowerGLM`   | `min(VehPower, 9)` → Faktor | Kategorial |
| `VehAgeGLM`     | Cut: 0–5 / 6–12 / 12+       | Kategorial |
| `DrivAgeGLM`    | Cut: 18–20, 21–25, …, 71+   | Kategorial |
| `BonusMalusGLM` | `min(BonusMalus, 150)`      | Numerisch  |
| `DensityGLM`    | `log(Density)`              | Numerisch  |

``` r
sev$VehAgeGLM  <- as.factor(cut(sev$VehAge, c(0, 5, 12, 101),
                    labels = c("0-5", "6-12", "12+"), include.lowest = TRUE))
sev$DrivAgeGLM <- as.factor(cut(sev$DrivAge,
                    c(18, 20, 25, 30, 40, 50, 70, 101),
                    labels = c("18-20","21-25","26-30","31-40","41-50","51-70","71+"),
                    include.lowest = TRUE))
sev$DensityGLM <- log(sev$Density)
sev$AvgClaim   <- sev$ClaimAmount  # Y_i = S_i / n_i
sev$ClaimNb    <- 1L               # Gewichte w_i = 1
```

### Wilson-Hilferty Cube-Root-Test (Gl. 5.47–5.48, S. 170)

Falls $Y_i^{1/3}$ annähernd **normalverteilt** ist, ist das Gamma-Modell
geeignet (Abb. 5.10):

$$Y_i^{1/3} \approx \mathcal{N}\!\left(\mu^{1/3}\!\left(1 - \tfrac{1}{9\alpha}\right),\;\frac{\mu^{2/3}}{9\alpha}\right)$$

``` r
cr      <- sev$AvgClaim^(1/3)
cr_skew <- mean(((cr - mean(cr)) / sd(cr))^3)
cr_kurt <- mean(((cr - mean(cr)) / sd(cr))^4)
# Skewness ≈ 0 und Kurtosis ≈ 3 → Gamma-Modell unterstützt
```

------------------------------------------------------------------------

## Schritt 1 — Gamma-Null-Modell

**Referenz:** Tabelle 5.13, S. 170 — Baseline (Intercept-only).

Unter dem Log-Link gilt:
$\log(\mu_i) = \beta_0 \Rightarrow \mu_i = e^{\beta_0} = \bar{Y}$
(gewichtetes Mittel).

``` r
gam_null <- glm(
  AvgClaim ~ 1,
  family  = Gamma(link = "log"),
  data    = sev,
  weights = ClaimNb
)

phi_null_P <- sum(residuals(gam_null, "pearson")^2) / gam_null$df.residual
```

------------------------------------------------------------------------

## Schritt 2 — Gamma GLM1: Volles Modell

**Referenz:** Listing 5.11, S. 171. Das Modell enthält **q+1 = 9
Variablengruppen** mit insgesamt ~49 Parametern (analog zum Poisson
GLM1).

``` r
gam1 <- glm(
  AvgClaim ~ VehPowerGLM + VehAgeGLM + DrivAgeGLM +
             BonusMalusGLM + VehBrand + VehGas +
             DensityGLM + Region + AreaGLM,
  family  = Gamma(link = "log"),
  data    = sev,
  weights = ClaimNb
  # KEIN offset(log(Exposure)) — nur im Poisson-Modell!
)
```

**In-Sample Gamma-Devianz-Loss** (Gl. 5.46, $\phi = 1$):

$$D(L, \hat{\mu}) = \frac{1}{m} \sum_{i=1}^{m} 2 \left[\frac{Y_i}{\hat{\mu}_i} - 1 - \log\!\frac{Y_i}{\hat{\mu}_i}\right]$$

### Balance-Eigenschaft

``` r
balance1 <- sum(fitted(gam1)) / sum(sev$AvgClaim) * 100
# Log-Link garantiert keine Balance → Korrektur erforderlich (s. Schritt 8)
```

------------------------------------------------------------------------

## Schritt 3 — Rückwärtsselektion → Gamma GLM2

**Referenz:** Abschnitt 5.3.3, S. 147. F-Test ist angemessen für Gamma
(da $\phi \neq 1$ geschätzt wird, anders als beim Poisson).

``` r
# Sequentielle ANOVA mit F-Test
anova_gam1 <- anova(gam1, test = "F")

# Drop-One-Test: Welche Variable kann gestrichen werden?
drop1_gam1 <- drop1(gam1, test = "F")
```

**Reduziertes Modell (GLM2)** nach Rückwärtsselektion (nur signifikante
Variablen, p \< 0.10):

``` r
gam2 <- glm(
  AvgClaim ~ BonusMalusGLM + DrivAgeGLM,
  family  = Gamma(link = "log"),
  data    = sev,
  weights = ClaimNb
)
```

------------------------------------------------------------------------

## Schritt 4 — MLE des Dispersionsparameters $\phi$

**Referenz:** Bemerkung 5.26, S. 173.

R’s `glm()` schätzt $\phi$ standardmäßig über die **Devianz**
($\hat{\phi}_D$), **nicht** per MLE. Die Score-Gleichung für
$\alpha = 1/\phi$ lautet:

$$\log(\alpha) + 1 - \psi(\alpha) = \overline{\log(Y_i/\hat{\mu}_i)}^w$$

wobei $\psi(\cdot)$ die Digamma-Funktion ist.

``` r
compute_phi_mle <- function(fit, y, w) {
  mu  <- fitted(fit)
  rhs <- weighted.mean(log(y / mu), w)
  score <- function(alpha) log(alpha) + 1 - digamma(alpha) - rhs
  alpha_mle <- uniroot(score, c(1e-6, 1e6), tol = 1e-10)$root
  list(alpha = alpha_mle, method = "MLE (Remark 5.26)")
}

mle_gam2 <- compute_phi_mle(gam2, sev$AvgClaim, sev$ClaimNb)
```

**MLE-basierter AIC** (Tabelle 5.13) mit $+1$ für den
Dispersionsparameter:

$$\text{AIC}_{\text{MLE}} = -2\,\ell(\hat{\beta}, \hat{\alpha}_{\text{MLE}}) + 2(q + 2)$$

> `glm()`’s AIC verwendet $\hat{\phi}_D$ (Devianz-basiert) und
> überschätzt den AIC leicht (Buch S. 172).

------------------------------------------------------------------------

## Schritt 5 — Inverse-Gaussian-GLM

**Referenz:** Abschnitt 5.3.8, S. 173–178. Konkurrenzmodell mit
kubischer Varianzfunktion $V(\mu) = \mu^3$ (vs. Gamma’s
$V(\mu) = \mu^2$).

| Eigenschaft | Gamma | Inverse Gaussian |
|----|----|----|
| Varianzfunktion | $V(\mu) = \mu^2$ | $V(\mu) = \mu^3$ |
| Unit-Devianz | $2[y/\mu - 1 - \log(y/\mu)]$ | $(y-\mu)^2/(\mu^2 y)$ |
| VK | $\text{VK}(Z) = 1/\sqrt{\alpha}$ (konstant in $\mu$) | $\text{VK}(Z) = \sqrt{\mu/\alpha}$ (wächst in $\mu$) |

Das **wachsende VK** der IG macht sie für Versicherungsdaten oft
**weniger geeignet** (Buch S. 177).

``` r
# Startwerte aus Gamma GLM2 (Buch S. 175: nicht-konkave Loglikelihood)
ig_glm2 <- glm(
  AvgClaim ~ BonusMalusGLM + DrivAgeGLM,
  family  = inverse.gaussian(link = "log"),
  data    = sev,
  weights = ClaimNb,
  start   = coef(gam2),             # Startpunkt aus Gamma GLM2
  control = glm.control(maxit = 200L)
)
```

------------------------------------------------------------------------

## Schritt 6 — 10-fache Kreuzvalidierung

**Referenz:** Tabelle 5.13, Spalte “TenfoldCV”, S. 171. Alle 5 Modelle
(Gamma Null, GLM1, GLM2, IG Null, IG GLM2) werden evaluiert.

``` r
set.seed(500L)
K     <- 10L
folds <- sample(rep(seq_len(K), length.out = m))

# Gamma-Devianz-Loss (Gl. 5.46, phi=1)
gamma_dev <- function(y, mu, w = 1) mean(w * 2 * (y/mu - 1 - log(y/mu)))

# IG-Devianz-Loss (Gl. 5.52, phi=1)
ig_dev <- function(y, mu, w = 1) mean(w * (y - mu)^2 / (mu^2 * y))
```

Für jeden Fold $k = 1, \ldots, 10$:

1.  Modelle auf Trainingsdaten $\mathcal{D} \setminus \mathcal{D}_k$
    anpassen
2.  Vorhersagen auf $\mathcal{D}_k$ berechnen
3.  Devianz-Loss auf Testdaten auswerten

> **Robustheit:** Neue Faktorstufen im Testset werden per `safe_pred()`
> abgefangen (gibt `NA` zurück, statt Fehler zu werfen).

------------------------------------------------------------------------

## Schritt 7 — Modellvergleich (Tabelle 5.13)

``` r
comp_tbl <- data.frame(
  Model         = c("Gamma Null","Gamma GLM1","Gamma GLM2","IG Null","IG GLM2"),
  N_Params      = c(2, length(coef(gam1))+1, length(coef(gam2))+1, 2, length(coef(ig_glm2))+1),
  AIC_R         = round(c(AIC(gam_null), AIC(gam1), AIC(gam2), AIC(ig_null), AIC(ig_glm2)), 1),
  AIC_MLE       = round(c(aic_null_mle, aic_gam1_mle, aic_gam2_mle, NA, NA), 1),
  Phi_Pearson   = round(c(phi_null_P, phi1_P, phi2_P, phi_ig_null, phi_ig_glm2), 4),
  InSample_Loss = ...,
  CV_Loss       = round(cv_means, 4)
)
```

**Erwartete Ergebnisse (analog Tabelle 5.13, S. 171):**

| Modell | Params | AIC (R) | AIC (MLE) | $\hat{\phi}_P$ | $D_{\text{in}}$ | $D_{\text{CV}}$ |
|----|----|----|----|----|----|----|
| Gamma Null | 2 | — | — | — | — | — |
| Gamma GLM1 | ~50 | ↓ | ↓ | — | ↓ | ↓ |
| Gamma GLM2 | ~9 | ↓↓ | ↓↓ | — | ~ | ↓ |
| IG GLM2 | ~9 | vergl. | — | — | vergl. | vergl. |

------------------------------------------------------------------------

## Schritt 8 — Balance-Korrektur des Intercepts

**Referenz:** Buch S. 172.

Unter dem Log-Link ist $\sum_i \hat{\mu}_i \neq \sum_i Y_i$ im
Allgemeinen. Für Preisstellungszwecke wird der Intercept korrigiert:

$$\hat{\beta}_0^{\text{korr}} = \hat{\beta}_0^{\text{MLE}} - \log\!\left(\frac{\bar{\hat{\mu}}}{\bar{Y}}\right)$$

``` r
balance_shift_gam2 <- -log(mean(fitted(gam2)) / mean_Y)

coef_corrected <- coef(gam2)
coef_corrected["(Intercept)"] <- coef_corrected["(Intercept)"] + balance_shift_gam2

mu_corrected <- exp(model.matrix(gam2) %*% coef_corrected)
# Nach Korrektur: mean(mu_corrected) ≈ mean_Y  ✓
```

------------------------------------------------------------------------

## Schritt 9 — Diagnostische Plots

Das Skript erstellt **8 diagnostische Visualisierungen**:

### 9a. Empirische Dichteverteilung + Cube-Root-Test

Entspricht Abb. 5.9 (links) und Abb. 5.10 (rechts). Überprüft die
Gamma-Eignung visuell.

### 9b. Log-Log-Plot (Abb. 5.9 rechts)

    log(Überlebenswahrsch.) vs. log(Schadenhöhe)
    → Gerade = Potenzgesetz-Tail
    → Steigung > -3: leichter Tail (Gamma ausreichend)
    → Steigung < -3: schwerer Tail (Gamma unterschätzt)

### 9c. Tukey-Anscombe-Plot + QQ-Plot (Abb. 5.11)

**Deviance Residuals** (Gl. 5.48):

$$r_i^D = \text{sign}(Y_i - \hat{\mu}_i)\sqrt{d(Y_i, \hat{\mu}_i)}$$

**QQ-Plot:** Skalierte Residuen
$Y_i/\hat{\mu}_i \sim \text{Gamma}(\hat{\alpha}, \hat{\alpha})$ unter
korrektem Modell.

``` r
plot_diagnostics <- function(fit, label = "", phi = NULL) {
  mu   <- fitted(fit)
  y    <- sev$AvgClaim
  phi_ <- if (is.null(phi)) summary(fit)$dispersion else phi
  rD   <- residuals(fit, type = "deviance")

  # Tukey-Anscombe: rD vs log(mu_hat)
  # QQ: sort(Y/mu) vs qgamma(ppoints(n), shape=alpha, scale=1/alpha)
  alpha_est <- 1 / phi_
  scaled    <- y / mu
  q_theory  <- qgamma(ppoints(length(scaled)),
                       shape = alpha_est, scale = 1 / alpha_est)
  # ... (Plots via ggplot2)
}
```

### 9d. Koeffizienten-Forest-Plot

Zeigt $\exp(\hat{\beta}_j)$ (multiplikativer Effekt auf
$\mathbb{E}[Y_i \mid N_i > 0]$) mit 95%-KI für Gamma GLM2.
Signifikanzsterne: `***` p\<0.001, `**` p\<0.01, `*` p\<0.05.

### 9e–9h. Weitere Visualisierungen

| Plot | Inhalt                                                   |
|------|----------------------------------------------------------|
| 9e   | Modellvergleichstabelle (Abb. Tabelle 5.13)              |
| 9f   | CV-Loss Balkendiagramm (alle 5 Modelle)                  |
| 9g   | Varianzfunktionen $V(\mu)$: Gamma vs. IG                 |
| 9h   | Marginale Schadenhöhen nach `DrivAgeGLM` und `VehAgeGLM` |

------------------------------------------------------------------------

## Schritt 10 — PDF-Report (10 Seiten)

``` r
pdf("gamma_glm_report.pdf", width = 13, height = 8.5, onefile = TRUE)

# Seite 1:  Modellvergleichstabelle (Table 5.13 Äquivalent)
# Seite 2:  Empirische Dichte + Cube-Root-Test (Abb. 5.9/5.10)
# Seite 3:  Log-Log-Plot (Abb. 5.9 rhs)
# Seite 4:  Varianzfunktionen Gamma vs. IG
# Seite 5:  CV-Loss Vergleich
# Seite 6:  Tukey-Anscombe + QQ für Gamma GLM2 (Abb. 5.11)
# Seite 7:  Tukey-Anscombe + QQ für Gamma GLM1
# Seite 8:  Tukey-Anscombe + QQ für IG GLM2
# Seite 9:  Koeffizienten-Forest-Plot Gamma GLM2
# Seite 10: Marginale Schadenhöhen nach DrivAge / VehAge

dev.off()
```

------------------------------------------------------------------------

## Schritt 11 — Modelle speichern

``` r
saveRDS(list(
  gam_null      = gam_null,
  gam1          = gam1,
  gam2          = gam2,
  ig_null       = ig_null,
  ig_glm2       = ig_glm2,
  comp_tbl      = comp_tbl,
  cv_results    = cv_results,
  phi_mle       = list(null = mle_null, glm1 = mle_gam1, glm2 = mle_gam2),
  balance_shift = balance_shift_gam2,
  sev_data      = sev
), "gamma_models.rds")
```

Alle gefitteten Objekte werden als `gamma_models.rds` gespeichert und
können in nachgelagerten Analysen (z.B. Pure Premium Berechnung) direkt
geladen werden.

------------------------------------------------------------------------

## Ausgabedateien

| Datei                  | Inhalt                        |
|------------------------|-------------------------------|
| `gamma_glm_report.pdf` | 10-seitiger Diagnosebericht   |
| `gamma_models.rds`     | Alle gefitteten Modellobjekte |

------------------------------------------------------------------------

## Systemanforderungen

``` r
# R >= 4.1
# Pakete: MASS, ggplot2, gridExtra, scales
sessionInfo()
```

| Anforderung | Version |
|-------------|---------|
| R           | \>= 4.1 |
| MASS        | CRAN    |
| ggplot2     | CRAN    |
| gridExtra   | CRAN    |
| scales      | CRAN    |

------------------------------------------------------------------------

## Hinweise & Limitierungen

> **Wichtiger Hinweis (Buch S. 167):** Die Autoren empfehlen für diesen
> Lab explizit, die französischen MTPL-Daten **nicht** zu verwenden, da
> die empirische Dichtefunktion (Abb. 13.15) gegen eine gute
> GLM-Anpassung spricht. Das Skript demonstriert die vollständige
> GLM-Maschinerie dennoch vollständig — dieser Umstand wird klar
> dokumentiert.

Weitere Punkte:

- **Kovariate-Zuweisung:** Da `freMTPL2sev` und `freMTPL2freq` disjunkte
  `IDpol`-Mengen haben, werden Kovariablen exposure-proportional
  gesampelt (`set.seed(123L)`). Die aktuarische Verteilung wird damit
  erhalten.
- **IG-Konvergenz:** Die Inverse-Gaussian-Loglikelihood ist nicht
  konkav. Das Skript startet den IWLS-Algorithmus von den
  Gamma-GLM2-Koeffizienten aus (Buch S. 175) und erhöht `maxit` auf bis
  zu 500, falls Warnungen auftreten.
- **$\alpha < 1$:** Ein geschätzter Shape-Parameter $\hat{\alpha} < 1$
  deutet auf eine **streng monoton fallende Dichte** und einen schweren
  Tail hin (Buch S. 172) — was für Kfz-Haftpflichtschäden typisch ist.

------------------------------------------------------------------------

## Literatur

Wüthrich, M.V., & Merz, M. (2023). *Statistical Foundations of Actuarial
Learning and its Applications*. Springer.

- Abschnitt 5.3.7: Lab: Gamma GLM für Schadenhöhen (S. 167–173)
- Abschnitt 5.3.8: Lab: Inverse Gaussian GLM (S. 173–178)
- Abschnitt 5.3.9: Log-Normal-Modell Diskussion (S. 176–180)
- Bemerkung 5.26: MLE des Dispersionsparameters (S. 173)
- Anhang B.13.1: freMTPL2-Datenbeschreibung (S. 553–563)

------------------------------------------------------------------------

# Kontakt

**Autor:** <marksquant@gmail.com>  
**Projekt:** Tarifmodellierung: GLM vs. Machine Learning; Gamma GLM für Schadenhöhen (Claim Severity)  
**Sprache:** R  
**Jahr:** 2026
