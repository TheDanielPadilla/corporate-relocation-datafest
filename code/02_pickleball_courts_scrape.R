# 02_pickleball_courts_scrape.R
# Purpose: Scrape and clean pickleball court counts by state from Places2Play.

library(rvest)
library(tidyverse)
library(readr)

base_url <- "https://www.places2play.org"
processed_dir <- "data/processed"

if (!dir.exists(processed_dir)) dir.create(processed_dir, recursive = TRUE)

# ----------------------------
# Build state list
# ----------------------------
by_state <- read_html(paste0(base_url, "/bystate"))

state_links <- by_state %>%
  html_elements("a") %>%
  html_attr("href") %>%
  na.omit() %>%
  unique() %>%
  keep(~ str_detect(.x, "^/state/"))

states_tbl <- tibble(
  url = paste0(base_url, state_links),
  slug = str_remove(state_links, "^/state/")
)

# ----------------------------
# Helper: extract indoor/outdoor pairs from one page
# ----------------------------
extract_pairs <- function(page) {
  txt <- page %>% html_text2()
  
  m <- str_match_all(txt, "In:\\s*(\\d+)\\s+Out:\\s*(\\d+)")[[1]]
  
  if (nrow(m) == 0) {
    return(tibble(indoor = integer(), outdoor = integer()))
  }
  
  tibble(
    indoor = as.integer(m[, 2]),
    outdoor = as.integer(m[, 3])
  )
}

# ----------------------------
# Helper: read total results from page header
# Example: "Results 0 - 50 of 839"
# ----------------------------
extract_total_places <- function(page) {
  txt <- page %>% html_text2()
  
  m <- str_match(txt, "Results\\s+\\d+\\s*-\\s*\\d+\\s+of\\s+(\\d+)")
  total <- suppressWarnings(as.integer(m[, 2]))
  
  if (is.na(total)) 0L else total
}

# ----------------------------
# Scrape one state
# ----------------------------
scrape_state <- function(url, slug, pause = 0.5) {
  message("Scraping: ", slug)
  
  first_page <- read_html(url)
  total_places <- extract_total_places(first_page)
  
  state_name <- str_to_title(str_replace_all(slug, "-", " "))
  
  if (total_places == 0) {
    return(tibble(
      state_name = state_name,
      places = 0L,
      indoor = 0L,
      outdoor = 0L,
      total_courts = 0L
    ))
  }
  
  offsets <- seq(0, total_places - 1, by = 50)
  
  page_urls <- if (length(offsets) == 1) {
    url
  } else {
    paste0(url, "?start=", offsets)
  }
  
  all_pairs <- map_dfr(page_urls, function(u) {
    Sys.sleep(pause)
    page <- read_html(u)
    extract_pairs(page)
  })
  
  tibble(
    state_name = state_name,
    places = total_places,
    indoor = sum(all_pairs$indoor, na.rm = TRUE),
    outdoor = sum(all_pairs$outdoor, na.rm = TRUE),
    total_courts = sum(all_pairs$indoor + all_pairs$outdoor, na.rm = TRUE)
  )
}

# ----------------------------
# Scrape all states
# ----------------------------
courts_tbl <- pmap_dfr(
  list(states_tbl$url, states_tbl$slug),
  scrape_state
)

# ----------------------------
# Add state abbreviations
# ----------------------------
abbr_tbl <- tibble(
  state_name = c(
    state.name,
    "District Of Columbia",
    "American Samoa",
    "Guam",
    "Northern Mariana Islands",
    "Puerto Rico",
    "United States Minor Outlying Islands",
    "Virgin Islands"
  ),
  state = c(
    state.abb,
    "DC", "AS", "GU", "MP", "PR", "UM", "VI"
  )
)

pickleball_courts_clean <- courts_tbl %>%
  left_join(abbr_tbl, by = "state_name") %>%
  mutate(
    state_name = case_when(
      state_name == "District Of Columbia" ~ "District of Columbia",
      TRUE ~ state_name
    )
  ) %>%
  arrange(state_name)

print(pickleball_courts_clean, n = Inf)

pickleball_totals <- pickleball_courts_clean %>%
  summarise(
    places = sum(places, na.rm = TRUE),
    indoor = sum(indoor, na.rm = TRUE),
    outdoor = sum(outdoor, na.rm = TRUE),
    total_courts = sum(total_courts, na.rm = TRUE)
  )

print(pickleball_totals)

# ----------------------------
# Save cleaned output
# ----------------------------
write_csv(
  pickleball_courts_clean,
  file.path(processed_dir, "pickleball_courts_clean.csv")
)

message("Pickleball scrape and cleaning complete.")