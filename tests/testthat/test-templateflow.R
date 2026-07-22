test_that("TemplateFlow query validation does not initialize Python", {
  expect_error(templateflow_get(""), "non-empty TemplateFlow identifier")
  expect_error(templateflow_citations("fsaverage", bibtex = NA), "TRUE or FALSE")
})

test_that("TemplateFlow paths remain ordinary builder inputs", {
  paths <- stats::setNames(
    vapply(seq_len(4), function(index) tempfile(), character(1)),
    c("pial_l", "inflated_l", "pial_r", "inflated_r")
  )
  invisible(lapply(paths, file.create))
  surfaces <- list(
    left = unname(paths[c("pial_l", "inflated_l")]),
    right = unname(paths[c("pial_r", "inflated_r")])
  )

  validated <- ggbrat:::brain2d_validate_paired_paths(
    surfaces, "surface_path", "both"
  )

  expect_equal(lengths(validated), c(left = 2L, right = 2L))
})
