# 03_state_comparison_visuals.R
# Purpose: Compare office rent and pickleball court availability across candidate states.

library(tidyverse)
library(readr)

processed_dir <- "data/processed"
figures_dir <- "figures"
output_dir <- "output"

if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ----------------------------
# Load cleaned data
# ----------------------------
leases <- read_csv(
  file.path(processed_dir, "leases_clean.csv"),
  show_col_types = FALSE
)

pickleball <- read_csv(
  file.path(processed_dir, "pickleball_courts_clean.csv"),
  show_col_types = FALSE
)

# ----------------------------
# Define relocation filters
# ----------------------------
western_states <- c("CA", "NV", "OR", "WA")

target_industry <- "Technology, Advertising, Media, and Information"

# ----------------------------
# Candidate leases excluding California
# ----------------------------
candidate_leases <- leases %>%
  filter(
    !state %in% western_states,
    cbd_suburban == "CBD",
    internal_industry == target_industry,
    leased_sf >= 40000,
    overall_rent > 0
  ) %>%
  mutate(
    avg_rent_building = overall_rent
  )

# ----------------------------
# Candidate leases including California benchmark
# ----------------------------
candidate_leases_with_ca <- leases %>%
  filter(
    !state %in% c("NV", "OR", "WA"),
    cbd_suburban == "CBD",
    internal_industry == target_industry,
    leased_sf >= 40000,
    overall_rent > 0
  ) %>%
  mutate(
    avg_rent_building = overall_rent
  )

# ----------------------------
# State-level summaries
# ----------------------------
state_summary_excluding_ca <- candidate_leases %>%
  group_by(state) %>%
  summarise(
    avg_state_rent = mean(avg_rent_building, na.rm = TRUE),
    n_leases = n(),
    .groups = "drop"
  ) %>%
  left_join(
    pickleball %>% select(state, total_courts),
    by = "state"
  ) %>%
  arrange(avg_state_rent)

state_summary_including_ca <- candidate_leases_with_ca %>%
  group_by(state) %>%
  summarise(
    avg_state_rent = mean(avg_rent_building, na.rm = TRUE),
    n_leases = n(),
    .groups = "drop"
  ) %>%
  left_join(
    pickleball %>% select(state, total_courts),
    by = "state"
  ) %>%
  arrange(avg_state_rent)

write_csv(
  state_summary_excluding_ca,
  file.path(output_dir, "state_summary_excluding_california.csv")
)

write_csv(
  state_summary_including_ca,
  file.path(output_dir, "state_summary_including_california.csv")
)

# ----------------------------
# Helper for dual-axis plotting
# ----------------------------
make_dual_axis_plot <- function(df, title_text) {
  scale_factor <- max(df$avg_state_rent, na.rm = TRUE) / max(df$total_courts, na.rm = TRUE)

  df_long <- df %>%
    mutate(total_courts_scaled = total_courts * scale_factor) %>%
    select(state, avg_state_rent, total_courts_scaled) %>%
    pivot_longer(
      cols = c(avg_state_rent, total_courts_scaled),
      names_to = "metric",
      values_to = "value"
    )

  ggplot(df_long, aes(x = state, y = value, fill = metric)) +
    geom_col(position = "dodge") +
    scale_fill_manual(
      values = c(
        avg_state_rent = "skyblue",
        total_courts_scaled = "orange"
      ),
      labels = c(
        avg_state_rent = "Average Rent",
        total_courts_scaled = "Total Courts"
      )
    ) +
    scale_y_continuous(
      name = "Average Rent ($ per Sq. Ft.)",
      sec.axis = sec_axis(~ . / scale_factor, name = "Number of Pickleball Courts")
    ) +
    labs(
      title = title_text,
      x = "State",
      fill = "Metric"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      axis.title.y.left = element_text(size = 12),
      axis.title.y.right = element_text(size = 12)
    )
}

# ----------------------------
# Create figures
# ----------------------------
plot_excluding_ca <- make_dual_axis_plot(
  state_summary_excluding_ca,
  "Average Rent and Pickleball Courts by Candidate State"
)

plot_including_ca <- make_dual_axis_plot(
  state_summary_including_ca,
  "Average Rent and Pickleball Courts by State (Including California)"
)

ggsave(
  file.path(figures_dir, "state_rent_vs_pickleball.png"),
  plot_excluding_ca,
  width = 10,
  height = 6,
  dpi = 300
)

ggsave(
  file.path(figures_dir, "state_rent_vs_pickleball_including_california.png"),
  plot_including_ca,
  width = 10,
  height = 6,
  dpi = 300
)

message("State comparison visuals complete.")