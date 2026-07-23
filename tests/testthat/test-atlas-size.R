make_size_test_atlas <- function() {
  sf::st_sf(
    region = c("one", "two"),
    geometry = sf::st_sfc(
      sf::st_point(c(0, 0)),
      sf::st_point(c(4, 2))
    )
  )
}

test_that("atlas_size scales the complete atlas around its centre", {
  atlas <- make_size_test_atlas()
  enlarged <- atlas_size(atlas, factor = 2)

  expect_equal(
    unname(sf::st_coordinates(enlarged)[, c("X", "Y")]),
    matrix(c(-2, -1, 6, 3), ncol = 2, byrow = TRUE)
  )
  expect_equal(sf::st_bbox(enlarged)[c("xmax", "ymax")] -
                 sf::st_bbox(enlarged)[c("xmin", "ymin")],
               2 * (sf::st_bbox(atlas)[c("xmax", "ymax")] -
                      sf::st_bbox(atlas)[c("xmin", "ymin")]))
})

test_that("atlas_size applies one transform to every sf layer", {
  atlas <- make_size_test_atlas()
  shade <- atlas
  sf::st_geometry(shade) <- sf::st_geometry(shade) + c(1, 1)

  result <- atlas_size(
    list(atlas = atlas, shade = shade, metadata = "unchanged"),
    factor = 0.5
  )

  expect_equal(
    unname(
      sf::st_coordinates(result$shade) - sf::st_coordinates(result$atlas)
    ),
    matrix(rep(c(0.5, 0.5), 2), ncol = 2, byrow = TRUE)
  )
  expect_identical(result$metadata, "unchanged")
})

test_that("atlas_size preserves depth coordinates", {
  atlas <- sf::st_sf(
    region = c("one", "two"),
    geometry = sf::st_sfc(
      sf::st_point(c(0, 0, 3), dim = "XYZ"),
      sf::st_point(c(2, 2, 7), dim = "XYZ")
    )
  )
  result <- atlas_size(atlas, factor = 2)
  coordinates <- sf::st_coordinates(result)

  expect_equal(coordinates[, "X"], c(-1, 3))
  expect_equal(coordinates[, "Y"], c(-1, 3))
  expect_equal(coordinates[, "Z"], c(3, 7))
})

test_that("atlas_size validates its inputs", {
  atlas <- make_size_test_atlas()
  expect_identical(atlas_size(atlas), atlas)
  expect_error(atlas_size(atlas, 0), "positive")
  expect_error(atlas_size(atlas, -1), "positive")
  expect_error(atlas_size("not an atlas"), "sf object")
})
