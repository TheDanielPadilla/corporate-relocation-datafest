# 04_unemployment_rent_forecast.R
# Purpose: Forecast unemployment and office rent trends for candidate states.

library(tidyverse)
library(readr)
library(lubridate)
library(forecast)
library(janitor)

raw_dir <- "data/raw"
processed_dir <- "data/processed"
figures_dir <- "figures"
output_dir <- "output"

if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ----------------------------
# Load cleaned rent data
# ----------------------------
price <- read_csv(
  file.path(processed_dir, "price_availability_clean.csv"),
  show_col_types = FALSE
)

market_state <- read_csv(
  file.path(processed_dir, "market_state_lookup.csv"),
  show_col_types = FALSE
)

# ----------------------------
# Load multiple FRED unemployment files
# ----------------------------
fred_files <- tribble(
  ~file,       ~state,              ~value_col,
  "CAUR.csv",  "California",        "CAUR",
  "GAUR.csv",  "Georgia",           "GAUR",
  "FLUR.csv",  "Florida",           "FLUR",
  "TXUR.csv",  "Texas",             "TXUR",
  "NCUR.csv",  "North Carolina",    "NCUR",
  "TNUR.csv",  "Tennessee",         "TNUR"
)

read_fred_state <- function(file, state, value_col) {
  read_csv(file.path(raw_dir, file), show_col_types = FALSE) %>%
    clean_names() %>%
    transmute(
      date = as.Date(observation_date),
      state = state,
      unemployment_rate = as.numeric(.data[[tolower(value_col)]])
    )
}

unemp <- purrr::pmap_dfr(
  fred_files,
  \(file, state, value_col) read_fred_state(file, state, value_col)
)

write_csv(unemp, file.path(processed_dir, "unemployment_data_combined.csv"))

# ----------------------------
# Build quarterly date for rent series
# ----------------------------
quarter_to_month <- function(q) {
  case_when(
    q == "Q1" ~ 1,
    q == "Q2" ~ 4,
    q == "Q3" ~ 7,
    q == "Q4" ~ 10,
    TRUE ~ NA_real_
  )
}

price_ts <- price %>%
  left_join(market_state, by = "market") %>%
  mutate(
    month = quarter_to_month(as.character(quarter)),
    date = as.Date(sprintf("%d-%02d-01", year, month))
  ) %>%
  filter(!is.na(state), !is.na(overall_rent))

# ----------------------------
# Candidate states
# ----------------------------
candidate_states <- c("Georgia", "Texas", "Florida", "North Carolina", "Tennessee")

# ----------------------------
# Rent series: average by state
# ----------------------------
state_rent <- price_ts %>%
  filter(state %in% c(candidate_states, "California")) %>%
  group_by(date, state) %>%
  summarise(
    avg_overall_rent = mean(overall_rent, na.rm = TRUE),
    .groups = "drop"
  )

ga_rent <- state_rent %>%
  filter(state == "Georgia") %>%
  arrange(date)

ca_rent <- state_rent %>%
  filter(state == "California") %>%
  arrange(date)

candidate_avg_rent <- state_rent %>%
  filter(state %in% candidate_states) %>%
  group_by(date) %>%
  summarise(
    avg_overall_rent = mean(avg_overall_rent, na.rm = TRUE),
    .groups = "drop"
  )

# ----------------------------
# Unemployment series
# ----------------------------
candidate_unemp <- unemp %>%
  filter(state %in% c(candidate_states, "California")) %>%
  arrange(date)

ga_unemp <- candidate_unemp %>%
  filter(state == "Georgia") %>%
  arrange(date)

ca_unemp <- candidate_unemp %>%
  filter(state == "California") %>%
  arrange(date)

candidate_avg_unemp <- candidate_unemp %>%
  filter(state %in% candidate_states) %>%
  group_by(date) %>%
  summarise(
    unemployment_rate = mean(unemployment_rate, na.rm = TRUE),
    .groups = "drop"
  )

# ----------------------------
# Helper: build ts objects
# ----------------------------
make_monthly_ts <- function(df, value_col) {
  start_year <- year(min(df$date))
  start_month <- month(min(df$date))
  ts(df[[value_col]], start = c(start_year, start_month), frequency = 12)
}

make_quarterly_ts <- function(df, value_col) {
  start_year <- year(min(df$date))
  start_quarter <- quarter(min(df$date))
  ts(df[[value_col]], start = c(start_year, start_quarter), frequency = 4)
}

# ----------------------------
# Fit models
# ----------------------------
fit_ga_unemp <- auto.arima(make_monthly_ts(ga_unemp, "unemployment_rate"))
fit_ca_unemp <- auto.arima(make_monthly_ts(ca_unemp, "unemployment_rate"))
fit_candidate_unemp <- auto.arima(make_monthly_ts(candidate_avg_unemp, "unemployment_rate"))

fit_ga_rent <- auto.arima(make_quarterly_ts(ga_rent, "avg_overall_rent"))
fit_ca_rent <- auto.arima(make_quarterly_ts(ca_rent, "avg_overall_rent"))
fit_candidate_rent <- auto.arima(make_quarterly_ts(candidate_avg_rent, "avg_overall_rent"))

fc_ga_unemp <- forecast(fit_ga_unemp, h = 24)
fc_ca_unemp <- forecast(fit_ca_unemp, h = 24)
fc_candidate_unemp <- forecast(fit_candidate_unemp, h = 24)

fc_ga_rent <- forecast(fit_ga_rent, h = 8)
fc_ca_rent <- forecast(fit_ca_rent, h = 8)
fc_candidate_rent <- forecast(fit_candidate_rent, h = 8)

# ----------------------------
# Save forecast output
# ----------------------------
forecast_output <- bind_rows(
  tibble(
    series = "georgia_unemployment",
    period = seq_along(fc_ga_unemp$mean),
    forecast = as.numeric(fc_ga_unemp$mean)
  ),
  tibble(
    series = "california_unemployment",
    period = seq_along(fc_ca_unemp$mean),
    forecast = as.numeric(fc_ca_unemp$mean)
  ),
  tibble(
    series = "candidate_states_unemployment",
    period = seq_along(fc_candidate_unemp$mean),
    forecast = as.numeric(fc_candidate_unemp$mean)
  ),
  tibble(
    series = "georgia_rent",
    period = seq_along(fc_ga_rent$mean),
    forecast = as.numeric(fc_ga_rent$mean)
  ),
  tibble(
    series = "california_rent",
    period = seq_along(fc_ca_rent$mean),
    forecast = as.numeric(fc_ca_rent$mean)
  ),
  tibble(
    series = "candidate_states_rent",
    period = seq_along(fc_candidate_rent$mean),
    forecast = as.numeric(fc_candidate_rent$mean)
  )
)

write_csv(forecast_output, file.path(output_dir, "forecast_output.csv"))

# ----------------------------
# Plot helpers
# ----------------------------
plot_forecast_monthly <- function(history_df, value_col, fc_obj, title, ylab) {
  future_dates <- seq(
    max(history_df$date) %m+% months(1),
    by = "1 month",
    length.out = length(fc_obj$mean)
  )
  
  forecast_df <- tibble(
    date = future_dates,
    mean = as.numeric(fc_obj$mean),
    lower_80 = as.numeric(fc_obj$lower[, 1]),
    upper_80 = as.numeric(fc_obj$upper[, 1]),
    lower_95 = as.numeric(fc_obj$lower[, 2]),
    upper_95 = as.numeric(fc_obj$upper[, 2])
  )
  
  ggplot() +
    geom_line(data = history_df, aes(x = date, y = .data[[value_col]]), linewidth = 0.8) +
    geom_ribbon(data = forecast_df, aes(x = date, ymin = lower_95, ymax = upper_95), alpha = 0.15) +
    geom_ribbon(data = forecast_df, aes(x = date, ymin = lower_80, ymax = upper_80), alpha = 0.30) +
    geom_line(data = forecast_df, aes(x = date, y = mean), linewidth = 1) +
    labs(title = title, x = "Date", y = ylab) +
    theme_minimal(base_size = 12)
}

plot_forecast_quarterly <- function(history_df, value_col, fc_obj, title, ylab) {
  future_dates <- seq(
    max(history_df$date) %m+% months(3),
    by = "3 months",
    length.out = length(fc_obj$mean)
  )
  
  forecast_df <- tibble(
    date = future_dates,
    mean = as.numeric(fc_obj$mean),
    lower_80 = as.numeric(fc_obj$lower[, 1]),
    upper_80 = as.numeric(fc_obj$upper[, 1]),
    lower_95 = as.numeric(fc_obj$lower[, 2]),
    upper_95 = as.numeric(fc_obj$upper[, 2])
  )
  
  ggplot() +
    geom_line(data = history_df, aes(x = date, y = .data[[value_col]]), linewidth = 0.8) +
    geom_ribbon(data = forecast_df, aes(x = date, ymin = lower_95, ymax = upper_95), alpha = 0.15) +
    geom_ribbon(data = forecast_df, aes(x = date, ymin = lower_80, ymax = upper_80), alpha = 0.30) +
    geom_line(data = forecast_df, aes(x = date, y = mean), linewidth = 1) +
    labs(title = title, x = "Date", y = ylab) +
    theme_minimal(base_size = 12)
}

# ----------------------------
# Make plots
# ----------------------------
p1 <- plot_forecast_monthly(
  ga_unemp,
  "unemployment_rate",
  fc_ga_unemp,
  "Georgia Unemployment Forecast",
  "Unemployment Rate (%)"
)

p2 <- plot_forecast_monthly(
  ca_unemp,
  "unemployment_rate",
  fc_ca_unemp,
  "California Unemployment Forecast",
  "Unemployment Rate (%)"
)

p3 <- plot_forecast_monthly(
  candidate_avg_unemp,
  "unemployment_rate",
  fc_candidate_unemp,
  "Average Unemployment Forecast: Candidate States",
  "Unemployment Rate (%)"
)

p4 <- plot_forecast_quarterly(
  ga_rent,
  "avg_overall_rent",
  fc_ga_rent,
  "Georgia / Atlanta Market Rent Forecast",
  "Average Office Rent"
)

p5 <- plot_forecast_quarterly(
  ca_rent,
  "avg_overall_rent",
  fc_ca_rent,
  "California Market Rent Forecast",
  "Average Office Rent"
)

p6 <- plot_forecast_quarterly(
  candidate_avg_rent,
  "avg_overall_rent",
  fc_candidate_rent,
  "Average Rent Forecast: Candidate States",
  "Average Office Rent"
)

ggsave(file.path(figures_dir, "unemployment_forecast_georgia.png"), p1, width = 8, height = 5, dpi = 300)
ggsave(file.path(figures_dir, "unemployment_forecast_california.png"), p2, width = 8, height = 5, dpi = 300)
ggsave(file.path(figures_dir, "unemployment_forecast_candidate_states.png"), p3, width = 8, height = 5, dpi = 300)

ggsave(file.path(figures_dir, "rent_forecast_georgia.png"), p4, width = 8, height = 5, dpi = 300)
ggsave(file.path(figures_dir, "rent_forecast_california.png"), p5, width = 8, height = 5, dpi = 300)
ggsave(file.path(figures_dir, "rent_forecast_candidate_states.png"), p6, width = 8, height = 5, dpi = 300)

message("Forecasting complete.")