test_that("SVG paths become labelled sf polygons", {
  svg <- tempfile(fileext = ".svg")
  writeLines(c(
    '<svg xmlns="http://www.w3.org/2000/svg">',
    '  <g id="upper"><path d="M 0 0 L 4 0 L 4 2 L 0 2 Z"/></g>',
    '  <g data-name="lower"><path d="M 0 4 C 1 3 3 3 4 4 L 4 6 L 0 6 Z"/></g>',
    '  <g data-name="lower"><path d="M 5 4 L 6 4 L 6 6 L 5 6 Z"/></g>',
    '</svg>'
  ), svg)
  on.exit(unlink(svg))

  atlas <- build_atlas_svg(svg, geometry_method = "path")

  expect_s3_class(atlas, "sf")
  expect_named(atlas, c("region", "geometry"))
  expect_setequal(atlas$region, c("upper", "lower"))
  expect_true(all(sf::st_is_valid(atlas)))
  expect_equal(unname(sf::st_bbox(atlas)[c("ymin", "ymax")]), c(0, 6))
})

test_that("SVG path parser handles relative and smooth curves", {
  coordinates <- svg_path_coordinates(
    "M 0 0 c 1 0 1 1 2 1 s 1 1 2 1 v 1 l -4 0 z",
    curve_steps = 5L
  )

  expect_equal(ncol(coordinates), 2L)
  expect_true(nrow(coordinates) > 10L)
  expect_equal(coordinates[1L, ], coordinates[nrow(coordinates), ])
})

test_that("SVG importer applies transforms to exact paths", {
  svg <- tempfile(fileext = ".svg")
  writeLines(
    '<svg xmlns="http://www.w3.org/2000/svg"><g id="x" transform="translate(2, 3)"><path d="M0 0 L1 0 L0 1 Z"><title>region_x</title></path></g></svg>',
    svg
  )
  on.exit(unlink(svg))

  atlas <- build_atlas_svg(svg, flip_y = FALSE)
  expect_identical(atlas$region, "region_x")
  expect_equal(as.numeric(sf::st_bbox(atlas)), c(2, 3, 3, 4))
})
