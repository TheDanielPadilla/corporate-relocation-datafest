
library(rvest)
library(tidyverse)
library(readr)

base_url <- "https://www.places2play.org"

# state list
by_state <- read_html(paste0(base_url, "/bystate"))

state_links <- by_state |>
  html_elements("a") |>
  html_attr("href") |>
  na.omit() |>
  unique() |>
  keep(~ str_detect(.x, "^/state/"))

states_tbl <- tibble(
  url = paste0(base_url, state_links),
  slug = str_remove(state_links, "^/state/")
)

# helper: parse one HTML page worth of In/Out pairs
extract_pairs <- function(page) {
  txt <- page |> html_text2()
  
  m <- str_match_all(txt, "In:\\s*(\\d+)\\s+Out:\\s*(\\d+)")[[1]]
  
  if (nrow(m) == 0) {
    return(tibble(indoor = integer(), outdoor = integer()))
  }
  
  tibble(
    indoor = as.integer(m[, 2]),
    outdoor = as.integer(m[, 3])
  )
}

# helper: read total results from header like "Results 0 - 50 of 839"
extract_total_places <- function(page) {
  txt <- page |> html_text2()
  
  m <- str_match(txt, "Results\\s+\\d+\\s*-\\s*\\d+\\s+of\\s+(\\d+)")
  total <- suppressWarnings(as.integer(m[, 2]))
  
  if (is.na(total)) 0L else total
}

scrape_state <- function(url, slug, pause = 0.5) {
  message("Scraping: ", slug)
  
  first_page <- read_html(url)
  
  total_places <- extract_total_places(first_page)
  
  # if no results
  if (total_places == 0) {
    return(tibble(
      State = str_to_title(str_replace_all(slug, "-", " ")),
      Places = 0L,
      Indoor = 0L,
      Outdoor = 0L,
      `Total Courts` = 0L
    ))
  }
  
  # Places2Play appears to show 50 results per page
  offsets <- seq(0, total_places - 1, by = 50)
  
  # try common pagination patterns; keep the one that works for the site version
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
    State = str_to_title(str_replace_all(slug, "-", " ")),
    Places = total_places,
    Indoor = sum(all_pairs$indoor, na.rm = TRUE),
    Outdoor = sum(all_pairs$outdoor, na.rm = TRUE),
    `Total Courts` = sum(all_pairs$indoor + all_pairs$outdoor, na.rm = TRUE)
  )
}

courts_tbl <- pmap_dfr(
  list(states_tbl$url, states_tbl$slug),
  scrape_state
)

abbr_tbl <- tibble(
  State = c(
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

final_tbl <- courts_tbl |>
  left_join(abbr_tbl, by = "State") |>
  mutate(
    State = case_when(
      State == "District Of Columbia" ~ "District of Columbia",
      TRUE ~ State
    )
  ) |>
  arrange(State)

print(final_tbl, n = Inf)

summarise(
  final_tbl,
  places = sum(Places),
  indoor = sum(Indoor),
  outdoor = sum(Outdoor),
  total = sum(`Total Courts`)
)

#Optional: Save final table
write_csv(final_tbl, "data/processed/pickleball_places2play_by_state.csv")