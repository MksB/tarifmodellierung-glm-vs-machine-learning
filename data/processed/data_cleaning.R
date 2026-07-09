################################################################################
# data_cleaning.R
#
# Purpose : Data cleaning for the French Motor Third-Party Liability (MTPL)
#           dataset (freMTPL2freq + freMTPL2sev), following the procedure
#           described in Loser et al.
#
# Steps   :
#   1. Load raw data (from CASdatasets package OR local CSV files)
#   2. Correct claim counts: replace ClaimNb in freq with counts derived
#      from sev, because policies with IDpol <= 24 500 have no severity
#      counterparts (Loser et al.)
#   3. Aggregate severity file: total claim amount + count per policy
#   4. Merge frequency and aggregated severity tables
#   5. Drop policies with ClaimNb > 5 (likely data errors / same driver)
#   6. Censor Exposure at 1 (one accounting year maximum)
#   7. Filter severity file to retained policies only
#   8. Re-level VehBrand with canonical ordering
#   9. Basic validation checks
################################################################################


# ── 0. Packages ---------------------------------------------------------------
required_pkgs <- c("dplyr", "readr")
missing_pkgs  <- required_pkgs[!vapply(
  required_pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1)
)]
if (length(missing_pkgs) > 0L) {
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
}

library(dplyr)
library(readr)


# ── 1. Load raw data ----------------------------------------------------------
# Option A: from the CASdatasets package (preferred)
# Option B: from local CSV files (fallback)

load_raw_data <- function(freq_csv = NULL, sev_csv = NULL) {

  use_package <- requireNamespace("CASdatasets", quietly = TRUE) &&
    is.null(freq_csv) && is.null(sev_csv)

  if (use_package) {
    message("Loading data from CASdatasets package ...")
    data("freMTPL2freq", package = "CASdatasets", envir = environment())
    data("freMTPL2sev",  package = "CASdatasets", envir = environment())
    freq_raw <- get("freMTPL2freq", envir = environment())
    sev_raw  <- get("freMTPL2sev",  envir = environment())
  } else {
    stopifnot(
      "Provide paths to freq_csv and sev_csv when CASdatasets is unavailable." =
        !is.null(freq_csv) && !is.null(sev_csv)
    )
    message("Loading data from CSV files ...")
    freq_raw <- readr::read_csv(freq_csv, show_col_types = FALSE)
    sev_raw  <- readr::read_csv(sev_csv,  show_col_types = FALSE)
  }

  list(freq = as.data.frame(freq_raw),
       sev  = as.data.frame(sev_raw))
}


# ── 2. Main cleaning function -------------------------------------------------
#
#' Clean the freMTPL2 dataset.
#'
#' @param freq_raw  data.frame – raw freMTPL2freq table (must contain IDpol,
#'                  ClaimNb, Exposure, VehGas, VehBrand, and covariate columns).
#' @param sev_raw   data.frame – raw freMTPL2sev table (must contain IDpol,
#'                  ClaimAmount).
#' @param max_claims Integer scalar. Policies with more claims than this are
#'                   assumed to be data errors and are dropped (default 5).
#' @param max_exposure Numeric scalar. Exposures are censored at this value
#'                     (default 1, i.e. one accounting year).
#' @param veh_brand_levels Character vector giving the canonical factor levels
#'                          for VehBrand.
#'
#' @return A named list with two cleaned data frames:
#'   \item{freq}{Policy-level data (one row per policy).}
#'   \item{sev}{Claim-level severity data, restricted to retained policies.}
clean_fremtpl2 <- function(
    freq_raw,
    sev_raw,
    max_claims     = 5L,
    max_exposure   = 1.0,
    veh_brand_levels = c("B1","B2","B3","B4","B5","B6",
                         "B10","B11","B12","B13","B14")
) {

  # ── 2.1 Prepare frequency table ───────────────────────────────────────────
  # Drop the original ClaimNb column (unreliable for IDpol <= 24 500);
  # the corrected count will come from the severity file after aggregation.
  freq <- freq_raw |>
    dplyr::select(-ClaimNb) |>
    dplyr::mutate(VehGas = factor(VehGas))

  # ── 2.2 Aggregate severity file ───────────────────────────────────────────
  # For each policy: total claim amount  +  number of individual claims.
  # Using a single dplyr summarise avoids the need to carry a dummy column.
  sev_agg <- sev_raw |>
    dplyr::group_by(IDpol) |>
    dplyr::summarise(
      ClaimTotal = sum(ClaimAmount, na.rm = TRUE),
      ClaimNb    = dplyr::n(),            # count derived from severity file
      .groups    = "drop"
    )

  # ── 2.3 Merge ─────────────────────────────────────────────────────────────
  # Left join: all policies are retained; those without any claim get 0s.
  freq <- freq |>
    dplyr::left_join(sev_agg, by = "IDpol") |>
    dplyr::mutate(
      ClaimNb    = dplyr::coalesce(ClaimNb,    0L),
      ClaimTotal = dplyr::coalesce(ClaimTotal, 0.0)
    )

  # ── 2.4 Drop suspected data errors (ClaimNb > max_claims) ─────────────────
  # Policies with more than `max_claims` claims appear to belong to one driver
  # with unusually short exposures and are therefore excluded.
  n_before <- nrow(freq)
  freq <- dplyr::filter(freq, ClaimNb <= max_claims)
  n_dropped <- n_before - nrow(freq)
  message(sprintf(
    "Step 2.4: Dropped %d policies with ClaimNb > %d  (%d retained).",
    n_dropped, max_claims, nrow(freq)
  ))

  # ── 2.5 Censor exposure ───────────────────────────────────────────────────
  # All exposures are capped at max_exposure (= 1 accounting year).
  freq <- dplyr::mutate(freq, Exposure = pmin(Exposure, max_exposure))

  # ── 2.6 Restrict severity file to retained policies ───────────────────────
  sev_clean <- sev_raw |>
    dplyr::filter(IDpol %in% freq$IDpol) |>
    dplyr::select(IDpol, ClaimAmount)

  # ── 2.7 Re-level VehBrand ─────────────────────────────────────────────────
  freq <- dplyr::mutate(
    freq,
    VehBrand = factor(VehBrand, levels = veh_brand_levels)
  )

  list(freq = freq, sev = sev_clean)
}


# ── 3. Validation checks ------------------------------------------------------
#
#' Run basic sanity checks on the cleaned data.
#'
#' Prints a summary and stops with an informative error if a check fails.
#'
#' @param cleaned Named list returned by \code{clean_fremtpl2()}.
validate_cleaned_data <- function(cleaned) {

  freq <- cleaned$freq
  sev  <- cleaned$sev

  stopifnot(
    "ClaimNb must be non-negative"        = all(freq$ClaimNb    >= 0L),
    "Exposure must be in (0, 1]"          = all(freq$Exposure   >  0  &
                                                 freq$Exposure  <= 1),
    "ClaimTotal must be non-negative"     = all(freq$ClaimTotal >= 0.0),
    "No policies with ClaimNb > 5"        = all(freq$ClaimNb    <= 5L),
    "No missing IDpol in freq"            = !anyNA(freq$IDpol),
    "No missing IDpol in sev"             = !anyNA(sev$IDpol),
    "All sev IDpols present in freq"      = all(sev$IDpol %in% freq$IDpol),
    "ClaimAmount strictly positive"       = all(sev$ClaimAmount > 0),
    "VehBrand has no unexpected NA"       = !anyNA(freq$VehBrand),
    "VehGas is a factor"                  = is.factor(freq$VehGas),
    "VehBrand is a factor"                = is.factor(freq$VehBrand)
  )

  message("\n── Validation passed ──────────────────────────────────────────")
  message(sprintf("  freq: %d rows  |  %d columns", nrow(freq), ncol(freq)))
  message(sprintf("  sev : %d rows  |  %d columns", nrow(sev),  ncol(sev)))
  message(sprintf("  Policies with >=1 claim  : %d", sum(freq$ClaimNb > 0L)))
  message(sprintf("  Total individual claims  : %d", nrow(sev)))
  message(sprintf("  Exposure range           : [%.4f, %.4f]",
                  min(freq$Exposure), max(freq$Exposure)))
  message(sprintf("  ClaimNb distribution:\n%s\n",
                  paste(capture.output(table(freq$ClaimNb)), collapse = "\n")))
}


# ── 4. Run -------------------------------------------------------------------
raw   <- load_raw_data(
  freq_csv = "I:\\FREELANCE\\Versicherung\\PHASE_1\\freMTPL2freq.csv",
  sev_csv  = "I:\\FREELANCE\\Versicherung\\PHASE_1\\freMTPL2sev.csv"
)

cleaned <- clean_fremtpl2(
  freq_raw = raw$freq,
  sev_raw  = raw$sev
)

validate_cleaned_data(cleaned)

# Convenient top-level names (mirrors original variable names)
dat <- cleaned$freq
sev <- cleaned$sev
str(dat)
str(sev)

write.csv(dat, file="freMTPL2freq_clean.csv")
write.csv(sev, file="freMTPL2sev_clean.csv")
