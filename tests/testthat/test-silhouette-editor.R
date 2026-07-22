test_that("silhouette lines are prepared as individually selectable features", {
  geometry <- sf::st_sfc(
    sf::st_multilinestring(list(
      matrix(c(0, 0, 1, 1), ncol = 2, byrow = TRUE),
      matrix(c(2, 0, 2, 1), ncol = 2, byrow = TRUE)
    ))
  )
  silhouette <- sf::st_sf(view = "lateral", geometry = geometry)

  lines <- ggbrat:::silhouette_prepare_lines(silhouette)

  expect_equal(nrow(lines), 2L)
  expect_true(all(sf::st_geometry_type(lines) == "LINESTRING"))
  expect_equal(lines$.silhouette_id, 1:2)
  expect_equal(lines$.source_feature, c(1L, 1L))
  expect_equal(lines$view, c("lateral", "lateral"))
})

test_that("editor groups expose every hemisphere and view combination", {
  lines <- sf::st_sf(
    hemisphere = rep(c("left", "right"), each = 2),
    view = rep(c("lateral", "medial"), 2),
    geometry = sf::st_sfc(lapply(seq_len(4), function(index) {
      sf::st_linestring(matrix(c(0, index, 1, index), ncol = 2, byrow = TRUE))
    }))
  )

  grouped <- ggbrat:::silhouette_editor_groups(lines)

  expect_setequal(
    grouped$.editor_group,
    c("left · lateral", "left · medial", "right · lateral", "right · medial")
  )
})

test_that("line smoothing preserves size and open endpoints", {
  coordinates <- matrix(
    c(0, 0, 1, 1, 2, 0, 3, 1, 4, 0),
    ncol = 2, byrow = TRUE
  )
  line <- sf::st_linestring(coordinates)
  smoothed <- ggbrat:::silhouette_smooth_line(line, 2)
  result <- unclass(smoothed)

  expect_equal(nrow(result), nrow(coordinates))
  expect_equal(result[1, ], coordinates[1, ])
  expect_equal(result[nrow(result), ], coordinates[nrow(coordinates), ])
  expect_false(isTRUE(all.equal(result, coordinates)))
})

test_that("line smoothing keeps closed lines closed", {
  coordinates <- matrix(
    c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0),
    ncol = 2, byrow = TRUE
  )
  smoothed <- unclass(ggbrat:::silhouette_smooth_line(
    sf::st_linestring(coordinates), 1
  ))

  expect_equal(nrow(smoothed), nrow(coordinates))
  expect_equal(smoothed[1, ], smoothed[nrow(smoothed), ])
})

test_that("edit_silhouette validates its input before launching", {
  polygon <- sf::st_sf(
    geometry = sf::st_sfc(sf::st_polygon(list(matrix(
      c(0, 0, 1, 0, 1, 1, 0, 0), ncol = 2, byrow = TRUE
    ))))
  )

  expect_error(edit_silhouette(polygon), "only line geometries")
  expect_error(edit_silhouette(list(), layer = "silhouette"), "requested layer")
})
