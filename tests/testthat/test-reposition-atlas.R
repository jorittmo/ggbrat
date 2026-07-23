make_reposition_test_atlas <- function() {
  sf::st_sf(
    region = paste0("region_", 1:4),
    hemisphere = rep(c("left", "right"), 2),
    view = rep(c("view_1", "view_2"), each = 2),
    int_view = rep(1:2, each = 2),
    geometry = sf::st_sfc(
      sf::st_point(c(0, 0)),
      sf::st_point(c(1, 0)),
      sf::st_point(c(10, 5)),
      sf::st_point(c(11, 5))
    )
  )
}

panel_centres <- function(x) {
  keys <- unique(paste(x$view, x$hemisphere))
  vapply(keys, function(key) {
    selected <- paste(x$view, x$hemisphere) == key
    bbox <- sf::st_bbox(x[selected, ])
    c(
      x = as.numeric((bbox["xmin"] + bbox["xmax"]) / 2),
      y = as.numeric((bbox["ymin"] + bbox["ymax"]) / 2)
    )
  }, numeric(2))
}

test_that("reposition_atlas infers surface panels in data order", {
  atlas <- make_reposition_test_atlas()

  in_row <- reposition_atlas(
    atlas, layout = "ABCD", horizontal_gap = 2, vertical_gap = 3
  )
  row_centres <- panel_centres(in_row)
  expect_equal(unname(row_centres["y", ]), rep(0, 4))
  expect_equal(unname(diff(row_centres["x", ])), rep(2, 3))
  expect_equal(
    attr(in_row, "layout_key")[c("panel", "view", "hemisphere")],
    data.frame(
      panel = LETTERS[1:4],
      view = rep(c("view_1", "view_2"), each = 2),
      hemisphere = rep(c("left", "right"), 2)
    )
  )

  in_grid <- reposition_atlas(
    atlas, layout = "AB\nCD", horizontal_gap = 2, vertical_gap = 3
  )
  grid_centres <- panel_centres(in_grid)
  expect_equal(unname(grid_centres["x", ]), c(0, 2, 0, 2))
  expect_equal(unname(grid_centres["y", ]), c(0, 0, -3, -3))
})

test_that("reposition_atlas infers volumetric panels from view", {
  volume <- sf::st_sf(
    region = c("one", "two"),
    axis = c("axial", "sagittal"),
    view = c("axial_1", "sagittal_1"),
    int_view = c(1L, 1L),
    geometry = sf::st_sfc(
      sf::st_point(c(5, 10)),
      sf::st_point(c(20, 30))
    )
  )

  result <- reposition_atlas(volume, "A\nB", vertical_gap = 4)
  coordinates <- sf::st_coordinates(result)
  expect_equal(coordinates[, "X"], c(0, 0))
  expect_equal(coordinates[, "Y"], c(0, -4))
  expect_equal(attr(result, "layout_key")$view, volume$view)
})

test_that("reposition_atlas shifts all atlas-list layers consistently", {
  atlas <- make_reposition_test_atlas()
  shade <- atlas
  shade$int_view <- NULL

  result <- reposition_atlas(
    list(
      atlas = atlas,
      shade = shade,
      cortex = atlas,
      camera_positions = list("unchanged")
    ),
    layout = "AB\nCD",
    vertical_gap = 2
  )

  expect_equal(panel_centres(result$atlas), panel_centres(result$cortex))
  expect_equal(
    sf::st_coordinates(result$atlas),
    sf::st_coordinates(result$shade)
  )
  expect_identical(result$camera_positions, list("unchanged"))
})

test_that("reposition_atlas validates layout membership", {
  atlas <- make_reposition_test_atlas()
  expect_error(reposition_atlas(atlas, "ABC"), "missing: D")
  expect_error(reposition_atlas(atlas, "ABCE"), "unknown: E")
  expect_error(reposition_atlas(atlas, "AABC"), "only once")
  expect_error(reposition_atlas(atlas, "AB1D"), "must be letters")
})
