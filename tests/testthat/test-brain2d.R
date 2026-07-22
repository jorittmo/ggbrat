test_that("brain_views requires presets in non-interactive mode", {
  expect_error(
    brain_views(
      annot_path = "dummy.annot",
      interactive = FALSE,
      n_views = 1
    ),
    "camera_positions"
  )
})

test_that("brain_views requires a cortical annotation or generic mesh", {
  cameras <- list(list(c(1, 0, 0), c(0, 0, 0), c(0, 0, 1)))
  expect_error(
    brain_views(annot_path = NULL, camera_positions = cameras),
    "either `annot_path` or `mesh_path`"
  )
})

test_that("generic mesh vertices retain their mesh hemisphere", {
  vertices <- data.frame(
    x = c(0, 1, 0, 1, 0, 1),
    y = c(0, 0, 1, 1, 2, 2),
    color = rep("#000000", 6),
    region = rep("region", 6),
    hemisphere = rep("subcortical", 6),
    view = rep("anterior", 6),
    int_view = rep(1L, 6)
  )
  atlas <- brain2d_vertices_to_sf(vertices)
  expect_equal(atlas$hemisphere, "subcortical")
  expect_equal(atlas$region, "region")
  expect_equal(atlas$vert_size, 6L)
})

test_that("vertex conversion and layout preserve projected Z", {
  vertices <- data.frame(
    x = c(0, 1, 0, 1, 0, 1),
    y = c(0, 0, 1, 1, 2, 2),
    z = seq(0.1, 0.6, by = 0.1),
    color = rep("#000000", 6),
    region = rep("region", 6),
    hemisphere = rep("left", 6),
    view = rep("lateral", 6),
    int_view = rep(2L, 6)
  )

  atlas <- brain2d_vertices_to_sf(vertices)
  expect_equal(as.character(sf::st_geometry_type(atlas, by_geometry = TRUE)), "MULTIPOINT")
  expect_equal(sf::st_coordinates(atlas$geometry)[, "Z"], vertices$z)

  shifted <- shift_brain_views(atlas, cell_dx = 2, cell_dy = -3, n_cols = 2)
  shifted_coordinates <- sf::st_coordinates(shifted$geometry)
  expect_equal(shifted_coordinates[, "X"], vertices$x)
  expect_equal(shifted_coordinates[, "Y"], vertices$y - 3)
  expect_equal(shifted_coordinates[, "Z"], vertices$z)
})

test_that("paired generic meshes must be named by hemisphere", {
  cameras <- list(list(c(1, 0, 0), c(0, 0, 0), c(0, 0, 1)))
  expect_error(
    brain_views(
      mesh_path = c("left.vtp", "right.vtp"),
      camera_positions = cameras
    ),
    "named `left` and `right`"
  )
})

test_that("glass cortex requires paired meshes", {
  cameras <- list(list(c(1, 0, 0), c(0, 0, 0), c(0, 0, 1)))
  mesh <- tempfile(fileext = ".vtp")
  file.create(mesh)
  on.exit(unlink(mesh))
  expect_error(
    brain_views(
      mesh_path = mesh,
      camera_positions = cameras,
      add_cortex = TRUE
    ),
    "requires a named left/right"
  )
  expect_error(
    brain_views(
      mesh_path = mesh,
      camera_positions = cameras,
      cortex_point_fraction = 0
    ),
    "in \\(0, 1\\]"
  )
})

test_that("atlas polygon and cortex preview controls are validated", {
  expect_error(build_brain_atlas(create_polygons = NA), "TRUE or FALSE")
  expect_error(brain_views(keep_z_coord = NA), "keep_z_coord")
  expect_message(
    tryCatch(build_brain_atlas(keep_z_coord = TRUE), error = function(error) NULL),
    "region polygons use X and Y only"
  )
  expect_equal(formals(build_brain_atlas)$create_polygons, TRUE)
  expect_equal(formals(build_brain_atlas)$keep_z_coord, FALSE)
  expect_equal(formals(brain_views)$keep_z_coord, FALSE)
  expect_equal(formals(brain_views)$cortex_preview_opacity, 0.1)
})

test_that("cortical density filtering retains dense projected points", {
  dense <- data.frame(
    x = c(seq(0, 0.09, length.out = 10), 10, 20),
    y = c(seq(0, 0.09, length.out = 10), 10, 20)
  )
  filtered <- brain2d_filter_cortex_points(
    dense,
    method = "density",
    k = 2,
    keep_quantile = 0.5,
    max_points = 4
  )
  expect_equal(nrow(filtered), 4L)
  expect_true(all(filtered$x < 1))
  expect_identical(brain2d_filter_cortex_points(dense, "all"), dense)
})

test_that("shift_brain_views uses int_view instead of parsing view labels", {
  points <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(0, 0)),
    sf::st_point(c(0, 0)),
    sf::st_point(c(0, 0))
  )

  atlas <- sf::st_sf(
    hemisphere = c("left", "right", "left", "right"),
    view = c("lateral", "lateral", "medial", "medial"),
    int_view = c(1L, 1L, 2L, 2L),
    geometry = points
  )

  shifted <- shift_brain_views(atlas, cell_dx = 2, cell_dy = -3, n_cols = 2)
  coords <- sf::st_coordinates(shifted)

  expect_equal(coords[, "X"], c(0, 2, 0, 2))
  expect_equal(coords[, "Y"], c(0, 0, -3, -3))
})

test_that("shift_brain_views shifts raw atlas lists", {
  atlas_points <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(0, 0)),
    sf::st_point(c(0, 0)),
    sf::st_point(c(0, 0))
  )

  atlas <- sf::st_sf(
    hemisphere = c("left", "right", "left", "right"),
    view = c("lateral", "lateral", "medial", "medial"),
    int_view = c(1L, 1L, 2L, 2L),
    geometry = atlas_points
  )

  silhouette_lines <- sf::st_sfc(
    sf::st_linestring(matrix(c(0, 0, 1, 0), ncol = 2, byrow = TRUE)),
    sf::st_linestring(matrix(c(0, 0, 1, 0), ncol = 2, byrow = TRUE)),
    sf::st_linestring(matrix(c(0, 0, 1, 0), ncol = 2, byrow = TRUE)),
    sf::st_linestring(matrix(c(0, 0, 1, 0), ncol = 2, byrow = TRUE))
  )

  silhouette <- sf::st_sf(
    hemisphere = c("left", "right", "left", "right"),
    view = c("lateral", "lateral", "medial", "medial"),
    int_view = c(1L, 1L, 2L, 2L),
    geometry = silhouette_lines
  )

  shifted <- shift_brain_views(
    list(atlas = atlas, silhouette = silhouette, camera_positions = list()),
    cell_dx = 2,
    cell_dy = -3,
    n_cols = 2
  )

  atlas_coords <- sf::st_coordinates(shifted$atlas)
  sil_coords <- sf::st_coordinates(shifted$silhouette)

  expect_equal(atlas_coords[, "X"], c(0, 2, 0, 2))
  expect_equal(atlas_coords[, "Y"], c(0, 0, -3, -3))
  expect_equal(sil_coords[sil_coords[, "L1"] == 1, "X"], c(0, 1))
  expect_equal(sil_coords[sil_coords[, "L1"] == 2, "X"], c(2, 3))
  expect_equal(sil_coords[sil_coords[, "L1"] == 3, "Y"], c(-3, -3))
  expect_equal(sil_coords[sil_coords[, "L1"] == 4, "X"], c(2, 3))
})

test_that("silhouette_sf handles empty inputs", {
  sil <- silhouette_sf(data.frame(x0 = numeric(), y0 = numeric(), x1 = numeric(), y1 = numeric()))
  expect_s3_class(sil, "sf")
  expect_equal(nrow(sil), 0L)
})

test_that("silhouette_sf reconstructs ordered segments without splitting paths", {
  segments <- data.frame(
    x0 = c(0, 1, 2, 10), y0 = c(0, 0, 0, 0),
    x1 = c(1, 2, 3, 11), y1 = c(0, 0, 0, 0)
  )
  sil <- silhouette_sf(segments, min_length = 0, simplify_tolerance = 0)
  expect_equal(nrow(sil), 2L)
  expect_equal(nrow(sf::st_coordinates(sil[1, ])), 4L)

  filtered <- silhouette_sf(segments, min_length = 2, simplify_tolerance = 0)
  expect_equal(nrow(filtered), 1L)
})

test_that("shift_brain_views handles raw atlas lists without silhouette", {
  atlas_points <- sf::st_sfc(
    sf::st_point(c(0, 0)),
    sf::st_point(c(0, 0))
  )

  atlas <- sf::st_sf(
    hemisphere = c("left", "right"),
    view = c("lateral", "lateral"),
    int_view = c(1L, 1L),
    geometry = atlas_points
  )

  shifted <- shift_brain_views(
    list(atlas = atlas, camera_positions = list()),
    cell_dx = 2,
    cell_dy = -3,
    n_cols = 2
  )

  coords <- sf::st_coordinates(shifted$atlas)

  expect_false("silhouette" %in% names(shifted))
  expect_equal(coords[, "X"], c(0, 2))
  expect_equal(coords[, "Y"], c(0, 0))
})

test_that("shift_brain_views shifts glass cortex layers", {
  points <- sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(0, 0)))
  layer <- sf::st_sf(
    hemisphere = c("left", "right"),
    view = c("lateral", "lateral"),
    int_view = c(1L, 1L),
    geometry = points
  )
  shifted <- shift_brain_views(list(atlas = layer, cortex = layer), cell_dx = 2)
  expect_equal(sf::st_coordinates(shifted$cortex)[, "X"], c(0, 2))
})
