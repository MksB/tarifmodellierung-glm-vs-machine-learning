####
# Data cleaning applied to the French MTPL data set...
#
# 
# 

# Notwendige Bibliotheken (falls noch nicht installiert: install.packages("CASdatasets"))
library(dplyr)

# 1. Daten laden

load("freMTPL2freq.rda")
load("freMTPL2sev.rda")


# 2. Severity-Daten aufbereiten (Aggregieren nach IDpol)
# Wir berechnen die Summe der Schadenzahlungen und die Anzahl der Ansprüche pro Police
# 
# Paket dplyr erledigt n() count...
# 
sev_clean <- freMTPL2sev %>%
  group_by(IDpol) %>%
  summarise(
    ClaimTotal = sum(ClaimAmount, na.rm = TRUE),
    ClaimNb_Check = n(), 
    .groups = "drop"
  )

# 3. Frequency-Daten aufbereiten und Mergen
# durch left_join() und gezielte Filterung bleibt der Speicherbedarf...
# ...geringer als bei mehrfachen Zwischenkopien
#
# Sicheres Handling von NAs: coalesce(ClaimTotal, 0) ersetzt NAs nur in der...
# ...spezifischen Spalte.
dat <- freMTPL2freq %>%
  # Spalte 2 (ClaimNb) entfernen, da wir die Info oft aus den Sev-Daten validieren 
  # oder neu berechnen wollen (entspricht deinem [,-2])
  select(-ClaimNb) %>%
  # Zusammenführen mit den aggregierten Severity-Daten
  left_join(sev_clean, by = "IDpol") %>%
  # NAs in ClaimTotal durch 0 ersetzen (nur dort, nicht im gesamten Datensatz!)
  mutate(ClaimTotal = coalesce(ClaimTotal, 0)) %>%
  # Filter: Nur Policen mit maximal 5 Ansprüchen (nutzt hier die Original-ClaimNb falls gewünscht)
  # Falls du die ClaimNb aus freMTPL2freq meinst, behalte sie oben im select.
  filter(freMTPL2freq$ClaimNb <= 5) %>%
  # Exposure auf maximal 1 deckeln
  mutate(Exposure = pmin(Exposure, 1)) %>%
  # Faktoren definieren
  mutate(
    VehGas = factor(VehGas),
    VehBrand = factor(VehBrand, levels = c("B1","B2","B3","B4","B5","B6","B10","B11","B12","B13","B14"))
  )

# 4. Severity-Tabelle filtern, sodass nur noch IDs vorhanden sind, die in 'dat' vorkommen
sev <- freMTPL2sev %>%
  filter(IDpol %in% dat$IDpol) %>%
  select(IDpol, ClaimAmount)

# Ergebnis prüfen
head(dat)

################
################

# 1. Severity-Daten aggregieren (Summe Betrag UND Anzahl der Zeilen = Claims)
sev_clean <- freMTPL2sev %>%
  group_by(IDpol) %>%
  summarise(
    ClaimTotal = sum(ClaimAmount, na.rm = TRUE),
    # Hier erzeugen wir die Anzahl der Ansprüche pro IDpol
    ClaimNb = as.numeric(n()), 
    .groups = "drop"
  )

# 2. In den Hauptdatensatz integrieren
dat <- freMTPL2freq %>%
  select(-ClaimNb) %>% # Alte Spalte entfernen, falls vorhanden
  left_join(sev_clean, by = "IDpol") %>%
  mutate(
    # Falls kein Join-Partner in sev gefunden wurde, ist ClaimNb = 0 und ClaimTotal = 0
    ClaimNb = coalesce(ClaimNb, 0),
    ClaimTotal = coalesce(ClaimTotal, 0)
  ) %>%
  # Filter und Transformationen wie gehabt
  filter(ClaimNb <= 5) %>%
  mutate(
    Exposure = pmin(Exposure, 1),
    VehGas = factor(VehGas),
    VehBrand = factor(VehBrand, levels = c("B1","B2","B3","B4","B5","B6","B10","B11","B12","B13","B14"))
  )

# Struktur prüfen
str(dat)

write.csv(dat, "data_clean_sev_freq_agg.csv", row.names = TRUE)
