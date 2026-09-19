# NFL Win Probability Model
# Logistic regression model for estimating in-game win probability

library(tidyverse)
library(nflreadr)
library(broom)


# LOAD PLAY-BY-PLAY DATA

nfl_pbp <- load_pbp(2021:2024)


# PREPARE MODELING DATA

model_data <- nfl_pbp |>
  filter(
    season_type == "REG",
    qtr <= 4,
    !is.na(posteam),
    result != 0,
    down %in% 1:4,
    if_all(
      c(
        ydstogo,
        yardline_100,
        game_seconds_remaining,
        score_differential
      ),
      ~ !is.na(.x)
    )
  ) |>
  mutate(
    posteam_win = case_when(
      posteam == home_team ~ as.numeric(result > 0),
      posteam == away_team ~ as.numeric(result < 0)
    ),
    down = factor(
      down,
      levels = 1:4,
      labels = c(
        "First",
        "Second",
        "Third",
        "Fourth"
      )
    )
  ) |>
  filter(!is.na(posteam_win)) |>
  select(
    season,
    week,
    game_id,
    play_id,
    home_team,
    away_team,
    posteam,
    defteam,
    posteam_win,
    down,
    ydstogo,
    yardline_100,
    game_seconds_remaining,
    score_differential,
    desc
  )


# TRAIN AND TEST SPLIT

training_data <- model_data |>
  filter(season %in% 2021:2023)

test_data <- model_data |>
  filter(season == 2024)


# BUILD WIN PROBABILITY MODEL

wp_model <- glm(
  posteam_win ~
    down +
    ydstogo +
    yardline_100 +
    game_seconds_remaining +
    score_differential,
  data = training_data,
  family = binomial()
)

model_results <- tidy(
  wp_model,
  conf.int = TRUE
)

model_results


# OUT-OF-SAMPLE MODEL EVALUATION

test_data <- test_data |>
  mutate(
    predicted_wp = predict(
      wp_model,
      newdata = test_data,
      type = "response"
    )
  )


# Brier score measures the accuracy of probability predictions
# Lower values indicate better probability estimates

test_brier <- mean(
  (test_data$predicted_wp - test_data$posteam_win)^2
)


# Classification accuracy using 50% win probability as the cutoff

test_accuracy <- mean(
  (test_data$predicted_wp >= 0.50) ==
    test_data$posteam_win
)


model_evaluation <- tibble(
  metric = c(
    "Brier Score",
    "Classification Accuracy"
  ),
  value = c(
    test_brier,
    test_accuracy
  )
)

model_evaluation



# 2025 GIANTS VS. CHARGERS CASE STUDY

nfl_2025_pbp <- load_pbp(2025)

giants_game <- nfl_2025_pbp |>
  filter(
    game_id == "2025_04_LAC_NYG",
    qtr <= 4,
    !is.na(posteam),
    down %in% 1:4,
    if_all(
      c(
        ydstogo,
        yardline_100,
        game_seconds_remaining,
        score_differential
      ),
      ~ !is.na(.x)
    )
  ) |>
  mutate(
    down = factor(
      down,
      levels = 1:4,
      labels = c(
        "First",
        "Second",
        "Third",
        "Fourth"
      )
    )
  ) |>
  arrange(play_id)


# Generate win probability using our model

giants_game$our_wp_posteam <- predict(
  wp_model,
  newdata = giants_game,
  type = "response"
)


# Convert probabilities to the Giants perspective

giants_game <- giants_game |>
  mutate(
    giants_wp = if_else(
      posteam == "NYG",
      our_wp_posteam,
      1 - our_wp_posteam
    ),
    nflverse_wp = if_else(
      posteam == "NYG",
      wp,
      1 - wp
    )
  )



# WIN PROBABILITY COMPARISON

ggplot(
  giants_game,
  aes(x = 3600 - game_seconds_remaining)
) +
  geom_line(
    aes(
      y = giants_wp,
      color = "Our Model"
    ),
    linewidth = 1
  ) +
  geom_line(
    aes(
      y = nflverse_wp,
      color = "nflverse"
    ),
    linewidth = 1
  ) +
  scale_color_manual(
    values = c(
      "Our Model" = "#0B2265",
      "nflverse" = "#A71930"
    )
  ) +
  scale_x_continuous(
    breaks = seq(0, 3600, 900),
    labels = c(
      "Q1",
      "Q2",
      "Q3",
      "Q4",
      "Final"
    )
  ) +
  scale_y_continuous(
    limits = c(0, 1),
    labels = scales::percent
  ) +
  labs(
    title = "Giants Win Probability",
    subtitle = "Chargers at Giants, Week 4, 2025",
    x = "Game Progress",
    y = "Giants Win Probability",
    color = NULL
  ) +
  theme_bw() +
  theme(
    legend.position = "bottom",
    plot.title = element_text(
      hjust = 0.5
    ),
    plot.subtitle = element_text(
      hjust = 0.5
    )
  )



# MODEL COMPARISON

comparison_metrics <- giants_game |>
  summarize(
    MAE = mean(
      abs(giants_wp - nflverse_wp),
      na.rm = TRUE
    ),
    RMSE = sqrt(
      mean(
        (giants_wp - nflverse_wp)^2,
        na.rm = TRUE
      )
    ),
    Correlation = cor(
      giants_wp,
      nflverse_wp,
      use = "complete.obs"
    )
  )

comparison_metrics

# BIGGEST WIN PROBABILITY SWINGS

giants_game <- giants_game |>
  mutate(
    our_wpa =
      lead(giants_wp) - giants_wp,
    nflverse_wpa =
      lead(nflverse_wp) - nflverse_wp
  )


biggest_swings <- giants_game |>
  filter(!is.na(our_wpa)) |>
  arrange(
    desc(abs(our_wpa))
  ) |>
  select(
    play_id,
    qtr,
    game_seconds_remaining,
    posteam,
    down,
    ydstogo,
    yardline_100,
    score_differential,
    giants_wp,
    our_wpa,
    nflverse_wpa,
    desc
  )


# Display the 10 largest swings

biggest_swings |>
  slice_head(n = 10)
