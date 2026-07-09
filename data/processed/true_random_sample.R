################################################################################
# true_random_sample.R
#
# Zweck  : Zieht n = 1000 Zeilen aus einer grossen CSV-Datei (677 992 Zeilen)
#          unter Verwendung ECHTER Zufaelligkeit – nicht des deterministischen
#          Mersenne-Twister-PRNG von R.
#
# Strategie der Zufaelligkeit (Rangfolge):
#   1. random.org  – atmosphaerisches Rauschen (echter physikalischer Zufall)
#      Anforderung: Internetverbindung + freies random.org-Kontingent
#   2. /dev/urandom – Hardware-Entropy des Betriebssystems (Linux/macOS)
#      Anforderung: Unix-artiges OS
#   3. Fallback     – openssl::rand_bytes()  (kryptografisch stark, plattform-
#                     unabhaengig, aber immer noch CSPRNG, kein echter Zufall)

################################################################################


# ── 0. Pakete -----------------------------------------------------------------
# Installiere fehlende Pakete automatisch
required_pkgs <- c("httr2", "readr", "openssl", "cli")
missing_pkgs  <- required_pkgs[!vapply(required_pkgs, requireNamespace,
                                       quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_pkgs) > 0L) {
  message("Installiere fehlende Pakete: ", paste(missing_pkgs, collapse = ", "))
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
}

library(httr2)
library(readr)
library(openssl)
library(cli)


# ── 1. Konfiguration ----------------------------------------------------------
CSV_PATH      <- "C:\\Users\\....\\Desktop\\FREELANCE\\Versicherung\\freMTPLfreq_sev.csv"   # <-- Pfad zur CSV-Datei anpassen
OUTPUT_PATH   <- "data_2000.csv"
N_SAMPLE      <- 2000L
N_TOTAL       <- 677992L       # bekannte Gesamtzahl der Zeilen (ohne Header)
HAS_HEADER    <- TRUE          # TRUE wenn erste Zeile ein Header ist
RANDOM_ORG_API_KEY <- ""       # optional: random.org API-Key eintragen
                               # (ohne Key: freies Kontingent, max 10 000/Tag)


# ── 2. Zufaellige Index-Erzeugung ---------------------------------------------

## 2a. random.org ---------------------------------------------------------------
#' Holt n eindeutige Integer aus der random.org HTTPS-API.
#'
#' @param n        Anzahl benoedigter Zahlen.
#' @param min_val  Untere Grenze (inklusiv).
#' @param max_val  Obere Grenze (inklusiv).
#' @param api_key  Optional: random.org API-Key (leerer String = anonymer Zugriff).
#' @return Integer-Vektor der Laenge n, oder NULL bei Fehler.
fetch_random_org <- function(n, min_val, max_val, api_key = "") {

  stopifnot(is.numeric(n), n >= 1L,
            is.numeric(min_val), is.numeric(max_val),
            min_val < max_val)

  # random.org erlaubt max. 10 000 Integers pro Anfrage
  if (n > 10000L) {
    cli::cli_abort("random.org: max. 10 000 Integers pro Anfrage (n = {n}).")
  }

  url <- "https://www.random.org/integers/"
  params <- list(
    num    = n,
    min    = min_val,
    max    = max_val,
    col    = 1,
    base   = 10,
    format = "plain",
    rnd    = if (nzchar(api_key)) paste0("id.", api_key) else "new"
  )

  req <- httr2::request(url) |>
    httr2::req_url_query(!!!params) |>
    httr2::req_timeout(30) |>
    httr2::req_retry(max_tries = 3, backoff = ~ 2)

  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      cli::cli_warn("random.org nicht erreichbar: {conditionMessage(e)}")
      NULL
    }
  )

  if (is.null(resp) || httr2::resp_status(resp) != 200L) return(NULL)

  body <- httr2::resp_body_string(resp)

  # Fehlermeldung von random.org abfangen
  if (grepl("Error|exceeded|quota", body, ignore.case = TRUE)) {
    cli::cli_warn("random.org meldet Fehler: {trimws(body)}")
    return(NULL)
  }

  nums <- suppressWarnings(as.integer(strsplit(trimws(body), "\\s+")[[1]]))
  if (anyNA(nums) || length(nums) != n) {
    cli::cli_warn("random.org: unerwartetes Antwortformat.")
    return(NULL)
  }

  nums
}


## 2b. /dev/urandom (Unix) ------------------------------------------------------
#' Erzeugt n eindeutige Integer in [min_val, max_val] aus /dev/urandom.
#'
#' Liest 4-Byte-Bloecke aus /dev/urandom und wandelt sie in Indizes um
#' (rejection sampling, um Modulo-Bias zu vermeiden).
#'
#' @param n        Anzahl benoedigter Zahlen.
#' @param min_val  Untere Grenze (inklusiv).
#' @param max_val  Obere Grenze (inklusiv).
#' @return Integer-Vektor der Laenge n, oder NULL bei Fehler.
fetch_dev_urandom <- function(n, min_val, max_val) {

  if (.Platform$OS.type == "windows") {
    cli::cli_warn("/dev/urandom ist unter Windows nicht verfuegbar.")
    return(NULL)
  }

  range_size <- max_val - min_val + 1L
  # Groesste Vielfache von range_size, das in 2^32 passt (Bias-Vermeidung)
  limit <- floor(2^32 / range_size) * range_size

  result   <- integer(0L)
  attempts <- 0L
  max_iter <- n * 10L   # Sicherheitsstop

  con <- tryCatch(
    file("/dev/urandom", "rb"),
    error = function(e) {
      cli::cli_warn("/dev/urandom nicht lesbar: {conditionMessage(e)}")
      NULL
    }
  )
  if (is.null(con)) return(NULL)
  on.exit(close(con), add = TRUE)

  while (length(result) < n && attempts < max_iter) {
    # Lese Bytes als unsigned 32-bit Integer
    raw_bytes <- readBin(con, what = "raw", n = 4L * (n - length(result)) * 2L)
    if (length(raw_bytes) < 4L) break

    # Gruppiere in 4-Byte-Worte
    n_words  <- length(raw_bytes) %/% 4L
    raw_mat  <- matrix(raw_bytes[seq_len(n_words * 4L)], nrow = 4L)

    # Konvertiere zu unsigned int32 (Big-Endian)
    uint32   <- colSums(
      matrix(as.integer(raw_mat), nrow = 4L) *
        matrix(c(16777216L, 65536L, 256L, 1L), nrow = 4L,
               ncol = n_words, byrow = FALSE)
    )

    # Rejection sampling (Bias-Vermeidung)
    valid    <- uint32[uint32 < limit]
    indices  <- (valid %% range_size) + min_val
    result   <- c(result, indices)
    attempts <- attempts + n_words
  }

  if (length(result) < n) {
    cli::cli_warn("/dev/urandom: nicht genug Werte erzeugt ({length(result)}/{n}).")
    return(NULL)
  }

  as.integer(result[seq_len(n)])
}


## 2c. openssl Fallback ---------------------------------------------------------
#' Erzeugt n Integer via openssl::rand_bytes() (CSPRNG, kein echter Zufall).
#'
#' @param n        Anzahl benoedigter Zahlen.
#' @param min_val  Untere Grenze (inklusiv).
#' @param max_val  Obere Grenze (inklusiv).
#' @return Integer-Vektor der Laenge n.
fetch_openssl <- function(n, min_val, max_val) {

  range_size <- max_val - min_val + 1L
  limit      <- floor(2^32 / range_size) * range_size
  result     <- integer(0L)
  max_iter   <- n * 20L
  iter       <- 0L

  while (length(result) < n && iter < max_iter) {
    needed    <- (n - length(result)) * 2L
    raw_bytes <- openssl::rand_bytes(needed * 4L)

    n_words   <- length(raw_bytes) %/% 4L
    raw_mat   <- matrix(as.integer(raw_bytes[seq_len(n_words * 4L)]),
                        nrow = 4L)
    uint32    <- colSums(
      raw_mat *
        matrix(c(16777216L, 65536L, 256L, 1L), nrow = 4L,
               ncol = n_words, byrow = FALSE)
    )
    # Nicht-negativ machen (R kennt kein uint32)
    uint32    <- uint32 %% 2^32
    valid     <- uint32[uint32 < limit]
    indices   <- (valid %% range_size) + min_val
    result    <- c(result, indices)
    iter      <- iter + n_words
  }

  as.integer(result[seq_len(n)])
}


## 2d. Haupt-Dispatcher: waehlt beste verfuegbare Quelle -----------------------
#' Erzeugt n EINDEUTIGE Zeilenindizes in [min_val, max_val].
#'
#' Versucht in Reihenfolge: random.org → /dev/urandom → openssl.
#' Duplikate werden entfernt und mit derselben Quelle nachgefuellt.
#'
#' @param n        Anzahl gewuenschter eindeutiger Indizes.
#' @param min_val  Kleinster erlaubter Index.
#' @param max_val  Groesster erlaubter Index.
#' @param api_key  Optional: random.org API-Key.
#' @return Sortierter Integer-Vektor der Laenge n.
get_true_random_indices <- function(n, min_val, max_val, api_key = "") {

  stopifnot(max_val - min_val + 1L >= n)

  fetch_fns <- list(
    list(name = "random.org",   fn = function(k) fetch_random_org(k, min_val, max_val, api_key)),
    list(name = "/dev/urandom", fn = function(k) fetch_dev_urandom(k, min_val, max_val)),
    list(name = "openssl",      fn = function(k) fetch_openssl(k, min_val, max_val))
  )

  active_source <- NULL
  indices       <- integer(0L)

  for (src in fetch_fns) {
    cli::cli_inform("Versuche Zufallsquelle: {src$name} ...")
    batch <- src$fn(n)
    if (!is.null(batch)) {
      active_source <- src
      indices       <- unique(batch)
      cli::cli_alert_success("Quelle '{src$name}' erfolgreich genutzt.")
      break
    }
  }

  if (is.null(active_source)) {
    cli::cli_abort("Keine Zufallsquelle verfuegbar. Abbruch.")
  }

  # Duplikate auffuellen mit derselben Quelle
  max_refill <- 20L
  refill_cnt <- 0L

  while (length(indices) < n && refill_cnt < max_refill) {
    needed  <- n - length(indices)
    cli::cli_inform("Fuelle {needed} fehlende eindeutige Indizes nach ...")
    extra   <- active_source$fn(needed * 2L)
    if (is.null(extra)) break
    indices <- unique(c(indices, extra))
    refill_cnt <- refill_cnt + 1L
  }

  if (length(indices) < n) {
    cli::cli_abort(
      "Konnte nicht genuegend eindeutige Indizes erzeugen ({length(indices)}/{n})."
    )
  }

  sort(indices[seq_len(n)])
}


# ── 3. CSV einlesen und samplen -----------------------------------------------
#' Liest nur die Stichprobenzeilen aus einer grossen CSV-Datei.
#'
#' Strategie: gesamte Zeilennummern bekannt → gezieltes Einlesen via
#'   readr::read_csv() mit skip/n_max (zeilenweise, speichereffizient).
#'
#' @param path        Pfad zur CSV-Datei.
#' @param row_indices Sortierter Vektor mit einzulesenden Zeilennummern
#'                    (relativ zu Datenzeilen, OHNE Header).
#' @param has_header  Logisch: hat die CSV eine Header-Zeile?
#' @return data.frame mit den ausgewaehlten Zeilen.
read_sampled_rows <- function(path, row_indices, has_header = TRUE) {

  stopifnot(file.exists(path))
  row_indices <- sort(unique(row_indices))

  cli::cli_inform("Lese {length(row_indices)} Zeilen aus '{path}' ...")

  # Header separat einlesen
  if (has_header) {
    header_df <- readr::read_csv(path, n_max = 0L, show_col_types = FALSE)
    col_names <- names(header_df)
  } else {
    col_names <- TRUE   # readr generiert V1, V2, ...
  }

  # Zeilen blockweise einlesen (effizient: nur gewuenschte Bloecke)
  chunks <- list()
  prev   <- 0L

  for (i in seq_along(row_indices)) {
    target <- row_indices[i]
    skip_n <- target - prev - 1L          # Zeilen ueberspringen

    # Beim ersten Block: Header ggf. schon eingelesen
    skip_total <- if (has_header) target else target - 1L

    chunk <- readr::read_csv(
      path,
      col_names  = col_names,
      skip       = skip_total,
      n_max      = 1L,
      show_col_types = FALSE
    )
    chunks[[i]] <- chunk
    prev <- target
  }

  result <- do.call(rbind, chunks)
  cli::cli_alert_success("{nrow(result)} Zeilen erfolgreich eingelesen.")
  result
}


# ── 4. Alternativer Ansatz: gesamte CSV laden (RAM-intensiv) -----------------
#' Fuer Systeme mit genug RAM: alles laden, dann samplen.
#' Schneller als zeilenweises Lesen, benoetigt aber ~2-4 GB RAM.
#'
#' @param path        Pfad zur CSV-Datei.
#' @param row_indices Vektor mit einzulesenden Zeilennummern (1-basiert).
#' @param has_header  Logisch: hat die CSV eine Header-Zeile?
#' @return data.frame mit den ausgewaehlten Zeilen.
read_full_then_sample <- function(path, row_indices, has_header = TRUE) {

  cli::cli_inform("Lade vollstaendige CSV (RAM-intensiv) ...")
  full <- readr::read_csv(path, show_col_types = FALSE,
                          col_names = has_header)
  cli::cli_alert_success("CSV geladen: {nrow(full)} Zeilen, {ncol(full)} Spalten.")
  full[row_indices, ]
}


# ── 5. Hauptprogramm ----------------------------------------------------------
main <- function() {

  cli::cli_h1("True-Random CSV Sampler")

  # Schritt 1: Eindeutige Zeilenindizes erzeugen
  cli::cli_h2("Schritt 1/3 – Zufaellige Indizes erzeugen")
  indices <- get_true_random_indices(
    n         = N_SAMPLE,
    min_val   = 1L,
    max_val   = N_TOTAL,
    api_key   = RANDOM_ORG_API_KEY
  )

  cli::cli_inform(
    c("i" = "Erste 10 Indizes: {paste(head(indices, 10), collapse = ', ')}",
      "i" = "Letzte 10 Indizes: {paste(tail(indices, 10), collapse = ', ')}")
  )

  # Schritt 2: Daten einlesen
  cli::cli_h2("Schritt 2/3 – Daten einlesen")

  # Waehle Methode: "stream" (speicherschonend) oder "full" (schneller bei RAM)
  method <- if (N_TOTAL > 500000L) "full" else "stream"
  cli::cli_inform("Methode: {method}")

  sample_df <- if (method == "full") {
    read_full_then_sample(CSV_PATH, indices, HAS_HEADER)
  } else {
    read_sampled_rows(CSV_PATH, indices, HAS_HEADER)
  }

  # Schritt 3: Ergebnis speichern
  cli::cli_h2("Schritt 3/3 – Ergebnis speichern")
  readr::write_csv(sample_df, OUTPUT_PATH)
  cli::cli_alert_success("Stichprobe gespeichert: '{OUTPUT_PATH}'")
  cli::cli_inform("{nrow(sample_df)} Zeilen, {ncol(sample_df)} Spalten.")

  invisible(sample_df)
}


# ── 6. Unit-Tests -------------------------------------------------------------
run_tests <- function() {

  cli::cli_h1("Unit-Tests")
  pass <- 0L; fail <- 0L

  test <- function(desc, expr) {
    result <- tryCatch(expr, error = function(e) FALSE)
    if (isTRUE(result)) {
      cli::cli_alert_success("PASS: {desc}")
      pass <<- pass + 1L
    } else {
      cli::cli_alert_danger("FAIL: {desc}")
      fail <<- fail + 1L
    }
  }

  # openssl-Fallback testen (immer verfuegbar)
  nums <- fetch_openssl(100L, 1L, 1000L)
  test("fetch_openssl: Laenge korrekt",        length(nums) == 100L)
  test("fetch_openssl: Bereich korrekt",        all(nums >= 1L & nums <= 1000L))
  test("fetch_openssl: Integer-Typ",            is.integer(nums))

  # Dispatcher testen
  idx <- get_true_random_indices(50L, 1L, 1000L)
  test("Dispatcher: Laenge korrekt",            length(idx) == 50L)
  test("Dispatcher: Eindeutig",                 length(unique(idx)) == 50L)
  test("Dispatcher: Sortiert",                  all(diff(idx) > 0L))
  test("Dispatcher: Bereich [1, 1000]",         all(idx >= 1L & idx <= 1000L))

  # Fehlerfall: n > Bereich
  err_caught <- tryCatch({
    get_true_random_indices(100L, 1L, 50L); FALSE
  }, error = function(e) TRUE)
  test("Fehler wenn n > Bereichsgroesse",       err_caught)

  cli::cli_inform("\nErgebnis: {pass} bestanden, {fail} fehlgeschlagen.")
}


# ── 7. Ausfuehren -------------------------------------------------------------
# Tests laufen lassen:
run_tests()

# Hauptprogramm starten (Kommentar entfernen, wenn CSV vorhanden):
# main()

## freMTPL2freq
CSV_PATH = "C:\\Users\\....\\Desktop\\FREELANCE\\Versicherung\\freMTPLfreq_sev.csv"
HAS_HEADER <- TRUE
run_tests()
main()

## freMTPL2sev
CSV_PATH = "C:\\Users\\....\\Desktop\\FREELANCE\\Versicherung\\r\\freMTPL2sev.csv"
HAS_HEADER <- TRUE
run_tests()
main()
