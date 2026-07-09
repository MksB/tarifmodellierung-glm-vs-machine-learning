Exposure Analysis – freMTPL Dataset
================

## Übersicht

Dieses Dokument erläutert den Aufbau, den Zweck und die Methodik von
`exposure_analysis.R`, einem Diagnoseskript für den Datensatz **„French
Motor Third-Party (`freMTPL`). Das Skript führt eine eingehende Analyse
der Variablen `Exposure` durch und konstruiert den Term
`offset(log(Exposure))`, der *zwingend erforderlich* ist in jedem
auf Poisson-GLM basierenden Schadenhäufigkeitsmodell.

> **Repository context:** Die gesamte Analyse-Pipeline wird durch das
> Einlesen von `exposure_analysis.R`. 


------------------------------------------------------------------------

## 1. Hintergrund: Was ist `Exposure`?

In der französischen Kfz-Haftpflichtversicherung deckt jeder
Versicherungsdatensatz einen **Teil eines Kalenderjahres** (eine
Abrechnungsperiode) ab. Die Variable `Exposure` gibt an, wie viele
**Versicherungsjahre** an Risiko ein einzelner Datensatz repräsentiert.

| Scenario                        | Exposure |
|---------------------------------|----------|
| Policy aktiv für das ganze Jahr | 1.00     |
| Policy aktiv für 6 Monate       | 0.50     |
| Policy aktiv für 1 Monat        | ≈ 0.083  |

Nach dem Bereinigungsschritt wird `Exposure` mittels
`pmin(Exposure, 1.0)` **auf 1 begrenzt**.

------------------------------------------------------------------------

## 2. Warum `offset(log(Exposure))` zwingend erforderlich ist

Ein Poisson-GLM modelliert die **erwartete Anzahl von Schadensfällen**:

$$E[\text{ClaimNb}] = \lambda \cdot \text{Exposure}$$

wobei $\lambda$ die latente **jährliche** Schadenquote ist. Unter
Verwendung der Log-Link(Verbindung):

$$\log E[\text{ClaimNb}] = \underbrace{\log(\lambda)}_{\text{linear predictor } X\beta} + \underbrace{\log(\text{Exposure})}_{\text{offset (coefficient fixed at 1)}}$$

Der Term $\log(\text{Exposure})$ wird als **Offset** einbezogen (eine
Kovariate) deren Regressionskoeffizient genau auf 1 festgelegt ist.
Dadurch wird sichergestellt, dass das Modell *Schadenraten* schätzt und nicht
die Rohzahlen.

> *Hinweis:* **Ohne den Versatz** wird eine seit einem Monat aktive
> Police genauso behandelt wie eine seit zwölf Monaten aktive, dabei ist
> jeder geschätzte Koeffizient stark verzerrt.

------------------------------------------------------------------------

## 3. Script Struktur

Das Skript ist in **8 logische Abschnitte** unterteilt:

| Abschnitt | Inhalt                                                        |
|-----------|---------------------------------------------------------------|
| 0         | Laden der Pakete (`ggplot2`, `gridExtra`, `scales`)           |
| 1         | Konfiguration (Dateipfade, gemeinsames Thema, Farbpalette)    |
| 2         | Datenaufbereitung (`prepare_data()`)                          |
| 3         | Genauigkeit der Expositionserfassung (`classify_precision()`) |
| 4         | Plottfunktionen (10 diagnostische Plots)                      |
| 5         | Offset-Erstellung und -Validierung (`build_offset()`)         |
| 6         | Hauptablauf (`run_exposure_analysis()`)                       |
| 7         | Einstiegspunkt für die Skriptausführung                       |
| 8         | Kurzanleitung zur Offset-Verwendung (Konsolenausgabe)         |

------------------------------------------------------------------------

## 4. Datenaufbereitung

### 4.1 Quelldateien

``` r
FREQ_CSV <- "freMTPLfreq.csv"   # Häufigkeitsdaten auf Policeebene
SEV_CSV  <- "freMTPLsev.csv"    # Schweregraddaten auf Schadenebene
```

### 4.2 `prepare_data()`

Die Funktion führt die Tabellen zu Häufigkeit und Schweregrad zusammen,
wendet Bereinigungsregeln an und kodiert die Faktorvariablen:

``` r
prepare_data <- function(freq_csv, sev_csv) {
  # 1. Roh-CSV-Dateien einlesen
  # 2. Schweregrad nach Police aggregieren (ClaimTotal, ClaimNb)
  # 3. Left-Join mit der Häufigkeitstabelle durchführen
  # 4. NA-Werte mit 0 füllen (Policen ohne Schadenfälle)
  # 5. Datensätze mit ClaimNb > 5 entfernen  (Datenqualitätsfilter)
  # 6. Exposure auf 1 zensieren: pmin(Exposure, 1.0)
  # 7. VehBrand, VehGas, Area, Region als geordnete Faktoren kodieren
}
```

**Wichtige Entscheidung zur Bereinigung – Zensur bei 1:**

``` r
dat$Exposure <- pmin(dat$Exposure, 1.0)
```

Dadurch werden die wenigen mehrjährigen Datenartefakte beseitigt, die
bei der Datenextraktion entstehen können.

------------------------------------------------------------------------

## 5. Aufzeichnungsgenauigkeit

### 5.1 `classify_precision()`

In den Rohdaten sind drei Aufzeichnungssysteme nebeneinander vorhanden:

| Kategorie | Beschreibung | Kriterium |
|----|----|----|
| **Ganzes Jahr** | Zensiert / tatsächlich jährlich | `e == 1,0` |
| **Tagesanteil** | Ganzzahlige Vielfache von 1/365 | `e × 365 ≈ Ganzzahl (Integer)` |
| **Monatsanteil** | Ganzzahlige Vielfache von 1/12 | `e × 12 ≈ Ganzzahl (Integer)` |
| **Dezimal (2 Stellen)** | Auf 2 Dezimalstellen gerundet | catch-all |

``` r
classify_precision <- function(e) {
  is_daily   <- abs(e * 365 - round(e * 365)) < 1e-4  & e < 1
  is_monthly <- abs(e * 12  - round(e * 12))  < 1e-4  & e < 1
  is_full    <- e == 1.0
  ...
}
```

> Das Aufzeichnungssystem hat **keinen** Einfluss auf die Gültigkeit von
> `log(Exposure)`, aber das Verständnis der Genauigkeit ist für die
> Reproduzierbarkeit und zu Prüfungszwecken wichtig.

------------------------------------------------------------------------

## 6. Diagnosediagramme (Teil 4)

Das Skript erzeugt **13 Seiten** Diagnosedaten in der Datei
`exposure_report.pdf`. Hier eine Übersicht über die einzelnen Diagramme
und ihren Zweck:

### 6.1 Konzeptdiagramm (`plot_concept`)

Eine Zeitleiste im Gantt-Stil, die vier Beispielpolicen innerhalb eines
Kalenderjahres zeigt. Veranschaulicht, wie `Exposure` dem aktiven
Zeitraum jeder Police zugeordnet wird. Verwendet `geom_rect()` mit einem
blauen Farbverlauf, der auf `Exposure` skaliert ist.

### 6.2 Expositionshistogramm (`plot_hist`)

Ein in Klassen unterteiltes Histogramm (`binwidth = 0,02`), eingefärbt
nach Erfassungsgenauigkeit (siehe Abschnitt 5). Eine rote gestrichelte
vertikale Linie markiert den Zensierungspunkt bei `Exposure = 1,0`.

Zusammenfassende Statistiken werden im Untertitel angezeigt: `n`,
`mean`, `median`, `sd` und die Gesamtsumme `sum` (Versicherungsjahre).

### 6.3 Empirische CDF (`plot_ecdf`)

Die empirische kumulative Verteilungsfunktion von `Exposure` mit
Quartilsmarkern (P25, P50, P75, P80). Zeigt, wie viel Prozent der
Policen Ganzjahresdaten sind.

### 6.4 Balkendiagramm zur Genauigkeit (`plot_precision`)

Ein horizontales Balkendiagramm, das die Anzahl und den prozentualen
Anteil jeder Genauigkeitskategorie zeigt. Bestätigt, dass die Mehrheit
der Werte als Zahlen mit zwei Dezimalstellen gespeichert ist.

### 6.5 Exposition nach Kovariaten – Boxplots (`plot_exp_by_covariate`)

Erstellt für `Area`, `VehGas` und `VehBrand`. Prüft, ob `Exposure` sich
systematisch mit den Bewertungsfaktoren ändert. Ist dies der Fall, führt
das Weglassen des Offsets zu einer Verwechslung zwischen den Effekten
kurzer Exposition und den Effekten der Kovariaten.

``` r
# Diamond = mean; red outliers = 1.5 × IQR rule
stat_summary(fun = mean, geom = "point", shape = 23, fill = "white")
```

### 6.6 log(Exposure) Verteilung (`plot_log_exposure`)

Zwei nebeneinander angeordnete Grafiken:

- **Links:** Histogramm von `log(Exposure)` – die tatsächlichen Werte,
  die als Offset an den GLM- Solver übergeben wurden.
- **Rechts:** Streudiagramm aller beobachteten Paare
  `(Exposure, log(Exposure))`, überlagert mit der theoretischen
  $\log$-Kurve. Mit Anmerkungen zum Kompressionseffekt, der den Offset
  numerisch stabil macht.

### 6.7 Tabelle zur Offset-Konstruktion (`plot_offset_explanation`)

Eine Schritt-für-Schritt-Referenztabelle, die mit
`gridExtra::tableGrob()` gerendert wurde und die sechs
Implementierungsschritte von der Validierung bis zur Verwendung des GLM
abdeckt.

### 6.8 Modellvergleich (`plot_offset_comparison`)

Passt zwei Poisson-GLMs an die vorbereiteten Daten an:

| Model         | Spezifikation                                     |
|---------------|---------------------------------------------------|
| **Correct**   | `ClaimNb ~ VehGas + Area + offset(log(Exposure))` |
| **Incorrect** | `ClaimNb ~ VehGas + Area`                         |

Vergleicht: 1. Angepasste **Jahresraten** (`fitted / Exposure`) über den
gesamten `Exposure`-Bereich. 2. Eine nebeneinander angeordnete
Koeffiziententabelle (`With_Offset` vs. `Without_Offset` vs.
`Difference`).

> Wenn die Stichprobe keine Schadensfälle enthält, werden rein zur
> Veranschaulichung synthetische Schadensfälle mit
> `rbinom(n, 1, pmin(Exposure * 0.07, 0.99))` eingefügt, und die Grafik
> wird deutlich als „synthetisch“ gekennzeichnet.

### 6.9 Schadensquote vs. Risikodauer (`plot_claim_rate`)

Für Policen mit mindestens einem Schaden: Zeichnet `ClaimNb / Exposure`
(logarithmische Skala) gegen `Exposure` mit einem LOESS-Glättungsfilter.
Bei einem korrekt spezifizierten Poisson- Ratenmodell sollte die
empirische Rate über den gesamten `Exposure`-Bereich hinweg annähernd
flach verlaufen.

### 6.10 Tabelle mit zusammenfassenden Statistiken (`plot_summary_table`)

Eine umfassende Statistik-Tabelle, die sowohl `Exposure` als auch
`log(Exposure)` abdeckt, einschließlich Sicherheitsprüfungen auf `-Inf`-
und `NA`-Werte in der Offset-Spalte.

------------------------------------------------------------------------

## 7. Erstellung und Validierung des Offsets

### 7.1 `build_offset()`

Dies ist die zentrale Produktionsfunktion. Sie wendet drei
Sicherheitsprüfungen an, bevor der Offset berechnet wird:

``` r
build_offset <- function(dat) {

  # Guard 1: No zero or negative Exposure
  # log(0) = -Inf breaks the GLM numerical solver
  n_zero_or_neg <- sum(dat$Exposure <= 0, na.rm = TRUE)
  if (n_zero_or_neg > 0L) stop(...)

  # Guard 2: Warn if Exposure > 1 (cleaning should have handled this)
  n_over_one <- sum(dat$Exposure > 1, na.rm = TRUE)
  if (n_over_one > 0L) warning(...)

  # Compute the offset
  dat$log_exposure <- log(dat$Exposure)

  # Guard 3: Confirm numerical safety
  stopifnot(
    "log_exposure contains NA"   = !anyNA(dat$log_exposure),
    "log_exposure contains -Inf" = !any(is.infinite(dat$log_exposure) & dat$log_exposure < 0),
    "log_exposure contains +Inf" = !any(is.infinite(dat$log_exposure) & dat$log_exposure > 0),
    "log_exposure contains NaN"  = !any(is.nan(dat$log_exposure))
  )

  dat
}
```

> Die Schutzmechanismen sorgen dafür, dass `build_offset()` sicher in
> einer Produktionspipeline aufgerufen werden kann, in der die
> Datenqualität der vorgelagerten Prozesse nicht immer gewährleistet
> werden kann.

------------------------------------------------------------------------

## 8. Ausgabe

Die Ausführung von `run_exposure_analysis()` erzeugt zwei
Ausgabedateien:

| File | Contents |
|----|----|
| `exposure_report.pdf` | 13-Seiten Diagnostik PDF (alle Grafiken) |
| `dat_with_offset.rds` | Bereinigte Data Frame inklusive `log_exposure` Spalte |

------------------------------------------------------------------------

## 9. Verwendung des Offsets in einem GLM

Nach Ausführung des Skripts ist der Offset sofort einsatzbereit:

``` r
# Load the saved data (offset column already included)
dat <- readRDS("dat_with_offset.rds")

# Option A: pre-computed column (recommended)
fit <- glm(
  ClaimNb ~ VehPower + VehAge + DrivAge + BonusMalus +
            VehBrand + VehGas + Area + Region +
            offset(log_exposure),
  family = poisson(link = "log"),
  data   = dat
)

# Option B: inline computation (equivalent)
fit <- glm(
  ClaimNb ~ VehPower + VehAge + DrivAge + BonusMalus +
            VehBrand + VehGas + Area + Region +
            offset(log(Exposure)),
  family = poisson(link = "log"),
  data   = dat
)

# Option C: Negative Binomial (overdispersion)
# library(MASS)
# fit_nb <- MASS::glm.nb(
#   ClaimNb ~ VehPower + ... + offset(log_exposure),
#   data = dat
# )
```

**Was der Offset bewirkt:**

| Modell | Mittelstruktur | Interpretation von $e^{\hat\beta_j}$ |
|----|----|----|
| Ohne Offset | $E[N] = e^{X\beta}$ | Auswirkung auf die rohe **Anzahl** (verzerrt) |
| Mit Offset | $E[N] = e^{X\beta} \cdot \text{Exposition}$ | Auswirkung auf die jährliche **Rate** (korrekt) |

------------------------------------------------------------------------

## 10. Dependencies

``` r
install.packages(c("ggplot2", "gridExtra", "scales"))
```

| Package     | Version | Role                               |
|-------------|---------|------------------------------------|
| `ggplot2`   | ≥ 3.4   | Alle plots                         |
| `gridExtra` | ≥ 2.3   | Multi-panel layout, `tableGrob`    |
| `scales`    | ≥ 1.2   | Axis formatting (`percent_format`) |

R ≥ 4.1 is required.

------------------------------------------------------------------------

# Kontakt

**Autor:** <marksquant@gmail.com>  
**Projekt:** Tarifmodellierung: GLM vs. Machine Learning; Exposure Analysis – freMTPL Dataset    
**Sprache:** R  
**Jahr:** 2026
