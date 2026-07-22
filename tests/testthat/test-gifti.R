test_that("GIFTI surfaces and label tables use the cortical reader", {
  skip_if_not_installed("reticulate")
  ggbrat:::brain2d_load_python()
  surface_path <- tempfile(fileext = ".surf.gii")
  second_surface_path <- tempfile(fileext = ".surf.gii")
  label_path <- tempfile(fileext = ".label.gii")
  reticulate::py_set_attr(reticulate::py, "ggbrat_surface_path", surface_path)
  reticulate::py_set_attr(
    reticulate::py, "ggbrat_second_surface_path", second_surface_path
  )
  reticulate::py_set_attr(reticulate::py, "ggbrat_label_path", label_path)
  reticulate::py_run_string(paste(
    "import nibabel as nib",
    "import numpy as np",
    "from nibabel.gifti import GiftiDataArray, GiftiImage, GiftiLabel, GiftiLabelTable",
    "points = np.asarray([[0,0,0],[1,0,0],[0,1,0],[0,0,1]], dtype=np.float32)",
    "faces = np.asarray([[0,1,2],[0,1,3],[0,2,3],[1,2,3]], dtype=np.int32)",
    "surface = GiftiImage(darrays=[GiftiDataArray(points, intent='NIFTI_INTENT_POINTSET'), GiftiDataArray(faces, intent='NIFTI_INTENT_TRIANGLE')])",
    "nib.save(surface, ggbrat_surface_path)",
    "second = GiftiImage(darrays=[GiftiDataArray(points + 2, intent='NIFTI_INTENT_POINTSET'), GiftiDataArray(faces, intent='NIFTI_INTENT_TRIANGLE')])",
    "nib.save(second, ggbrat_second_surface_path)",
    "values = np.asarray([0,1,1,2], dtype=np.int32)",
    "table = GiftiLabelTable()",
    "background = GiftiLabel(0, 0.7, 0.7, 0.7, 1.0)",
    "background.label = 'unknown'",
    "region1 = GiftiLabel(1, 1.0, 0.0, 0.0, 1.0)",
    "region1.label = 'Region One'",
    "region2 = GiftiLabel(2, 0.0, 0.0, 1.0, 1.0)",
    "region2.label = 'Region Two'",
    "table.labels = [background, region1, region2]",
    "labels = GiftiImage(darrays=[GiftiDataArray(values, intent='NIFTI_INTENT_LABEL')], labeltable=table)",
    "nib.save(labels, ggbrat_label_path)",
    sep = "\n"
  ))

  surface <- ggbrat:::brain2d_python_env$read_surface_file(surface_path)
  labels <- ggbrat:::brain2d_python_env$read_label_file(label_path)

  expect_equal(dim(surface[[1]]), c(4L, 3L))
  expect_equal(dim(surface[[2]]), c(4L, 3L))
  expect_equal(as.character(labels[[1]]), c(
    "unlabelled", "Region One", "Region One", "Region Two"
  ))
  expect_equal(as.character(labels[[2]]), c(
    "#bdbdbd", "#ff0000", "#ff0000", "#0000ff"
  ))

  blended <- ggbrat:::brain2d_resolve_explicit_surfaces(
    list(left = c(surface_path, second_surface_path)), ratio = 0.25
  )
  blended_surface <- ggbrat:::brain2d_python_env$read_surface_file(blended$left)
  expect_equal(blended_surface[[1]], surface[[1]] + 1.5, tolerance = 1e-6)
  expect_equal(blended_surface[[2]], surface[[2]])
})
