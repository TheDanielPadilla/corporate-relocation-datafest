# 01_load_and_clean_data.R
# Purpose: Load and clean rent / lease data for the relocation project.

library(tidyverse)
library(janitor)
library(readr)
library(stringr)

raw_dir <- "data/raw"
processed_dir <- "data/processed"

if (!dir.exists(processed_dir)) dir.create(processed_dir, recursive = TRUE)

# ----------------------------
# Load rent / price data
# ----------------------------
price <- read_csv(
  file.path(raw_dir, "Price_and_Availability_Data.csv"),
  show_col_types = FALSE
) %>%
  clean_names() %>%
  mutate(
    market = str_squish(str_trim(market)),
    quarter = factor(quarter, levels = c("Q1", "Q2", "Q3", "Q4")),
    year = as.integer(year),
    period = paste(year, quarter, sep = "-")
  )

price_clean <- price %>%
  filter(!is.na(overall_rent), overall_rent > 0) %>%
  select(
    year, quarter, period, market, internal_class,
    rba, available_space, availability_proportion,
    overall_rent, direct_overall_rent, sublet_overall_rent,
    leasing
  ) %>%
  arrange(market, year, quarter)

write_csv(price_clean, file.path(processed_dir, "price_availability_clean.csv"))

# ----------------------------
# Load lease-level data
# ----------------------------
leases <- read_csv(
  file.path(raw_dir, "Leases.csv"),
  show_col_types = FALSE
) %>%
  clean_names() %>%
  mutate(
    market = str_squish(str_trim(market)),
    city = str_squish(str_trim(city)),
    state = str_to_upper(str_trim(state)),
    cbd_suburban = str_squish(str_trim(cbd_suburban)),
    internal_industry = str_squish(str_trim(internal_industry)),
    internal_class = str_squish(str_trim(internal_class)),
    leased_sf = as.numeric(leased_sf),
    year = as.integer(year),
    quarter = factor(quarter, levels = c("Q1", "Q2", "Q3", "Q4"))
  )

leases_clean <- leases %>%
  filter(!is.na(overall_rent), overall_rent > 0) %>%
  select(
    year, quarter, market, city, state, cbd_suburban,
    building_name, building_id, address,
    leased_sf, company_name, internal_industry,
    transaction_type, internal_class,
    rba, available_space, overall_rent, leasing
  ) %>%
  arrange(state, city, market, year, quarter)

write_csv(leases_clean, file.path(processed_dir, "leases_clean.csv"))

# ----------------------------
# Market-state bridge table
# ----------------------------
market_state_lookup <- leases_clean %>%
  filter(!is.na(market), !is.na(state)) %>%
  distinct(market, state) %>%
  arrange(state, market)

write_csv(market_state_lookup, file.path(processed_dir, "market_state_lookup.csv"))

# ----------------------------
# Eligible large urban leases
# ----------------------------
eligible_large_urban_leases <- leases_clean %>%
  filter(
    !is.na(leased_sf),
    leased_sf >= 40000,
    cbd_suburban == "CBD"
  )

write_csv(
  eligible_large_urban_leases,
  file.path(processed_dir, "eligible_large_urban_leases.csv")
)

# ----------------------------
# Candidate city subset
# ----------------------------
candidate_city_leases <- leases_clean %>%
  filter(city %in% c("Atlanta", "Austin", "Miami", "Nashville"))

write_csv(
  candidate_city_leases,
  file.path(processed_dir, "candidate_city_leases.csv")
)

message("Data cleaning complete.")
