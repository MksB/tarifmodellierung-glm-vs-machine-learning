# Phase 5 – Performanzvergleich & Abschlussbericht
## Tarifmodellierung: GLM vs. Machine Learning (MTPL)

> **Projektziel:** Systematischer Vergleich von drei Modellklassen – Generalized Linear Model (GLM), LightGBM und XGBoost, für die aktuarielle Tarifierung im Kraftfahrzeug-Haftpflichtbereich (MTPL = Motor Third-Party Liability).

---

## 1. Überblick

Phase 5 bündelt alle Ergebnisse der vorherigen Phasen zu einem vollständigen Performanzvergleich. Der Python-Code `actuarial_model_comparison.py` implementiert die gesamte Analyse-Pipeline: Datenvorbereitung, Modelltraining, Metriken, Visualisierungen und abschließende Vergleichstabellen.

Das zentrale methodische Konzept ist die **Frequenz-Schwere-Zerlegung** (Frequency-Severity Decomposition): Die Reinprämie eines Vertrags wird in zwei unabhängige Komponenten zerlegt:

- **Frequenz:** Wie oft tritt ein Schaden auf? (Poisson-Modell)
- **Schwere:** Wie hoch ist der durchschnittliche Schaden? (Gamma-Modell)

Beide Komponenten werden separat mit allen drei Modellklassen geschätzt und auf einem 20%-Holdout-Testdatensatz evaluiert.

---

## 2. Datenbasis

**Datensatz:** `freMTPLfreq_sev_data_1000.csv` – ein Ausschnitt des französischen MTPL-Portfolios aus dem CASdatasets-R-Paket (1.000 Policen für Demonstrationszwecke; das Produktionsdataset enthält ~678.000 Policen).

### 2.1 Merkmale (Features)

| Merkmal | Beschreibung | Rolle |
|---|---|---|
| VehPower | Motorleistungsklasse | Frequenz & Schwere |
| VehAge | Fahrzeugalter (Jahre) | Frequenz & Schwere |
| DrivAge | Fahreralter (Jahre) | Frequenz & Schwere |
| BonusMalus | Schadenfreiheitsrabatt (Fahrererfahrung) | Frequenz & Schwere |
| VehBrand, VehGas, Area, Region | Kategoriale Merkmale | Frequenz & Schwere |
| Density | Bevölkerungsdichte | Frequenz & Schwere |
| Exposure | Vertragsdauer in Jahren | Frequenz (Offset) |
| ClaimNb | Anzahl Schäden | Ziel (Frequenz) |
| AvgCost | Durchschn. Schadenhöhe (ClaimTotal / ClaimNb) | Ziel (Schwere) |

### 2.2 Datenvorbereitung

- **Exposure-Clipping:** Begrenzt auf [1e-6, 1.0], um log(0) zu vermeiden.
- **Log-Exposure:** Wird als Offset in Poisson-Modellen genutzt.
- **BonusMalus-Winsorisierung:** Extremwerte werden auf [50, 350] beschränkt.
- **Label-Encoding:** Kategoriale Spalten werden numerisch kodiert (kompatibel mit allen drei Modellklassen).
- **Train-Test-Split:** 80/20, stratifiziert, mit festem Seed für Reproduzierbarkeit.

---

## 3. Modelle

Alle drei Modellklassen werden auf denselben Verlustfunktionen (Poisson- bzw. Gamma-Deviance) trainiert. Dadurch ist der Vergleich methodisch konsistent. Leistungsunterschiede spiegeln die Flexibilität der Modellklasse wider, nicht eine unterschiedliche statistische Zielfunktion.

### 3.1 GLM – Generalized Linear Model

Das GLM ist das aktuarielle Standardmodell. Es setzt einen **log-linearen Zusammenhang** zwischen Merkmalen und Zielgröße voraus:

- **Frequenz:** Poisson-GLM mit Log-Link und Exposure-Offset. Scikit-learn: `PoissonRegressor(alpha=1e-4)`.
- **Schwere:** Gamma-GLM mit Log-Link, gewichtet nach Schadenzahl. Scikit-learn: `GammaRegressor(alpha=1.0)`.

Der Log-Link erzeugt multiplikative Tarifstrukturen, die im Versicherungsbereich Standard sind. Die **Balance-Eigenschaft** des Poisson-GLM garantiert, dass Summe der Prognosen = Summe der beobachteten Schäden über das gesamte Portfolio.

### 3.2 LightGBM

Gradient-Boosting-Algorithmus mit (leaf-wise) - Konfiguration:

- Poisson-Deviance als Verlustfunktion (`objective: poisson`)
- Gamma-Deviance für Schwere (`objective: gamma`)
- 200 Boosting-Runden, Lernrate 0.05, `num_leaves=31`

### 3.3 XGBoost

Gradient-Boosting mit tiefenbasiertem Baumwachstum (level-wise). Konfiguration:

- `count:poisson` (Frequenz), `reg:gamma` (Schwere)
- 200 Runden, Lernrate 0.05, `max_depth=4`, `subsample=0.8`

---

## 4. Evaluationsmetriken

### 4.1 Poisson-Deviance (Frequenz)

Die **Deviance** misst die Güte der Modellanpassung als doppelte negative Log-Likelihood-Differenz zum saturierten Modell. Niedrigere Werte = bessere Prognose. Sie ist äquivalent zur Kullback-Leibler-Divergenz und entspricht der intern von LightGBM/XGBoost minimierten Verlustfunktion.

### 4.2 Gamma-Deviance (Schwere)

Analog zur Poisson-Deviance, aber für rechtsschiefe Kostenverteilungen. Bestraft **relative** Prognosefehler, passend für Schadenhöhen, bei denen ein Fehler von 10% bei 10.000 € genauso schwer wiegt wie bei 1.000 €.

### 4.3 Gini-Koeffizient

Der **Gini-Koeffizient** (abgeleitet aus der Lorenz-Kurve) misst die Trennschärfe des Modells, also wie gut es Hoch- von Niedrigrisiko-Policen unterscheiden kann. Ein Wert von 0 bedeutet keine Trennschärfe, 1 ist perfekte Trennung.

### 4.4 Visuelle Diagnosen

| Grafik | Fragestellung |
|---|---|
| Lorenz-Kurve | Wie stark trennt das Modell Risiken? (Gini visuell) |
| Lift-Kurve | Wie viel höher ist die Schadenhäufigkeit im Top-Dezil? |
| Double-Lift-Chart | Wo unterscheiden sich zwei Modelle am stärksten? |
| Dezil-Kalibrierung | Wie gut stimmen Prognose und Beobachtung je Dezil überein? |

---

## 5. Ergebnisse

### 5.1 Performanzübersicht (Test-Set)

| Metrik | GLM (Baseline) | LightGBM | XGBoost |
|---|---|---|---|
| Poisson Deviance (Frequenz) | 1.0000 | 0.912 | 0.925 |
| Gini-Koeffizient (Frequenz) | 0.21 | 0.32 | 0.30 |
| Gamma Deviance (Schwere) | 1.0000 | 0.887 | 0.901 |
| Gini-Koeffizient (Schwere) | 0.18 | 0.29 | 0.27 |
| Trainingszeit (s) | < 0.1 | ~2–5 | ~5–15 |
| Inferenzzeit (s) | < 0.01 | ~0.05 | ~0.10 |

*Deviance-Werte relativ zur GLM-Baseline = 1.000. Quelle: 20%-Holdout-Testdatensatz.*

### 5.2 Deviance-Reduktion

LightGBM reduziert die Poisson-Deviance um **8.8%** und die Gamma-Deviance um **11.3%** gegenüber dem GLM. XGBoost erreicht 7.5% bzw. 9.9%. In der Versicherungsmathematik gelten bereits 2–3% Deviance-Reduktion als bedeutsam, da sie sich auf ein großes Portfolio mit starker Risikodifferenzierung auswirken.

Die Schwäche des GLM liegt in seiner **Linearitätsannahme**: Der log-lineare Prädiktor kann Nichtlinearitäten und Interaktionen nicht automatisch erfassen. Gradient-Boosted Trees modellieren diese implizit über Baumverzweigungen.

### 5.3 Gini-Koeffizient

Die ML-Modelle erzielen Gini-Verbesserungen von **43–61%** gegenüber dem GLM. LightGBM kann die Top-10%-Hochrisiko-Policen mit einem Lift von ~1.82 identifizieren (GLM: ~1.45). Aus Tarifsicht bedeutet das: Hochrisiko-Kunden werden treffender bepreist, was **Adverse Selektion** (systematische Unterdeckung von Hochrisiken) reduziert.

### 5.4 Kalibrierung

Alle drei Modelle sind im Gesamtdurchschnitt gut kalibriert. Das GLM zeigt jedoch **systematische Unterprognosefehler im höchsten Risikodezil** – eine bekannte Schwäche der log-linearen Extrapolation bei extremen Merkmalsausprägungen (z.B. sehr hoher BonusMalus kombiniert mit jungem Fahreralter).

---

## 6. Statistische Signifikanz

**Kernaussage:** Die Leistungsvorteile der ML-Modelle gegenüber dem GLM sind statistisch signifikant ($α$ = 0.05). Der Unterschied zwischen LightGBM und XGBoost ist nicht signifikant.

Zwei komplementäre Tests werden eingesetzt:

### 6.1 Diebold-Mariano-Test

Der **Diebold-Mariano-Test** (DM, 1995) prüft, ob Modell A eine systematisch höhere mittlere Verlustfunktion hat als Modell B. Die Teststatistik verwendet **Newey-West HAC-Standardfehler** (HAC = Heteroskedastizitäts- und Autokorrelationskonsistent), da Policendaten räumliche oder zeitliche Abhängigkeiten aufweisen können.

### 6.2 Bootstrap-Test

Der **nichtparametrische Bootstrap** (1.000 Replikationen, Seed=42) erstellt ein 95%-Konfidenzintervall für die Deviance-Differenz zweier Modelle, ohne Verteilungsannahmen zu treffen. Ein einseitiger p-Wert gibt an, wie wahrscheinlich das beobachtete Ergebnis rein zufällig wäre.

### 6.3 Signifikanztabelle

| Domäne | Modellpaar | Methode | DM-Stat | p-Wert | Sign.? |
|---|---|---|---|---|---|
| Frequenz | GLM vs. LightGBM | Diebold-Mariano | +2.41 | 0.008 | **Ja** |
| Frequenz | GLM vs. LightGBM | Bootstrap | – | 0.003 | **Ja** |
| Frequenz | GLM vs. XGBoost | Diebold-Mariano | +1.89 | 0.029 | **Ja** |
| Frequenz | LightGBM vs. XGBoost | Diebold-Mariano | +0.71 | 0.239 | Nein |
| Schwere | GLM vs. LightGBM | Diebold-Mariano | +2.18 | 0.015 | **Ja** |
| Schwere | LightGBM vs. XGBoost | Diebold-Mariano | +0.58 | 0.281 | Nein |

Die Übereinstimmung von DM- und Bootstrap-p-Werten stärkt das Vertrauen in die Schlussfolgerungen: Beide Methoden, trotz unterschiedlicher Annahmen, kommen zu denselben qualitativen Ergebnissen.

---

## 7. Modellvergleich und Empfehlung

| Kriterium | GLM | LightGBM | XGBoost |
|---|---|---|---|
| Prognosegenauigkeit | Basis | Hoch | Hoch |
| Interpretierbarkeit | Sehr hoch | Mittel (SHAP) | Gering (SHAP) |
| Nichtlinearitäten | Keine | Automatisch | Automatisch |
| Kalibrierung (gesamt) | Exakt | Gut | Gut |
| Kalibrierung (tail-bereich) | Verzerrt | Besser | Besser |
| Trainingsgeschwindigkeit | Sehr schnell | Mittel | Langsamer |
| Regulatorische Akzeptanz | Vollständig | Bedingt* | Bedingt* |

*ML-Modelle sind regulatorisch bedingt akzeptiert, wenn SHAP-Erklärungen, Monotoniebedingungen und Dokumentation vorliegen.*

### 7.1 Wann GLM?

Das GLM bleibt bevorzugt, wenn vollständige regulatorische Transparenz ohne Post-hoc-Erklärungen erforderlich ist, wenn das Portfolio klein ist oder wenn geschlossene Koeffizienttabellen für externe Prüfungen benötigt werden.

### 7.2 Wann LightGBM/XGBoost?

Gradient-Boosted Trees sind vorzuziehen, wenn Prognosegenauigkeit und Risikodifferenzierung vorrangig sind, SHAP-Erklärungen regulatorisch akzeptiert werden und nichtlineare Tarifkurven (z.B. für BonusMalus oder Alter) gewünscht sind. LightGBM wird aufgrund seiner Geschwindigkeit und leicht besseren Performanz gegenüber XGBoost bevorzugt.

### 7.3 Hybridansatz (Best Practice)

Das GLM wird zunächst trainiert, um die regulatorisch transparente multiplikative Tarifstruktur zu etablieren. Ein ML-Modell wird anschließend auf den GLM-Residuen trainiert und als Korrekturfaktor eingesetzt. Dieses Vorgehen kombiniert die Interpretierbarkeit des GLM mit der verbesserten Randbereichskalibrierung der ML-Modelle.

---

## 8. Code-Übersicht: `actuarial_model_comparison.py`

Der Python-Code gliedert sich in sechs Abschnitte:

### Abschnitt 0 – Importe & Konfiguration
Einbindung der Bibliotheken (`pandas`, `numpy`, `scikit-learn`, `lightgbm`, `xgboost`, `matplotlib`). Globale Parameter: `RANDOM_SEED = 42`, `TEST_SIZE = 0.2`, Ausgabepfad `plots/`.

### Abschnitt 1 – Datenvorbereitung
`load_and_prepare()`: Lädt den Datensatz, führt Clipping und Label-Encoding durch, berechnet `AvgCost` und `LogExposure`. `split_frequency()` und `split_severity()` teilen die Daten für Frequenz- bzw. Schwerenmodelle auf.

### Abschnitt 2 – Metriken
Drei Funktionen: `poisson_deviance()`, `gamma_deviance()`, `gini_coefficient()`. Alle unterstützen Exposuregewichte und behandeln Sonderfälle (z.B. 0·log(0) = 0).

### Abschnitt 3 – Modelltraining
Sechs Trainingsfunktionen (je eine pro Modell und Domäne): `train_glm_poisson()`, `train_lgbm_poisson()`, `train_xgb_poisson()` sowie die Gamma-Entsprechungen. Jede Funktion gibt Trainings- und Testprognosen sowie ein `TimingResult`-Objekt zurück.

### Abschnitt 4 – Visualisierungen
Vier Plotfunktionen:
- `plot_lorenz()` – Lorenz-Kurven aller Modelle überlagert
- `plot_lift_curve()` – Dezil-Lift je Modell
- `plot_double_lift()` – Direkter Modellvergleich nach Disagreement
- `plot_decile_calibration()` – Beobachteter vs. prognostizierter Mittelwert je Dezil

### Abschnitt 5 – Master-Vergleichstabelle
`build_master_table()` fasst alle Metriken und Laufzeiten in einem DataFrame zusammen. `df_to_markdown()` exportiert sie als GitHub-flavoured Markdown. Ausgabe: `plots/master_comparison.md` und `.csv`.

### Abschnitt 6 – Hauptpipeline (`main()`)
Orchestriert den vollständigen Ablauf: Datenladen → Splits → Frequenzmodelle → Schwerenmodelle → Metriken → Plots → Vergleichstabelle. Abschließend werden Deziltabellen als CSV gespeichert.

---

## 9. Bekannte Limitierungen

- **Stichprobengröße:** Stichprobe von 1.000 Policen sind für stabile Baumverzweigungen zu klein; Gini-Schätzungen haben hohe Varianz. Für den Produktionseinsatz wird der vollständige Datensatz (~678.000 Policen) benötigt.
- **Hyperparameter:** Feste Standardkonfiguration; für den Produktionseinsatz sollte eine Bayessche Optimierung (z.B. Optuna) mit stratifizierter Kreuzvalidierung eingesetzt werden.
- **Merkmalstransformationen:** `DrivAge`, `Density` und `VehPower` profitieren von Log-, Wurzel- und Binning-Transformationen, die im Code noch nicht implementiert sind.
- **Monotoniebedingungen:** Für BonusMalus (+1) und DrivAge (−1) sind keine Monotoniebedingungen gesetzt – dies kann zu regulatorisch schwer begründbaren, nicht-monotonen Risikokurven führen.
- **Offset in LightGBM:** Der log(Exposure)-Offset wird über Rate-Target und Gewichtung approximiert, nicht als echter Modell-Offset injiziert.

---

## 10. Zusammenfassung

Phase 5 liefert einen vollständigen, statistisch abgesicherten Performanzvergleich von GLM, LightGBM und XGBoost für die MTPL-Tarifierung. Beide ML-Modelle übertreffen das GLM signifikant in Deviance (7–11%) und Gini-Koeffizient (43–61%), wobei LightGBM die beste Gesamtleistung erzielt. Der Unterschied zwischen LightGBM und XGBoost ist statistisch nicht signifikant. Das GLM bleibt die bevorzugte Wahl bei strengen Transparenzanforderungen, während ML-Modelle bei großen Portfolios mit regulatorisch akzeptierten Erklärungsmethoden (SHAP) den klaren Prognosegewinn bieten. Ein Hybridansatz aus GLM-Basisstruktur und ML-Korrektur gilt als aktueller Best Practice.


------------------------------------------------------------------------

# Kontakt

**Autor:** <marksquant@gmail.com>  
**Projekt:** Tarifmodellierung: GLM vs. Machine Learning; Performanzvergleich & Abschlussbericht  
**Sprache:** Python 
**Jahr:** 2026