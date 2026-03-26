# 05_city_scoring.R
# Purpose: Score candidate cities for relocation.

library(tidyverse)
library(readr)
library(lubridate)

processed_dir <- "data/processed"
output_dir <- "output"
figures_dir <- "figures"

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)

leases <- read_csv(
  file.path(processed_dir, "leases_clean.csv"),
  show_col_types = FALSE
)

price <- read_csv(
  file.path(processed_dir, "price_availability_clean.csv"),
  show_col_types = FALSE
)

unemp <- read_csv(
  file.path(processed_dir, "unemployment_data_combined.csv"),
  show_col_types = FALSE
) %>%
  mutate(date = as.Date(date))

# ----------------------------
# Candidate cities
# ----------------------------
candidate_cities <- c("Atlanta", "Austin", "Miami", "Nashville")

# ----------------------------
# Helper: safe min-max scaling
# ----------------------------
min_max_scale <- function(x, reverse = FALSE) {
  rng <- max(x, na.rm = TRUE) - min(x, na.rm = TRUE)
  
  if (is.na(rng) || rng == 0) {
    scaled <- rep(0.5, length(x))
  } else {
    scaled <- (x - min(x, na.rm = TRUE)) / rng
  }
  
  if (reverse) 1 - scaled else scaled
}

# ----------------------------
# Office supply: total leased sf in large urban leases
# ----------------------------
office_supply <- leases %>%
  filter(
    city %in% candidate_cities,
    cbd_suburban == "CBD",
    leased_sf >= 40000
  ) %>%
  group_by(city, state) %>%
  summarise(
    office_supply_sf = sum(leased_sf, na.rm = TRUE),
    n_large_leases = n(),
    .groups = "drop"
  )

# ----------------------------
# Tech presence: count of tech-industry leases
# ----------------------------
tech_presence <- leases %>%
  filter(
    city %in% candidate_cities,
    internal_industry == "Technology, Advertising, Media, and Information"
  ) %>%
  group_by(city, state) %>%
  summarise(
    tech_lease_count = n(),
    .groups = "drop"
  )

# ----------------------------
# Rent: average observed rent by city
# ----------------------------
city_rent <- leases %>%
  filter(
    city %in% candidate_cities,
    !is.na(overall_rent),
    overall_rent > 0
  ) %>%
  group_by(city, state) %>%
  summarise(
    avg_overall_rent = mean(overall_rent, na.rm = TRUE),
    .groups = "drop"
  )

# ----------------------------
# Unemployment: latest state unemployment rate
# Map city -> state abbreviation to match leases data
# ----------------------------
latest_unemployment <- unemp %>%
  group_by(state) %>%
  filter(date == max(date, na.rm = TRUE)) %>%
  ungroup()

state_lookup <- tibble(
  state = c("Georgia", "Texas", "Florida", "Tennessee"),
  state_abbrev = c("GA", "TX", "FL", "TN")
)

city_unemployment <- tibble(
  city = c("Atlanta", "Austin", "Miami", "Nashville"),
  state = c("Georgia", "Texas", "Florida", "Tennessee")
) %>%
  left_join(latest_unemployment, by = "state") %>%
  left_join(state_lookup, by = "state") %>%
  transmute(
    city = city,
    state = state_abbrev,
    unemployment_rate = unemployment_rate
  )

# ----------------------------
# Combine all metrics into a composite score
# ----------------------------
city_scores <- office_supply %>%
  left_join(tech_presence, by = c("city", "state")) %>%
  left_join(city_rent, by = c("city", "state")) %>%
  left_join(city_unemployment, by = c("city", "state")) %>%
  mutate(
    tech_lease_count = replace_na(tech_lease_count, 0),
    tech_score = min_max_scale(tech_lease_count),
    rent_score = min_max_scale(avg_overall_rent, reverse = TRUE),
    unemp_score = min_max_scale(unemployment_rate, reverse = TRUE),
    supply_score = min_max_scale(office_supply_sf),
    composite_score =
      0.40 * tech_score +
      0.20 * rent_score +
      0.20 * unemp_score +
      0.20 * supply_score
  ) %>%
  arrange(desc(composite_score))

# ----------------------------
# Save scores
# ----------------------------
write_csv(city_scores, file.path(output_dir, "city_scores.csv"))

# ----------------------------
# Visualize scores
# ----------------------------
plot_scores <- ggplot(
  city_scores,
  aes(x = reorder(city, composite_score), y = composite_score)
) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Composite Relocation Scores for Candidate Cities",
    x = "City",
    y = "Composite Score"
  ) +
  theme_minimal(base_size = 12)

ggsave(
  file.path(figures_dir, "city_composite_scores.png"),
  plot_scores,
  width = 8,
  height = 5,
  dpi = 300
)

message("City scoring complete.")