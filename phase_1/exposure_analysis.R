################################################################################
# exposure_analysis.R
#
# Purpose : In-depth analysis of the Exposure variable in the freMTPL2 dataset
#           and rigorous preparation of offset(log(Exposure)) for Poisson GLMs.
#
# What Exposure means in French MTPL:
#   Each policy is active for a fraction of the calendar year (one accounting
#   period). Exposure measures how many *policy-years* of risk a record
#   represents. A policy active for 6 months → Exposure = 0.50.
#   After the cleaning step, Exposure is censored at 1 (one full year).
#
# Why offset(log(Exposure)) is mandatory in Poisson frequency models:
#   The Poisson GLM models E[ClaimNb] = lambda * Exposure, where lambda is
#   the latent *annual* claim rate. Taking logs:
#     log E[ClaimNb] = log(lambda) + log(Exposure)
#   The term log(Exposure) enters as an OFFSET – a covariate whose coefficient
#   is fixed at exactly 1 – so the model estimates *rates*, not raw counts.
#   Without the offset, a policy active for 1 month would be treated the same
#   as one active for 12 months, badly biasing every coefficient.
#
# Analysis structure:
#   Part 1 – Exposure distribution (histogram, density, CDF, spike analysis)
#   Part 2 – Recording precision (daily vs monthly vs 2-dp rounding)
#   Part 3 – Relationship between Exposure and covariates
#   Part 4 – log(Exposure) properties and offset construction
#   Part 5 – Offset correctness: Poisson GLM with and without offset (comparison)
#   Part 6 – Diagnostics: rate = ClaimNb / Exposure vs covariates
#   Part 7 – Summary table and final offset column
#
# Outputs : exposure_report.pdf    (13-page diagnostic PDF)
#           dat_with_offset.rds    (data frame with log_exposure column)
#
################################################################################


# ── 0. Packages ---------------------------------------------------------------
for (pkg in c("ggplot2", "gridExtra", "scales")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop(sprintf("Install missing package: install.packages('%s')", pkg))
}
library(ggplot2)
library(gridExtra)
library(scales)


# ── 1. Configuration ----------------------------------------------------------
FREQ_CSV   <- "freMTPL2freq.csv"
SEV_CSV    <- "freMTPL2sev.csv"
OUTPUT_PDF <- "exposure_report.pdf"
OUTPUT_RDS <- "dat_with_offset.rds"

# Shared theme
theme_exp <- function(base = 11) {
  theme_minimal(base_size = base) +
    theme(
      plot.title       = element_text(face = "bold", size = base + 2),
      plot.subtitle    = element_text(size = base - 1, colour = "grey40"),
      panel.grid.minor = element_blank(),
      strip.text       = element_text(face = "bold")
    )
}

COL_EXP   <- "#4472C4"   # main exposure colour
COL_LOG   <- "#ED7D31"   # log(Exposure) colour
COL_RATE  <- "#70AD47"   # claim rate colour
COL_WARN  <- "#C00000"   # warning / anomaly colour


# ── 2. Data preparation -------------------------------------------------------
prepare_data <- function(freq_csv, sev_csv) {
  freq_raw <- read.csv(freq_csv, stringsAsFactors = FALSE)
  sev_raw  <- read.csv(sev_csv,  stringsAsFactors = FALSE)

  freq <- freq_raw[, names(freq_raw) != "ClaimNb"]
  sev_agg <- aggregate(
    list(ClaimTotal = sev_raw$ClaimAmount,
         ClaimNb    = rep(1L, nrow(sev_raw))),
    by = list(IDpol = sev_raw$IDpol), FUN = sum
  )
  dat <- merge(freq, sev_agg, by = "IDpol", all.x = TRUE)
  dat$ClaimNb[is.na(dat$ClaimNb)]       <- 0L
  dat$ClaimTotal[is.na(dat$ClaimTotal)] <- 0.0
  dat <- dat[dat$ClaimNb <= 5L, ]
  dat$Exposure  <- pmin(dat$Exposure, 1.0)
  dat$VehBrand  <- factor(dat$VehBrand,
    levels = c("B1","B2","B3","B4","B5","B6","B10","B11","B12","B13","B14"))
  dat$VehGas    <- factor(dat$VehGas)
  dat$Area      <- factor(dat$Area, levels = sort(unique(dat$Area)))
  dat$Region    <- factor(dat$Region)
  dat
}


# ── 3. Exposure recording precision ------------------------------------------
#' Classify how each Exposure value was recorded.
#'
#' Three recording systems coexist in the data:
#'   "daily"   – exact integer multiples of 1/365 (≈ 0.00274 per day)
#'   "monthly" – exact integer multiples of 1/12  (≈ 0.08333 per month)
#'   "decimal" – rounded to 2 decimal places (e.g. 0.08, 0.49)
#'
#' In practice most values satisfy multiple criteria; "decimal" is the
#' catch-all. The distinction matters for understanding precision of the
#' offset but does NOT affect the validity of log(Exposure).
classify_precision <- function(e) {
  is_daily   <- abs(e * 365 - round(e * 365)) < 1e-4  & e < 1
  is_monthly <- abs(e * 12  - round(e * 12))  < 1e-4  & e < 1
  is_full    <- e == 1.0

  dplyr_like <- ifelse(is_full,    "Full year (= 1)",
                ifelse(is_daily,   "Daily fraction (k/365)",
                ifelse(is_monthly, "Monthly fraction (k/12)",
                                   "Decimal (2 d.p.)")))
  factor(dplyr_like,
         levels = c("Full year (= 1)", "Daily fraction (k/365)",
                    "Monthly fraction (k/12)", "Decimal (2 d.p.)"))
}


# ── 4. Plots ------------------------------------------------------------------

## 4.1  Conceptual diagram: what Exposure means --------------------------------
plot_concept <- function() {
  # Timeline illustration: 4 example policies within one calendar year
  policies <- data.frame(
    id      = factor(c("Policy A\n(Full year)",
                       "Policy B\n(Jul–Dec, E=0.50)",
                       "Policy C\n(Mar–Nov, E=0.75)",
                       "Policy D\n(Jan only, E=0.08)"),
                     levels = rev(c("Policy A\n(Full year)",
                                    "Policy B\n(Jul–Dec, E=0.50)",
                                    "Policy C\n(Mar–Nov, E=0.75)",
                                    "Policy D\n(Jan only, E=0.08)"))),
    start   = c(0.00, 0.50, 0.17, 0.00),
    end     = c(1.00, 1.00, 0.92, 0.08),
    exp_val = c(1.00, 0.50, 0.75, 0.08)
  )

  ggplot(policies, aes(xmin = start, xmax = end, ymin = as.numeric(id) - 0.3,
                        ymax = as.numeric(id) + 0.3, fill = exp_val)) +
    geom_rect(colour = "white", linewidth = 0.5) +
    scale_fill_gradient(low = "#BDD7EE", high = COL_EXP,
                        name = "Exposure", limits = c(0, 1)) +
    scale_x_continuous(
      breaks = seq(0, 1, 1/12),
      labels = c("Jan","Feb","Mar","Apr","May","Jun",
                 "Jul","Aug","Sep","Oct","Nov","Dec",""),
      expand = expansion(mult = c(0.01, 0.01))
    ) +
    scale_y_continuous(breaks = 1:4, labels = rev(levels(policies$id))) +
    geom_text(aes(x = (start + end) / 2, y = as.numeric(id),
                  label = sprintf("E = %.2f", exp_val)),
              colour = "white", fontface = "bold", size = 3.8) +
    labs(
      title    = "What does Exposure measure?",
      subtitle = paste0(
        "Each policy is active for a fraction of the calendar year.\n",
        "Exposure = proportion of the year the policy was in force ",
        "(censored at 1.0 after cleaning)."
      ),
      x = "Calendar month", y = NULL
    ) +
    theme_exp() +
    theme(legend.position = "right", axis.text.y = element_text(size = 9))
}


## 4.2  Histogram of Exposure --------------------------------------------------
plot_hist <- function(dat) {
  e     <- dat$Exposure
  prec  <- classify_precision(e)
  tmp   <- data.frame(e = e, precision = prec)

  ggplot(tmp, aes(x = e, fill = precision)) +
    geom_histogram(binwidth = 0.02, colour = "white", linewidth = 0.15) +
    geom_vline(xintercept = 1.0, colour = COL_WARN,
               linetype = "dashed", linewidth = 0.9) +
    annotate("text", x = 0.97, y = Inf, label = "Censored\nat 1.0",
             hjust = 1, vjust = 1.5, colour = COL_WARN, size = 3.2,
             fontface = "bold") +
    scale_fill_manual(values = c(
      "Full year (= 1)"        = COL_WARN,
      "Daily fraction (k/365)" = "#9DC3E6",
      "Monthly fraction (k/12)"= "#2E75B6",
      "Decimal (2 d.p.)"       = "#BDD7EE"
    )) +
    scale_x_continuous(breaks = seq(0, 1, 0.1)) +
    labs(
      title    = "Distribution of Exposure",
      subtitle = sprintf(
        "n = %d | mean = %.3f | median = %.3f | sd = %.3f | sum = %.1f policy-years",
        length(e), mean(e), median(e), sd(e), sum(e)
      ),
      x = "Exposure (proportion of year)", y = "Count",
      fill = "Recording precision"
    ) +
    theme_exp() +
    theme(legend.position = "bottom",
          legend.text = element_text(size = 8))
}


## 4.3  Empirical CDF ----------------------------------------------------------
plot_ecdf <- function(dat) {
  e   <- sort(dat$Exposure)
  cdf <- seq_along(e) / length(e)
  tmp <- data.frame(e = e, cdf = cdf)

  # mark key percentiles
  pcts <- c(0.25, 0.50, 0.75, 0.80)
  pct_vals <- quantile(e, pcts)
  pct_df   <- data.frame(e = pct_vals, cdf = pcts,
                          label = sprintf("P%d\n%.2f", pcts * 100, pct_vals))

  ggplot(tmp, aes(x = e, y = cdf)) +
    geom_line(colour = COL_EXP, linewidth = 1.0) +
    geom_segment(data = pct_df,
                 aes(x = e, xend = e, y = 0, yend = cdf),
                 linetype = "dashed", colour = "grey50", linewidth = 0.5) +
    geom_segment(data = pct_df,
                 aes(x = 0, xend = e, y = cdf, yend = cdf),
                 linetype = "dashed", colour = "grey50", linewidth = 0.5) +
    geom_point(data = pct_df, aes(x = e, y = cdf),
               colour = COL_WARN, size = 2.5) +
    geom_text(data = pct_df, aes(x = e + 0.03, y = cdf - 0.04, label = label),
              size = 2.8, colour = "grey30") +
    scale_x_continuous(breaks = seq(0, 1, 0.1)) +
    scale_y_continuous(labels = scales::percent_format()) +
    labs(
      title    = "Empirical CDF of Exposure",
      subtitle = sprintf("%.1f%% of policies have Exposure = 1 (full year)",
                         mean(e == 1) * 100),
      x = "Exposure", y = "Cumulative proportion"
    ) +
    theme_exp()
}


## 4.4  Recording precision breakdown ------------------------------------------
plot_precision <- function(dat) {
  prec <- classify_precision(dat$Exposure)
  tmp  <- as.data.frame(table(prec))
  names(tmp) <- c("Category", "Count")
  tmp$Pct <- tmp$Count / sum(tmp$Count) * 100

  ggplot(tmp, aes(x = reorder(Category, Count), y = Count)) +
    geom_col(fill = COL_EXP, width = 0.6) +
    geom_text(aes(label = sprintf("%d\n(%.1f%%)", Count, Pct)),
              hjust = -0.1, size = 3.2) +
    coord_flip() +
    scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
    labs(
      title    = "Exposure recording precision",
      subtitle = paste0(
        "Most values are stored as 2-decimal fractions.\n",
        "'Full year' = censored at 1.0 after cleaning (pmin rule)."
      ),
      x = NULL, y = "Number of policies"
    ) +
    theme_exp()
}


## 4.5  Exposure vs covariates (box plots) ------------------------------------
plot_exp_by_covariate <- function(dat, var, fill_col = COL_EXP) {
  tmp <- data.frame(x = dat[[var]], e = dat$Exposure)

  ggplot(tmp, aes(x = factor(x), y = e)) +
    geom_boxplot(fill = fill_col, colour = "grey30",
                 outlier.size = 0.8, linewidth = 0.5, width = 0.55,
                 outlier.colour = COL_WARN) +
    stat_summary(fun = mean, geom = "point",
                 shape = 23, size = 2, fill = "white") +
    labs(
      title    = sprintf("Exposure by %s", var),
      subtitle = "Diamond = mean | Whiskers = 1.5 × IQR | Red dots = outliers",
      x = var, y = "Exposure"
    ) +
    theme_exp() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
}


## 4.6  log(Exposure): distribution and properties ----------------------------
plot_log_exposure <- function(dat) {
  le  <- log(dat$Exposure)
  tmp <- data.frame(le = le)

  p1 <- ggplot(tmp, aes(x = le)) +
    geom_histogram(bins = 60, fill = COL_LOG, colour = "white",
                   linewidth = 0.15) +
    geom_vline(xintercept = 0, colour = COL_WARN,
               linetype = "dashed", linewidth = 0.9) +
    annotate("text", x = 0.05, y = Inf,
             label = "log(1) = 0\n(full year)", hjust = 0, vjust = 1.5,
             colour = COL_WARN, size = 3.0, fontface = "bold") +
    scale_x_continuous(
      sec.axis = sec_axis(
        trans = ~ exp(.),
        breaks    = exp(c(-6, -4, -2, -1, -0.5, 0)),
        labels    = function(x) sprintf("E=%.3f", x),
        name      = "Original Exposure scale"
      )
    ) +
    labs(
      title    = "Distribution of log(Exposure)  [= the offset value]",
      subtitle = sprintf(
        "Range: [%.3f, %.1f] | Mean: %.3f | No -Inf values (min Exposure = %.5f > 0)",
        min(le), max(le), mean(le), min(dat$Exposure)
      ),
      x = "log(Exposure)", y = "Count"
    ) +
    theme_exp()

  # Scatter: Exposure vs log(Exposure) with annotation
  x_seq <- seq(0.001, 1, length.out = 500)
  curve_df <- data.frame(e = x_seq, le = log(x_seq))

  p2 <- ggplot(curve_df, aes(x = e, y = le)) +
    geom_line(colour = COL_LOG, linewidth = 1.2) +
    geom_point(data = data.frame(e = dat$Exposure, le = log(dat$Exposure)),
               aes(x = e, y = le), colour = COL_EXP, alpha = 0.25,
               size = 0.8) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = COL_WARN,
               linewidth = 0.7) +
    geom_vline(xintercept = 1, linetype = "dashed", colour = COL_WARN,
               linewidth = 0.7) +
    annotate("text", x = 0.5, y = -3.5,
             label = "log(E) compresses the\nlong right tail of Exposure\n→ numerically stable offset",
             size = 3.2, colour = "grey30", hjust = 0) +
    scale_x_continuous(breaks = seq(0, 1, 0.2)) +
    labs(
      title    = "log(Exposure) as a function of Exposure",
      subtitle = "Blue dots = observed policies; orange curve = log function",
      x = "Exposure", y = "log(Exposure)  [offset value]"
    ) +
    theme_exp()

  gridExtra::grid.arrange(p1, p2, ncol = 2)
}


## 4.7  Why the offset is mandatory: model comparison -------------------------
#' Fit two Poisson GLMs – with and without offset – and compare coefficients
#' and fitted annual rates to demonstrate the bias introduced without offset.
#'
#' NOTE: Because this 1 000-row sample has very few claims (or none) relative
#' to the full 677 992-row dataset, the numerical comparison is illustrative.
#' In production on the full data the bias is substantial and well-documented
#' in the actuarial literature (e.g. Ohlsson & Johansson 2010).
plot_offset_comparison <- function(dat) {

  has_claims <- sum(dat$ClaimNb) > 0

  if (!has_claims) {
    # Create a minimal synthetic illustration using the full covariate structure
    # but injecting a small number of artificial claims proportional to Exposure
    # so the GLM can converge. This is purely for illustrative purposes and is
    # clearly labelled as such in the plot.
    set.seed(42L)
    dat_demo       <- dat
    # Assign claims with probability proportional to Exposure * 0.07 (7% annual rate)
    dat_demo$ClaimNb <- rbinom(nrow(dat), size = 1L,
                                prob = pmin(dat$Exposure * 0.07, 0.99))
  } else {
    dat_demo <- dat
  }

  # Model 1: with correct offset
  fit_with <- tryCatch(
    glm(ClaimNb ~ VehGas + Area + offset(log(Exposure)),
        family = poisson(link = "log"), data = dat_demo),
    error = function(e) NULL
  )

  # Model 2: without offset (incorrect – counts, not rates)
  fit_without <- tryCatch(
    glm(ClaimNb ~ VehGas + Area,
        family = poisson(link = "log"), data = dat_demo),
    error = function(e) NULL
  )

  if (is.null(fit_with) || is.null(fit_without)) {
    return(ggplot() +
      annotate("text", x = 0.5, y = 0.5,
               label = "GLM could not converge on this sample\n(too few claims).\nOn the full 677 992-row dataset the offset effect is substantial.",
               size = 4, hjust = 0.5) +
      theme_void() +
      labs(title = "Offset comparison (illustrative)"))
  }

  # Compare fitted annual rates
  rate_with    <- fitted(fit_with)    / dat_demo$Exposure
  rate_without <- fitted(fit_without) / dat_demo$Exposure

  tmp <- data.frame(
    Exposure     = dat_demo$Exposure,
    Rate_With    = rate_with,
    Rate_Without = rate_without
  )

  p1 <- ggplot(tmp, aes(x = Exposure)) +
    geom_point(aes(y = Rate_With,    colour = "With offset(log(E))"),
               alpha = 0.4, size = 0.9) +
    geom_point(aes(y = Rate_Without, colour = "Without offset"),
               alpha = 0.4, size = 0.9) +
    geom_hline(yintercept = mean(dat_demo$ClaimNb / dat_demo$Exposure[dat_demo$Exposure > 0]),
               linetype = "dashed", colour = "grey40", linewidth = 0.7) +
    scale_colour_manual(
      values = c("With offset(log(E))" = COL_RATE,
                 "Without offset"       = COL_WARN)
    ) +
    labs(
      title    = "Fitted annual claim rates: with vs without offset",
      subtitle = if (!has_claims) "(Illustrative: synthetic claims used)" else
                 "Rates should be roughly constant across Exposure values",
      x = "Exposure", y = "Fitted annual claim rate",
      colour = NULL
    ) +
    theme_exp() +
    theme(legend.position = "top")

  # Coefficient comparison table
  coef_with    <- coef(fit_with)
  coef_without <- coef(fit_without)
  common       <- intersect(names(coef_with), names(coef_without))
  coef_df <- data.frame(
    Parameter     = common,
    With_Offset   = round(coef_with[common],    4),
    Without_Offset = round(coef_without[common], 4),
    Difference    = round(coef_with[common] - coef_without[common], 4),
    stringsAsFactors = FALSE
  )

  tbl_grob <- gridExtra::tableGrob(
    coef_df, rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core    = list(fg_params = list(cex = 0.78)),
      colhead = list(fg_params = list(cex = 0.82, fontface = "bold"),
                     bg_params = list(fill = "#4472C4", alpha = 0.85))
    )
  )
  title_grob <- grid::textGrob(
    "Coefficient comparison: with vs without offset",
    gp = grid::gpar(fontsize = 11, fontface = "bold")
  )

  gridExtra::grid.arrange(
    p1,
    gridExtra::arrangeGrob(title_grob, tbl_grob,
                            ncol = 1, heights = c(0.12, 0.88)),
    ncol = 2
  )
}


## 4.8  Claim rate vs Exposure (rate = ClaimNb / Exposure) --------------------
plot_claim_rate <- function(dat) {
  # Only produce this plot when claims exist
  if (sum(dat$ClaimNb) == 0L) {
    return(
      ggplot() +
        annotate("text", x = 0.5, y = 0.5,
                 label = "No claims in this sample.\nOn the full dataset this plot shows\nthe empirical annual rate vs Exposure.",
                 hjust = 0.5, size = 4.5, colour = "grey40") +
        theme_void() +
        labs(title = "Claim rate vs Exposure (requires claims in data)")
    )
  }

  claimers <- dat[dat$ClaimNb > 0, ]
  claimers$Rate <- claimers$ClaimNb / claimers$Exposure
  claimers$ExpBin <- cut(claimers$Exposure,
                          breaks = c(0, 0.25, 0.5, 0.75, 1.001),
                          labels = c("(0, 0.25]","(0.25, 0.5]",
                                     "(0.5, 0.75]","(0.75, 1.0]"),
                          right  = TRUE)
  ggplot(claimers, aes(x = Exposure, y = Rate)) +
    geom_point(colour = COL_RATE, alpha = 0.6, size = 1.5) +
    geom_smooth(method = "loess", se = TRUE, colour = COL_WARN,
                linewidth = 0.9, fill = COL_WARN, alpha = 0.15) +
    geom_hline(yintercept = mean(claimers$Rate), linetype = "dashed",
               colour = "grey40", linewidth = 0.7) +
    scale_y_log10() +
    labs(
      title    = "Empirical claim rate vs Exposure (policies with ≥1 claim)",
      subtitle = "If the Poisson rate model is correct, rate should be ~flat across Exposure.\nDashed = mean rate.",
      x = "Exposure", y = "ClaimNb / Exposure  (log scale)"
    ) +
    theme_exp()
}


## 4.9  Exposure summary statistics table -------------------------------------
plot_summary_table <- function(dat) {
  e  <- dat$Exposure
  le <- log(e)

  rows <- data.frame(
    Statistic = c("N (policies)", "Sum (total policy-years)",
                  "Min", "1st Quartile (P25)", "Median (P50)",
                  "Mean", "3rd Quartile (P75)", "P90", "P95",
                  "Max (censored at 1)", "Standard deviation",
                  "Skewness",
                  "Policies with Exposure = 1.0",
                  "Policies with Exposure < 0.01",
                  "log(Exposure): min", "log(Exposure): max",
                  "log(Exposure): mean",
                  "Any log(Exposure) = -Inf?",
                  "Any log(Exposure) = NA?"),
    Value = c(
      format(length(e), big.mark = ","),
      sprintf("%.2f", sum(e)),
      sprintf("%.5f", min(e)),
      sprintf("%.4f", quantile(e, 0.25)),
      sprintf("%.4f", quantile(e, 0.50)),
      sprintf("%.4f", mean(e)),
      sprintf("%.4f", quantile(e, 0.75)),
      sprintf("%.4f", quantile(e, 0.90)),
      sprintf("%.4f", quantile(e, 0.95)),
      sprintf("%.4f", max(e)),
      sprintf("%.4f", sd(e)),
      sprintf("%.4f", mean(((e - mean(e)) / sd(e))^3)),
      sprintf("%d (%.1f%%)", sum(e == 1), mean(e == 1) * 100),
      sprintf("%d (%.1f%%)", sum(e < 0.01), mean(e < 0.01) * 100),
      sprintf("%.4f", min(le)),
      sprintf("%.4f", max(le)),
      sprintf("%.4f", mean(le)),
      as.character(any(is.infinite(le) & le < 0)),
      as.character(any(is.na(le)))
    ),
    stringsAsFactors = FALSE
  )

  title_g <- grid::textGrob(
    "Exposure variable — summary statistics",
    gp = grid::gpar(fontsize = 13, fontface = "bold")
  )
  tbl_g <- gridExtra::tableGrob(
    rows, rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core    = list(fg_params = list(cex = 0.82)),
      colhead = list(fg_params = list(cex = 0.86, fontface = "bold"),
                     bg_params = list(fill = "#4472C4", alpha = 0.85))
    )
  )
  gridExtra::grid.arrange(title_g, tbl_g, ncol = 1, heights = c(0.07, 0.93))
}


## 4.10  Offset construction explanation table ---------------------------------
plot_offset_explanation <- function() {
  rows <- data.frame(
    Step = 1:6,
    Action = c(
      "Verify Exposure > 0 for all rows",
      "Compute log_exposure = log(Exposure)",
      "Confirm no -Inf / NA in log_exposure",
      "Add log_exposure column to data frame",
      "Use in GLM as: offset(log_exposure)",
      "Confirm the GLM coefficient is fixed at 1"
    ),
    Code = c(
      "stopifnot(all(dat$Exposure > 0))",
      "dat$log_exposure <- log(dat$Exposure)",
      "stopifnot(!anyNA(dat$log_exposure), all(is.finite(dat$log_exposure)))",
      "# column now part of dat",
      "glm(ClaimNb ~ X1 + X2 + offset(log_exposure), family=poisson)",
      "# offset coefficient is implicitly 1 by definition"
    ),
    Why = c(
      "log(0) = -Inf breaks the GLM numerical solver",
      "Poisson link is log; offset enters on same scale",
      "Defensive check before modelling",
      "Reproducible; avoids recomputing inline each time",
      "Fixes the Exposure coefficient at exactly 1",
      "Model now estimates annual RATE lambda, not raw count"
    ),
    stringsAsFactors = FALSE
  )

  title_g <- grid::textGrob(
    "How to prepare and use offset(log(Exposure))  —  step-by-step",
    gp = grid::gpar(fontsize = 12, fontface = "bold")
  )
  tbl_g <- gridExtra::tableGrob(
    rows, rows = NULL,
    theme = gridExtra::ttheme_minimal(
      core    = list(fg_params = list(cex = 0.72)),
      colhead = list(fg_params = list(cex = 0.78, fontface = "bold"),
                     bg_params = list(fill = "#ED7D31", alpha = 0.85))
    )
  )
  gridExtra::grid.arrange(title_g, tbl_g, ncol = 1, heights = c(0.06, 0.94))
}


# ── 5. Build and validate the offset column ----------------------------------
#' Construct log_exposure and run all safety checks.
#'
#' @param dat  Cleaned data.frame with Exposure column.
#' @return dat with added log_exposure column (and validation messages).
build_offset <- function(dat) {

  # ── Guard 1: Exposure must be strictly positive ───────────────────────────
  n_zero_or_neg <- sum(dat$Exposure <= 0, na.rm = TRUE)
  if (n_zero_or_neg > 0L) {
    stop(sprintf(
      "%d rows have Exposure <= 0. log(Exposure) would be -Inf or NaN. ",
      n_zero_or_neg,
      "Apply the 1/365 floor fix from missing_values.R before proceeding."
    ))
  }

  # ── Guard 2: Exposure must be <= 1 (cleaning already enforced this) ───────
  n_over_one <- sum(dat$Exposure > 1, na.rm = TRUE)
  if (n_over_one > 0L) {
    warning(sprintf("%d rows have Exposure > 1. Was pmin(Exposure, 1) applied?",
                    n_over_one))
  }

  # ── Compute offset ────────────────────────────────────────────────────────
  dat$log_exposure <- log(dat$Exposure)

  # ── Guard 3: Confirm numerical safety ─────────────────────────────────────
  stopifnot(
    "log_exposure contains NA"   = !anyNA(dat$log_exposure),
    "log_exposure contains -Inf" = !any(is.infinite(dat$log_exposure) &
                                         dat$log_exposure < 0),
    "log_exposure contains +Inf" = !any(is.infinite(dat$log_exposure) &
                                         dat$log_exposure > 0),
    "log_exposure contains NaN"  = !any(is.nan(dat$log_exposure))
  )

  message(sprintf(
    paste0("log_exposure built successfully.\n",
           "  Range : [%.5f, %.4f]\n",
           "  Mean  : %.5f\n",
           "  All finite, no NA, no -Inf."),
    min(dat$log_exposure), max(dat$log_exposure), mean(dat$log_exposure)
  ))

  dat
}


# ── 6. Main -------------------------------------------------------------------
run_exposure_analysis <- function(
    freq_csv   = FREQ_CSV,
    sev_csv    = SEV_CSV,
    output_pdf = OUTPUT_PDF,
    output_rds = OUTPUT_RDS
) {
  # ── Prepare data ──────────────────────────────────────────────────────────
  dat <- prepare_data(freq_csv, sev_csv)

  # ── Build offset ──────────────────────────────────────────────────────────
  dat <- build_offset(dat)

  # ── Save enriched data ────────────────────────────────────────────────────
  saveRDS(dat, output_rds)
  message(sprintf("Data with offset saved: '%s'", output_rds))

  # ── Generate PDF report ───────────────────────────────────────────────────
  message(sprintf("Building report → '%s' …", output_pdf))
  pdf(output_pdf, width = 12, height = 7.5, onefile = TRUE)

  # Page 1: Conceptual diagram
  print(plot_concept())

  # Page 2: Summary statistics table
  plot_summary_table(dat)

  # Page 3: Histogram (with precision colouring)
  print(plot_hist(dat))

  # Page 4: Empirical CDF
  print(plot_ecdf(dat))

  # Page 5: Recording precision breakdown
  print(plot_precision(dat))

  # Page 6: log(Exposure) distribution + function curve
  plot_log_exposure(dat)

  # Page 7: Offset construction step-by-step
  plot_offset_explanation()

  # Page 8–10: Exposure vs covariates
  print(plot_exp_by_covariate(dat, "Area"))
  print(plot_exp_by_covariate(dat, "VehGas"))
  print(plot_exp_by_covariate(dat, "VehBrand"))

  # Page 11: Exposure vs DrivAge (scatter)
  tmp_scatter <- data.frame(DrivAge = dat$DrivAge, Exposure = dat$Exposure,
                             Area = dat$Area)
  p_scatter <- ggplot(tmp_scatter, aes(x = DrivAge, y = Exposure,
                                        colour = Area)) +
    geom_point(alpha = 0.35, size = 0.9) +
    geom_smooth(aes(group = 1), method = "loess", se = TRUE,
                colour = "black", linewidth = 0.8,
                fill = "grey70", alpha = 0.25) +
    labs(
      title    = "Exposure vs Driver Age",
      subtitle = "Weak or no trend expected — Exposure depends on policy start date, not demographics",
      x = "Driver age (years)", y = "Exposure"
    ) +
    theme_exp()
  print(p_scatter)

  # Page 12: Offset comparison (with vs without)
  plot_offset_comparison(dat)

  # Page 13: Claim rate vs Exposure
  print(plot_claim_rate(dat))

  dev.off()
  message(sprintf("Report saved: '%s'", output_pdf))

  invisible(dat)
}


# ── 7. Execute ----------------------------------------------------------------
dat_final <- run_exposure_analysis()

# ── 8. Quick reference: how to use the offset in practice --------------------
cat("\n")
cat("══════════════════════════════════════════════════════════════════\n")
cat("  OFFSET USAGE REFERENCE\n")
cat("══════════════════════════════════════════════════════════════════\n")
cat("\n")
cat("  # 1. Load the saved data (offset column already included)\n")
cat("  dat <- readRDS('dat_with_offset.rds')\n")
cat("\n")
cat("  # 2a. Use the pre-computed column (recommended)\n")
cat("  glm(ClaimNb ~ VehPower + VehAge + DrivAge + BonusMalus +\n")
cat("                VehBrand + VehGas + Area + Region +\n")
cat("                offset(log_exposure),\n")
cat("      family = poisson(link = 'log'),\n")
cat("      data   = dat)\n")
cat("\n")
cat("  # 2b. Compute inline (equivalent, slightly less readable)\n")
cat("  glm(ClaimNb ~ . + offset(log(Exposure)) - IDpol - ClaimTotal\n")
cat("                  - log_exposure,\n")
cat("      family = poisson(link = 'log'),\n")
cat("      data   = dat)\n")
cat("\n")
cat("  # 3. Negative Binomial (overdispersion)\n")
cat("  # library(MASS)\n")
cat("  # MASS::glm.nb(ClaimNb ~ VehPower + ... + offset(log_exposure),\n")
cat("  #              data = dat)\n")
cat("\n")
cat("  # 4. What the offset does:\n")
cat("  #    Without offset: E[ClaimNb] = exp(Xb)            [wrong: count model]\n")
cat("  #    With    offset: E[ClaimNb] = exp(Xb) * Exposure  [correct: rate model]\n")
cat("  #    The model coefficients exp(b_j) are now multiplicative\n")
cat("  #    effects on the ANNUAL claim rate, not on the raw count.\n")
cat("══════════════════════════════════════════════════════════════════\n")
