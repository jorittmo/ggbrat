test_that("compact_subcortical_layout packs hemisphere and view groups", {
  square <- function(x, y) {
    sf::st_polygon(list(matrix(
      c(x, y, x + 1, y, x + 1, y + 1, x, y + 1, x, y),
      ncol = 2,
      byrow = TRUE
    )))
  }
  atlas <- sf::st_sf(
    hemisphere = rep(c("left", "right"), 2),
    view = rep(c("lateral", "medial"), each = 2),
    int_view = rep(1:2, each = 2),
    geometry = sf::st_sfc(
      square(0, 0), square(10, 0), square(0, -10), square(10, -10)
    )
  )

  compact <- compact_subcortical_layout(
    atlas,
    horizontal_gap = 0.2,
    vertical_gap = 0.3
  )
  boxes <- lapply(seq_len(nrow(compact)), function(i) sf::st_bbox(compact[i, ]))
  expect_equal(unname(boxes[[2]]["xmin"] - boxes[[1]]["xmax"]), 0.2)
  expect_equal(unname(boxes[[1]]["ymin"] - boxes[[3]]["ymax"]), 0.3)
})

test_that("compact_subcortical_layout drops glass layers by default", {
  points <- sf::st_sf(
    hemisphere = "left",
    view = "lateral",
    int_view = 1L,
    geometry = sf::st_sfc(sf::st_point(c(0, 0)))
  )
  compact <- compact_subcortical_layout(list(atlas = points, cortex = points))
  expect_false("cortex" %in% names(compact))
})
