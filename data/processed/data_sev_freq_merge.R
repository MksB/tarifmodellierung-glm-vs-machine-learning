library(dplyr)

load("freMTPL2freq.rda")
load("freMTPL2sev.rda")


# Aggregation der Severity
# Verdichtung die Schadendaten auf Policebene...
# ClaimNb_Check dient Validierung gegen die Frequency-Daten

sev_clean <- freMTPL2sev %>%
	group_by(IDpol) %>%
	summarise(
		ClaimTotal = sum(ClaimAmount, na.rm=TRUE),
		ClaimNb_Check = as.numeric(n()),
		.groups = "drop"
)

# Merging und Bereinigung (Hauptdatensatz dat)
# left_join: behält alle Policen aus Frequency Datei
# coalesce(...,0): Policen ohne Schaden erhalten ClaimTotal=0 und später ClaimNb=0
# filter(ClaimNb <= 5): Entfernt extreme Ausreißer(sehr selten, aber für stabile Modellierung)
# pmin(Exposure,1): Capping der Exposure auf max. 1Jahr
# Faktorisierung der kategorialen Variablen mit expliziten Levels

dat_05052026 <- freMTPL2freq %>%
	select(-ClaimNb) %>%
	left_join(sev_clean, by="IDpol") %>%
	mutate(ClaimTotal = coalesce(ClaimTotal, 0)) %>%
	filter(freMTPL2freq$ClaimNb <= 5) %>%
	mutate(Exposure = pmin(Exposure,1)) %>%
	mutate(
		VehGas = factor(VehGas),
		VehBrand = factor(VehBrand, level = c("B1","B2","B3","B4","B5","B6","B7","B8","B9","B10","B11","B12","B13","B14"))
)

str(dat_05052026)
wite.csv(dat_05052026,"data_clean_sev_freq_agg.csv", row.names=TRUE)
