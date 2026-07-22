test_that("volumetric masks are polygonized directly and retain holes", {
  mask <- matrix(FALSE, 5, 5)
  mask[2:4, 2:4] <- TRUE
  mask[3, 3] <- FALSE

  geometry <- ggbrat:::vol_mask_polygon(mask, 1:5, 1:5)
  feature <- sf::st_sf(geometry = sf::st_sfc(geometry))

  expect_s3_class(geometry, "XY")
  expect_true(all(sf::st_is_valid(feature)))
  expect_gt(length(sf::st_geometry(feature)[[1]][[1]]), 1L)
})

test_that("volumetric polygon outlines can be smoothed", {
  mask <- matrix(FALSE, 5, 5)
  mask[2:4, 2:4] <- TRUE
  geometry <- ggbrat:::vol_mask_polygon(mask, 1:5, 1:5)
  smoothed <- ggbrat:::vol_smooth_geometry(geometry, 2L)

  expect_s3_class(smoothed, "XY")
  original_coordinates <- nrow(sf::st_coordinates(sf::st_sfc(geometry)))
  smoothed_coordinates <- nrow(sf::st_coordinates(sf::st_sfc(smoothed)))
  expect_lte(smoothed_coordinates, original_coordinates * 3)
  expect_false(isTRUE(all.equal(
    sf::st_coordinates(sf::st_sfc(smoothed)),
    sf::st_coordinates(sf::st_sfc(geometry))
  )))
  expect_true(sf::st_is_valid(sf::st_sfc(smoothed)))
})

test_that("build_atlas_vol creates three valid slice atlases", {
  atlas <- array(0, c(5, 5, 5))
  atlas[2:3, 2:3, 2:3] <- 1
  atlas[4:5, 3:4, 3:4] <- 2
  context <- array(0, c(5, 5, 5))
  context[1:5, 1:5, 2:4] <- 0.8

  atlas_path <- tempfile(fileext = ".nii.gz")
  context_path <- tempfile(fileext = ".nii.gz")
  lookup_path <- tempfile(fileext = ".csv")
  RNifti::writeNifti(RNifti::asNifti(atlas), atlas_path)
  RNifti::writeNifti(RNifti::asNifti(context), context_path)
  writeLines(c("1,left", "2,right"), lookup_path)

  result <- build_atlas_vol(
    atlas_path,
    lookup_path = lookup_path,
    gray_matter_path = context_path,
    slice_coordinates = c(axial = 2, sagittal = 2, coronal = 2),
    gray_matter_region = NA_character_,
    smooth_iterations = 1,
    gray_matter_smooth_iterations = 0.25
  )

  expect_s3_class(result, "sf")
  expect_setequal(unique(result$axis), c("axial", "sagittal", "coronal"))
  expect_setequal(unique(result$view), c("axial_1", "sagittal_1", "coronal_1"))
  expect_true(all(result$int_view == 1L))
  expect_setequal(unique(result$selection_order), 1:3)
  expect_true(all(c("left", "right") %in% result$region))
  expect_true(any(is.na(result$region[result$tissue == "gray_matter"])))
  expect_setequal(unique(result$tissue), c("gray_matter", "subcortical"))
  expect_true(all(sf::st_is_valid(result)))
  expect_true(all(result$slice_index == 3L))
  expect_true(all(result$slice_coordinate == 2))
})

test_that("slice selections number repeated axes independently", {
  xform <- diag(4)
  axis_map <- ggbrat:::vol_axis_map(xform)
  selections <- ggbrat:::vol_slice_selections(
    c("axial", "coronal"),
    c(axial = 2, coronal = 1),
    c(5, 5, 5), xform, axis_map
  )

  expect_equal(selections$axis, c("axial", "coronal"))
  expect_equal(selections$view, c("axial_1", "coronal_1"))
  expect_equal(selections$slice_index, c(3L, 2L))
})

test_that("build_atlas_vol validates image grids and label selections", {
  atlas_path <- tempfile(fileext = ".nii.gz")
  context_path <- tempfile(fileext = ".nii.gz")
  RNifti::writeNifti(RNifti::asNifti(array(0, c(5, 5, 5))), atlas_path)
  RNifti::writeNifti(RNifti::asNifti(array(0, c(4, 5, 5))), context_path)

  expect_error(
    build_atlas_vol(atlas_path, gray_matter_path = context_path),
    "identical dimensions"
  )
  expect_error(
    build_atlas_vol(
      atlas_path, gray_matter_path = atlas_path, labels = "one",
      include_gray_matter = FALSE
    ),
    "finite numeric"
  )
  expect_error(
    build_atlas_vol(
      atlas_path, gray_matter_path = atlas_path, smooth_iterations = -0.5
    ),
    "non-negative number"
  )
  expect_error(
    build_atlas_vol(
      atlas_path, gray_matter_path = atlas_path,
      gray_matter_smooth_iterations = NA_real_
    ),
    "gray_matter_smooth_iterations.*non-negative number"
  )
  expect_error(
    build_atlas_vol(
      atlas_path, gray_matter_path = atlas_path,
      interactive = TRUE, n_views = 0
    ),
    "positive integer"
  )
})

test_that("lookup tables may have headers and UTF-8 BOMs", {
  path <- tempfile(fileext = ".csv")
  writeBin(charToRaw("\ufefflabel,region\n1,Hippocampus\n2,Amygdala\n"), path)

  lookup <- ggbrat:::vol_read_lookup(path)

  expect_equal(lookup$label, c(1, 2))
  expect_equal(lookup$region, c("Hippocampus", "Amygdala"))
})
