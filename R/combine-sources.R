combine_scraped_and_api_data <- function(data_scraped = NULL, data_api = NULL) {
  if (is.null(data_scraped)) {
    data_scraped <- readr::read_csv(here::here("data/covid-19-florida_dash_summary.csv"))
  }
  if (is.null(data_api)) {
    data_api <- readr::read_csv(here::here("data/covid-19-florida_arcgis_summary.csv"), guess_max = 1e5)
  }
  
  data_scraped_sel <-
    data_scraped %>%
    dplyr::select(timestamp, negative, positive, pending, deaths = one_of("deaths", "county_deaths", "florida_deaths"), -total) %>%
    dplyr::mutate(deaths = dplyr::coalesce(!!!rlang::syms(stringr::str_subset(colnames(.), "deaths")))) %>%
    dplyr::select(-matches("deaths\\d+")) %>%
    tidyr::fill(deaths) %>%
    dplyr::mutate(source = 1, timestamp = lubridate::ymd_hms(timestamp))
  
  data_api_sel <- 
    data_api %>%
    dplyr::group_by(timestamp) %>%
    dplyr::mutate(c_fl_res_deaths = dplyr::coalesce(c_fl_res_deaths, fl_res_deaths)) %>% 
    dplyr::summarize_at(vars(t_positive_2, t_neg_res, t_neg_not_fl_res, t_pending, t_inconc, c_non_res_deaths, c_fl_res_deaths), sum, na.rm = TRUE) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(t_negative_2 = t_neg_res + t_neg_not_fl_res) %>% 
    dplyr::mutate(source = 0)

  dplyr::bind_rows(data_scraped_sel, data_api_sel) %>%
    # Updates never occur before 11am, so the first snapshot is from the previous day
    # In general, use the last reported value of the day as the day's results
    dplyr::mutate(day = lubridate::floor_date(timestamp - lubridate::hours(9)), "day") %>% 
    dplyr::mutate_at(vars(day), lubridate::as_date) %>%
    dplyr::group_by(day) %>%
    dplyr::arrange(dplyr::desc(timestamp), source) %>%
    dplyr::slice(1) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      negative = dplyr::coalesce(t_negative_2, negative),
      positive = dplyr::coalesce(t_positive_2, positive),
      pending = dplyr::coalesce(t_pending, pending),
      deaths = dplyr::coalesce(c_fl_res_deaths + c_non_res_deaths, deaths),
      inconclusive = t_inconc
    ) %>%
    tidyr::replace_na(list(inconclusive = 0)) %>%
    dplyr::mutate(total = negative + positive) %>%
    dplyr::arrange(day) %>%
    dplyr::select(day, timestamp, total, negative, positive, pending, deaths, inconclusive)
}