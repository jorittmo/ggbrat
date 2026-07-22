test_that("nifti_to_surface validates density controls before loading Python", {
  expect_error(
    nifti_to_surface("atlas.nii.gz", reduction = 0.5, subdivision = 1),
    "either `reduction` or `subdivision`"
  )
  expect_error(nifti_to_surface("atlas.nii.gz", reduction = 1), "in \\[0, 1\\)")
  expect_error(nifti_to_surface("atlas.nii.gz", subdivision = 4), "between 0 and 3")
  expect_error(
    nifti_to_surface("atlas.nii.gz", voxel_smoothing_sigma = -1),
    "non-negative"
  )
  expect_error(
    nifti_to_surface("atlas.nii.gz", smoothing_iterations = -1),
    "non-negative integer"
  )
  expect_error(nifti_to_surface("atlas.nii.gz", smoothing_factor = 0), "in \\(0, 1\\]")
  expect_error(nifti_to_surface("atlas.nii.gz", minimum_vertices = 3), "at least 4")
  expect_error(nifti_to_surface("atlas.nii.gz", minimum_volume = -1), "non-negative")
  expect_error(
    nifti_to_surface("atlas.nii.gz", split_hemispheres = NA),
    "TRUE or FALSE"
  )
  expect_error(nifti_to_surface(character()), "one or more")
  expect_error(nifti_to_surface("atlas.nii.gz", mask_threshold = Inf), "finite")
  expect_error(
    nifti_to_surface("atlas.nii.gz", distance_upsampling = 5),
    "distance_upsampling"
  )
  expect_error(
    nifti_to_surface("atlas.nii.gz", minimum_component_voxels = 0),
    "minimum_component_voxels"
  )
  expect_error(nifti_to_surface("atlas.nii.gz", closing_radius = 0), "positive")
  expect_error(
    nifti_to_surface("atlas.nii.gz", closing_radius = 2, max_closing_radius = 1),
    "at least"
  )
})

test_that("Python dependencies support NIfTI-to-surface conversion", {
  temporary <- tempfile("ggbrat-nifti-smoke-")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)

  image <- array(0L, dim = c(12L, 12L, 12L))
  image[4:9, 4:9, 4:9] <- 1L
  nifti_path <- file.path(temporary, "tiny-atlas.nii.gz")
  output_path <- file.path(temporary, "tiny-atlas.vtp")
  RNifti::writeNifti(image, nifti_path)

  result <- nifti_to_surface(
    nifti_path = nifti_path,
    output_file = output_path
  )

  expect_true(file.exists(output_path))
  expect_gt(file.info(output_path)$size, 0)
  expect_gt(result$vertices, 0L)
  expect_gt(result$faces, 0L)
  expect_length(result$regions, 1L)
  expect_equal(result$regions[[1L]]$region, "label_1")
})
