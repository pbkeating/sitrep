#' Rates and Ratios
#'
#' Calculate attack rate, case fatality rate, and mortality rate
#'
#' @param cases,deaths number of cases or deaths in a population. For `_df`
#'   functions, this can be the name of a logical column OR an evaluated
#'   logical expression (see examples).
#' @param population the number of individuals in the population.
#' @param conf_level a number representing the confidence level for which to
#' calculate the confidence interval. Defaults to 0.95, representinc 95%
#' confidence interval.
#' @param multiplier The base by which to multiply the output:
#'  - `multiplier = 1`: ratio between 0 and 1
#'  - `multiplier = 100`: proportion
#'  - `multiplier = 10^4`: x per 10,000 people
#' @param mergeCI Whether or not to put the confidence intervals in one column (default is FALSE)
#' @param digits if `mergeCI = TRUE`, this determines how many digits are printed
#' @export
#' @rdname attack_rate
#' @examples
#' # Attack rates can be calculated with just two numbers
#' print(ar <- attack_rate(10, 50), digits = 4) # 20% attack rate
#'
#' # print them inline using `fmt_ci_df()`
#' fmt_ci_df(ar)
#'
#' # Alternatively, if you want one column for the CI, use `mergeCI = TRUE`
#' attack_rate(10, 50, mergeCI = TRUE, digits = 2) # 20% attack rate
#'
#' print(cfr <- case_fatality_rate(1, 100), digits = 2) # CFR of 1%
#' fmt_ci_df(cfr)
#'
#' # using a data frame
#' if (require("outbreaks")) {
#'
#'   e <- outbreaks::ebola_sim$linelist
#'   case_fatality_rate_df(e, 
#'                         outcome == "Death", 
#'                         group = gender, 
#'                         add_total = TRUE,
#'                         mergeCI = TRUE)
#'
#' }
attack_rate <- function(cases, population, conf_level = 0.95,
                        multiplier = 100, mergeCI = FALSE, digits = 2) {
  res <- proportion(cases, population, multiplier = multiplier, conf_level = conf_level)
  colnames(res) <- c("cases", "population", "ar", "lower", "upper")
  if (mergeCI == TRUE) {
    res <- merge_ci_df(res, digits = digits)
  }
  res
}

#' @rdname attack_rate
#' @export
case_fatality_rate <- function(deaths, population, conf_level = 0.95,
                               multiplier = 100, mergeCI = FALSE, digits = 2) {
  res <- proportion(deaths, population, multiplier = multiplier, conf_level = conf_level)
  colnames(res) <- c("deaths", "population", "cfr", "lower", "upper")
  if (mergeCI == TRUE) {
    res <- merge_ci_df(res, digits = digits)
  }
  res
}

#' @rdname attack_rate
#' @export
case_fatality_rate_df <- function(x, deaths, group = NULL, conf_level = 0.95,
                                  multiplier = 100, mergeCI = FALSE, digits = 2,
                                  add_total = FALSE) {

  qdeath <- rlang::enquo(deaths)
  qgroup <- rlang::enquo(group)
  wants_grouping <- !is.null(rlang::get_expr(qgroup))


  # Group the data if needed
  if (wants_grouping) {
    x <- dplyr::group_by(x, !!qgroup)
  }

  # Summarise the data. Luckily, deaths can be either a column or a logical
  # expression to evaluate :)
  # This creates a list column for the case fatality rate based on the
  # calculated deaths and population before... so this means that 
  # THE ORDER OF THE STATEMENTS MATTER
  res <- dplyr::summarise(x,
                          deaths := sum(!!qdeath, na.rm = TRUE), 
                          population := dplyr::n(),
                          cfr := list(case_fatality_rate(.data$deaths, 
                                                         .data$population, 
                                                         conf_level, 
                                                         multiplier, 
                                                         mergeCI, 
                                                         digits)[-(1:2)]
                          ))

  # unnesting the list column
  res <- tidyr::unnest(res, .data$cfr)

  # adding the total if there was grouping 
  if (add_total && wants_grouping) {
    tot <- case_fatality_rate(sum(res$deaths, na.rm = TRUE),
                              sum(res$population, na.rm = TRUE),
                              conf_level,
                              multiplier,
                              mergeCI,
                              digits)
    res <- tibble::add_row(res, 
                           !!qgroup := "Total",
                           deaths = tot$deaths,
                           population = tot$population,
                           cfr = tot$cfr
                          )
    # merge CI gives different numbers of columns, this accounts for that.
    if (mergeCI) {
      res$ci[nrow(res)] <- tot$ci
    } else {
      res$lower[nrow(res)] <- tot$lower
      res$upper[nrow(res)] <- tot$upper
    }
  }
  res
}

#' @rdname attack_rate
#' @export
mortality_rate <- function(deaths, population, conf_level = 0.95,
                           multiplier = 10^4, mergeCI = FALSE, digits = 2) {
  stopifnot(is.numeric(multiplier), length(multiplier) == 1L, multiplier > 0)
  # as in here https://www.cdc.gov/ophss/csels/dsepd/ss1978/lesson3/section3.html
  res <- proportion(deaths, population, conf_level = conf_level, multiplier = multiplier)
  est_label <- paste0("mortality per ", scales::number(multiplier))
  colnames(res) <- c("deaths", "population", est_label, "lower", "upper")
  if (mergeCI == TRUE) {
    res <- merge_ci_df(res, digits = digits)
  }
  res
}

proportion <- function(x, n, conf_level = 0.95, multiplier = 100) {
  stopifnot(is.numeric(conf_level), conf_level >= 0, conf_level <= 1)
  n <- if (length(n) < length(x)) rep(n, length(x)) else n
  missing_data <- is.na(x) | is.na(x)
  x[missing_data] <- 100
  n[missing_data] <- 100
  res <- binom::binom.wilson(x, n, conf.level = conf_level)
  res <- res[, c("x", "n", "mean", "lower", "upper")]
  res[missing_data, ] <- NA_real_
  colnames(res) <- c("x", "n", "prop", "lower", "upper")
  res$prop  <- (x / n) * multiplier
  res$lower <- res$lower * multiplier
  res$upper <- res$upper * multiplier
  res
}

