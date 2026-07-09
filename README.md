# Tarifmodellierung: GLM vs. Machine Learning

**Ein End-to-End-Projekt zur aktuariellen Tarifmodellierung in der Kfz-Haftpflichtversicherung**

![R](https://img.shields.io/badge/Language-R-276DC3?style=flat-square&logo=r&logoColor=white)
![Machine Learning](https://img.shields.io/badge/Machine%20Learning-LightGBM%20%7C%20XGBoost-F7931E?style=flat-square)
![GLM](https://img.shields.io/badge/GLM-Poisson%20%7C%20Gamma-2E8B57?style=flat-square)


**Von klassischen Generalized Linear Models (GLM) zu modernen Machine-Learning-Verfahren – ein systematischer Vergleich für die Versicherungstarifierung.**

---

## Inhaltsverzeichnis

- [Projektübersicht](#projektübersicht)
- [Motivation & Hintergrund](#motivation--hintergrund)
- [Datenbasis](#datenbasis)
- [Projektworkflow](#projektworkflow)
- [Modellierungsansätze](#modellierungsansätze)
  - [Generalized Linear Models (GLM)](#generalized-linear-models-glm)
  - [Machine Learning](#machine-learning)
- [Feature Engineering](#feature-engineering)
- [Trainings- und Validierungsstrategie](#trainings--und-validierungsstrategie)
- [Evaluationsmetriken](#evaluationsmetriken)
- [Ergebnisse & Vergleich](#ergebnisse--vergleich)
- [Projektstruktur](#projektstruktur)
- [Installation & Nutzung](#installation--nutzung)
- [Reproduzierbarkeit](#reproduzierbarkeit)
- [Fazit](#fazit)

---

## Projektübersicht

Dieses Projekt implementiert eine vollständige **End-to-End-Pipeline zur aktuariellen Tarifmodellierung** in der Kraftfahrzeug-Haftpflichtversicherung.

Im Mittelpunkt steht der Vergleich zwischen klassischen statistischen Verfahren und modernen Machine-Learning-Modellen hinsichtlich:

- Prognosegüte
- Interpretierbarkeit
- regulatorischer Nachvollziehbarkeit
- praktischer Einsetzbarkeit

Die Modellierung folgt dem etablierten **Frequency-Severity-Ansatz**, bei dem die erwartete Risikoprämie in zwei Komponenten zerlegt wird:

```text
Pure Premium
      │
      ├──────────────► Claim Frequency
      │                    (Poisson)
      │
      └──────────────► Claim Severity
                           (Gamma)
```

Sowohl GLMs als auch Gradient-Boosting-Verfahren werden auf identischer Datengrundlage trainiert und anhand aktuarieller Qualitätsmetriken verglichen.

## Motivation & Hintergrund

Generalized Linear Models gelten seit Jahrzehnten als Standard in der Versicherungsmathematik.

Ihre Vorteile sind:

- hohe Interpretierbarkeit
- regulatorische Akzeptanz
- stabile Parameterschätzung
- transparente Tarifstruktur

Moderne Machine-Learning-Verfahren ermöglichen dagegen:

- nichtlineare Zusammenhänge
- automatische Interaktionseffekte
- höhere Prognosegenauigkeit
- feinere Risikosegmentierung

Dieses Projekt untersucht, **wann GLMs ausreichend sind und wann Machine Learning einen messbaren Mehrwert liefert.**

## Datenbasis

Verwendet wird der bekannte **French Motor Third-Party Liability (freMTPL2)** Benchmark-Datensatz.

### Enthaltene Informationen

| Kategorie | Beispiele                          |
| --------- | ---------------------------------- |
| Fahrzeug  | Leistung, Alter, Marke, Kraftstoff |
| Fahrer    | Alter, Bonus-Malus                 |
| Region    | Region, Urbanisierungsgrad         |
| Exposure  | Versicherungsdauer                 |
| Schäden   | Schadenanzahl und Schadenhöhe      |

### Datenaufbereitung

- Aggregation der Schadenfälle
- Zusammenführung von Frequency- und Severity-Daten
- Behandlung fehlender Werte
- Entfernung extremer Beobachtungen
- Exposure-Zensierung auf maximal ein Versicherungsjahr
- Faktorisierung kategorialer Variablen
- numerische Stabilisierung

## Projektworkflow

```text
                     Raw Insurance Data
                             │
                             ▼
                  Explorative Datenanalyse
                             │
                             ▼
                     Datenaufbereitung
                             │
          ┌──────────────────┴──────────────────┐
          ▼                                     ▼
     Frequency Model                     Severity Model
          ▼                                     ▼
     Poisson GLM                       Gamma GLM
          ▼                                     ▼
     LightGBM / XGBoost              LightGBM / XGBoost
          ▼                                     ▼
          └───────────────┬─────────────────────┘
                          ▼
                  SHAP Explainability
                          ▼
               Modellvergleich & Evaluation
```

## Modellierungsansätze

### Generalized Linear Models (GLM)

#### Frequenzmodell

- Poisson GLM
- Log-Link
- Exposure als Offset

```text
log(μ) = Xβ + log(Exposure)
```

#### Severity-Modell

- Gamma GLM
- Log-Link
- Maximum Likelihood

Zusätzlich wurde ein **Inverse Gaussian GLM** als Konkurrenzmodell untersucht.

#### Vorteile
 
- ✓ Interpretierbar
- ✓ Regulatorisch etabliert
- ✓ Robuste Parameterschätzung

### Machine Learning

Implementierte Modelle:

| Modell                     | Ziel                 |
| -------------------------- | -------------------- |
| Random Forest *(optional)* | Benchmark            |
| LightGBM                   | Frequency & Severity |
| XGBoost                    | Frequency & Severity |

Eigenschaften:

- Gradient Boosting
- nichtlineare Effekte
- Interaktionen
- Bayes'sche Hyperparameteroptimierung
- Early Stopping

## Feature Engineering

Folgende Transformationen wurden eingesetzt:

| Feature               | Transformation     |
| --------------------- | ------------------ |
| Density               | log(1 + Density)   |
| BonusMalus            | quadratischer Term |
| Region                | Label Encoding     |
| Vehicle Brand         | Label Encoding     |
| kategoriale Variablen | Encoding           |
| Exposure              | Offset             |

Ziel:

- Reduktion von Schiefe
- numerische Stabilität
- bessere Generalisierung

## Trainings- und Validierungsstrategie

### Cross Validation

- 5-Fold Cross Validation

### Hyperparameteroptimierung

Optuna mit Bayes'scher Optimierung.

Optimiert wurden u. a.:

- `learning_rate`
- `max_depth`
- `num_leaves`
- `reg_alpha`
- `reg_lambda`

Zusätzlich:

- Early Stopping
- robuste Modellvalidierung
- Vergleich identischer Daten-Splits

## Evaluationsmetriken

| Kategorie       | Kennzahl             |
| --------------- | -------------------- |
| Frequenz        | Poisson Deviance     |
| Severity        | Gamma Deviance       |
| Diskriminierung | Gini-Koeffizient     |
| Segmentierung   | Lift Charts          |
| Kalibrierung    | Calibration Curves   |
| Vergleich       | Diebold-Mariano-Test |
| Robustheit      | Bootstrap            |

## Ergebnisse & Vergleich

### Vergleich

| Kriterium                  | GLM       | Machine Learning |
| -------------------------- | --------- | ---------------- |
| Interpretierbarkeit        | ★★★★★   | ★★★☆☆              |
| Prognosegüte               | ★★★☆☆   | ★★★★★            |
| Nichtlinearität            | begrenzt  | hervorragend     |
| Interaktionen              | manuell   | automatisch      |
| Rechenzeit                 | gering    | höher            |
| Regulatorische Transparenz | sehr hoch | hoch (mit SHAP)  |

### Kernerkenntnisse

#### GLM

- hervorragende Interpretierbarkeit
- stabil
- regulatorischer Standard

#### Machine Learning

- niedrigere Deviance
- höhere Gini-Werte
- bessere Segmentierung
- stärkere Modellflexibilität

#### Explainability

Zur Interpretation komplexer Modelle wurden SHAP-Werte eingesetzt.

Untersucht wurden:

- globale Feature Importance
- lokale Erklärungen
- Beeswarm Plots
- Waterfall Plots
- Vergleich mit GLM-Koeffizienten

## Projektstruktur

```text
Tarifmodellierung-GLM-vs-ML/
│
├── data/
│   ├── raw/
│   └── processed/
│
├── phase_1/
│    ├── exposure_analysis.r
│    ├── exposure_report.pdf
│    └── phase_1_Exposure_Analyse.md
│
├── phase_2/
│    ├── gamma_glm.r
│    ├── gamma_glm_report.pdf
│    ├── glm_analysis.r
│    ├── glm_analysis_python.py
│    ├── glm_phase_2_report.pdf
│    ├── python_offset_demo.py
│    └── phase_2_Gamma_GLM_Schadenhöhe.md
│
├── phase_3/
│    ├── phase3_ml_modeling.py
│    └── phase3_ml_modeling.md
│
├── phase_4/
│   ├── plots/
│   ├── phase_4_shap_analysis.py
│   └── phase_4_SHAP_analysis.md
│
├── phase_5/
│   ├── plots/
│   ├── actuarial_model_comparison.py
│   └── performanzvergleich_abschlussbericht.md
│
├── SAS/
│   ├── phase_1/
│   ├── phase_2/
│   ├── phase_3/
│   ├── phase_4/
│   ├── phase_5/
│
├── technical_paper/
│
└── README.md
```

## Installation & Nutzung

### Repository klonen

```bash
git clone https://github.com/username/tarifmodellierung-glm-vs-ml.git
cd tarifmodellierung-glm-vs-ml
```

### Abhängigkeiten installieren

```r
install.packages(c(
  "tidyverse",
  "data.table",
  "MASS",
  "xgboost",
  "lightgbm",
  "caret",
  "optuna",
  "SHAPforxgboost"
))
```


## Reproduzierbarkeit

Das Projekt wurde mit Fokus auf wissenschaftliche Reproduzierbarkeit entwickelt.

### Gewährleistet durch

- feste Zufallsseeds
- dokumentierte Datenaufbereitung
- klar getrennte Projektphasen
- reproduzierbare Cross Validation
- versionierte Modellparameter
- identische Evaluationsmetriken

## Fazit

Dieses Projekt zeigt, dass klassische GLMs und moderne Machine-Learning-Verfahren keine konkurrierenden, sondern **komplementäre Ansätze** darstellen.

**GLMs** überzeugen durch Transparenz, Stabilität und regulatorische Akzeptanz.

**Gradient Boosting** erzielt die höhere Vorhersagegenauigkeit und bildet komplexe Risikostrukturen deutlich besser ab.

Durch den Einsatz von **SHAP** lassen sich moderne Machine-Learning-Modelle nachvollziehbar interpretieren und damit auch im regulierten Versicherungsumfeld sinnvoll einsetzen.

> [!IMPORTANT]
> **Kernaussage:** **Die Zukunft der aktuariellen Tarifmodellierung liegt nicht im Ersatz klassischer GLMs durch Machine Learning, sondern in der intelligenten Kombination beider Ansätze.**


---

**⭐ Wenn Ihnen dieses Projekt gefällt, freue wir uns über einen Star auf GitHub.**
