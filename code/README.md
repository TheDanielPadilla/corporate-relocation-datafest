# Code Workflow

This folder contains cleaned R scripts for the portfolio version of the DataFest relocation project.

## Script Order

1. `01_load_and_clean_data.R`  
   Loads and cleans the commercial real estate price and lease datasets, standardizes variable names, and writes processed files to `data/processed/`.

2. `02_pickleball_courts_scrape.R`  
   Scrapes pickleball court counts by state from Places2Play, standardizes the output, and saves a cleaned state-level file for analysis.

3. `03_state_comparison_visuals.R`  
   Merges cleaned lease and pickleball data to compare candidate states on average office rent and pickleball court availability.

4. `04_unemployment_rent_forecast.R`  
   Combines multiple FRED unemployment files, prepares rent time series, and creates forecast plots for unemployment and office rent trends.

5. `05_city_scoring.R`  
   Combines office supply, tech presence, rent, and unemployment metrics into a weighted composite score for candidate cities.

## Workflow Summary

A typical workflow for reproducing the portfolio version of this project is:

1. Place the raw real estate files in `data/raw/`
2. Run `01_load_and_clean_data.R`
3. Run `02_pickleball_courts_scrape.R`
4. Place the FRED unemployment CSV files in `data/raw/`
5. Run:
   - `03_state_comparison_visuals.R`
   - `04_unemployment_rent_forecast.R`
   - `05_city_scoring.R`

## Expected Raw Files

The scripts expect these raw files in `data/raw/`:

### Commercial real estate data
- `Price_and_Availability_Data.csv`
- `Leases.csv`

### FRED unemployment data
- `CAUR.csv`
- `GAUR.csv`
- `FLUR.csv`
- `TXUR.csv`
- `NCUR.csv`
- `TNUR.csv`

## Processed Outputs

The scripts write cleaned and derived files to:

- `data/processed/`
- `figures/`
- `output/`

Examples include:

- `price_availability_clean.csv`
- `leases_clean.csv`
- `market_state_lookup.csv`
- `pickleball_courts_clean.csv`
- `unemployment_data_combined.csv`
- `city_scores.csv`

## Notes

This folder is organized as a cleaned and reproducible version of the original 48-hour hackathon workflow. Some portions of the original project were reconstructed from saved presentation materials and remaining code.
