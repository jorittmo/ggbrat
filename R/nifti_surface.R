#' Create a labelled surface mesh from a NIfTI atlas
#'
#' Creates each nonzero atlas region independently using marching cubes, then
#' combines the disconnected components in one VTP file. The numeric `label`
#' and character `parcel` arrays are stored as both point and cell data.
#'
#' @param nifti_path Path to a discrete-label `.nii` or `.nii.gz` image.
#' @param lookup_path Optional CSV whose first two columns contain numeric labels
#'   and parcel names. Headerless files are supported.
#' @param output_file Destination `.vtp` file. By default it is named after the
#'   NIfTI image under `data/subcortical/surfaces`.
#' @param labels Optional numeric labels to include. The default uses every
#'   nonzero label in the image.
#' @param split_hemispheres Whether to create separate `_left.vtp` and
#'   `_right.vtp` meshes. Hemispheres are inferred from parcel-name components
#'   such as `_L`, `_R`, `left`, `right`, `lh`, and `rh` in the lookup table.
#' @param reduction Proportion of triangles to remove from each region, in
#'   `[0, 1)`. Cannot be combined with `subdivision`.
#' @param subdivision Number of linear subdivision levels from 0 through 3.
#'   Each level creates approximately four times as many triangles. This adds
#'   sampling vertices but does not add anatomical detail beyond the NIfTI.
#' @param voxel_smoothing_sigma Standard deviation, in voxels, for Gaussian
#'   smoothing of each label's signed-distance field before marching cubes.
#'   Zero preserves the exact voxel-derived boundary; values around 0.5 to 1.5
#'   progressively reduce its staircase appearance.
#' @param smoothing_method Either `"windowed_sinc"`, which better preserves
#'   volume, or `"laplacian"`, which more strongly rounds voxel edges.
#' @param smoothing_iterations Number of windowed-sinc smoothing iterations.
#' @param smoothing_factor Smoothing strength in `(0, 1]`: the relaxation
#'   factor for Laplacian smoothing or passband for windowed-sinc smoothing.
#' @param minimum_vertices Connected components with fewer vertices are removed.
#' @param minimum_volume Connected components with a smaller volume in cubic
#'   world-coordinate units are removed.
#' @param overwrite Whether an existing output file may be replaced.
#'
#' @return A list containing `output_file`, per-region mesh summaries, and total
#'   vertex and face counts.
#' @export
nifti_to_surface <- function(
  nifti_path,
  lookup_path = NULL,
  output_file = NULL,
  labels = NULL,
  split_hemispheres = FALSE,
  reduction = 0,
  subdivision = 0L,
  voxel_smoothing_sigma = 0,
  smoothing_method = c("windowed_sinc", "laplacian"),
  smoothing_iterations = 0L,
  smoothing_factor = 0.1,
  minimum_vertices = 4L,
  minimum_volume = 0.01,
  overwrite = FALSE
) {
  smoothing_method <- match.arg(smoothing_method)
  if (!is.character(nifti_path) || length(nifti_path) != 1L || !nzchar(nifti_path)) {
    stop("`nifti_path` must be one non-empty path.", call. = FALSE)
  }
  if (!is.null(output_file) &&
      (!is.character(output_file) || length(output_file) != 1L || !nzchar(output_file))) {
    stop("`output_file` must be NULL or one non-empty path.", call. = FALSE)
  }
  if (!is.numeric(reduction) || length(reduction) != 1L || is.na(reduction) ||
      reduction < 0 || reduction >= 1) {
    stop("`reduction` must be one number in [0, 1).", call. = FALSE)
  }
  if (!is.numeric(subdivision) || length(subdivision) != 1L || is.na(subdivision) ||
      subdivision < 0 || subdivision > 3 || subdivision != as.integer(subdivision)) {
    stop("`subdivision` must be an integer between 0 and 3.", call. = FALSE)
  }
  if (reduction > 0 && subdivision > 0) {
    stop("Use either `reduction` or `subdivision`, not both.", call. = FALSE)
  }
  if (!is.numeric(voxel_smoothing_sigma) || length(voxel_smoothing_sigma) != 1L ||
      is.na(voxel_smoothing_sigma) || voxel_smoothing_sigma < 0) {
    stop("`voxel_smoothing_sigma` must be one non-negative number.", call. = FALSE)
  }
  if (!is.numeric(smoothing_iterations) || length(smoothing_iterations) != 1L ||
      is.na(smoothing_iterations) || smoothing_iterations < 0 ||
      smoothing_iterations != as.integer(smoothing_iterations)) {
    stop("`smoothing_iterations` must be a non-negative integer.", call. = FALSE)
  }
  if (!is.numeric(smoothing_factor) || length(smoothing_factor) != 1L ||
      is.na(smoothing_factor) || smoothing_factor <= 0 || smoothing_factor > 1) {
    stop("`smoothing_factor` must be one number in (0, 1].", call. = FALSE)
  }
  if (!is.numeric(minimum_vertices) || length(minimum_vertices) != 1L ||
      is.na(minimum_vertices) || minimum_vertices < 4 ||
      minimum_vertices != as.integer(minimum_vertices)) {
    stop("`minimum_vertices` must be an integer of at least 4.", call. = FALSE)
  }
  if (!is.numeric(minimum_volume) || length(minimum_volume) != 1L ||
      is.na(minimum_volume) || minimum_volume < 0) {
    stop("`minimum_volume` must be one non-negative number.", call. = FALSE)
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.logical(split_hemispheres) || length(split_hemispheres) != 1L ||
      is.na(split_hemispheres)) {
    stop("`split_hemispheres` must be TRUE or FALSE.", call. = FALSE)
  }

  nifti_surface_load_python()
  args <- list(
    nifti_path = normalizePath(nifti_path, mustWork = FALSE),
    lookup_path = if (is.null(lookup_path)) NULL else normalizePath(lookup_path, mustWork = FALSE),
    output_file = output_file,
    labels = labels,
    reduction = reduction,
    subdivision = as.integer(subdivision),
    voxel_smoothing_sigma = voxel_smoothing_sigma,
    smoothing_method = smoothing_method,
    smoothing_iterations = as.integer(smoothing_iterations),
    smoothing_factor = smoothing_factor,
    minimum_vertices = as.integer(minimum_vertices),
    minimum_volume = minimum_volume,
    overwrite = overwrite
  )
  if (!split_hemispheres) {
    return(reticulate::py_to_r(
      do.call(nifti_surface_python_env$nifti_to_surface, args)
    ))
  }
  if (is.null(lookup_path)) {
    stop("`lookup_path` is required when `split_hemispheres = TRUE`.", call. = FALSE)
  }

  if (is.null(output_file)) {
    atlas_name <- basename(nifti_path)
    atlas_name <- sub("\\.nii(\\.gz)?$", "", atlas_name, ignore.case = TRUE)
    output_file <- file.path("data", "subcortical", "surfaces", paste0(atlas_name, ".vtp"))
  }
  stem <- sub("\\.vtp$", "", output_file, ignore.case = TRUE)
  output_files <- c(left = paste0(stem, "_left.vtp"), right = paste0(stem, "_right.vtp"))
  results <- lapply(names(output_files), function(hemisphere) {
    hemi_args <- args
    hemi_args$output_file <- output_files[[hemisphere]]
    hemi_args$hemisphere <- hemisphere
    reticulate::py_to_r(do.call(nifti_surface_python_env$nifti_to_surface, hemi_args))
  })
  names(results) <- names(output_files)

  list(
    output_files = stats::setNames(
      vapply(results, `[[`, character(1), "output_file"),
      names(results)
    ),
    hemispheres = results,
    vertices = sum(vapply(results, `[[`, integer(1), "vertices")),
    faces = sum(vapply(results, `[[`, integer(1), "faces"))
  )
}

nifti_surface_python_env <- new.env(parent = baseenv())

nifti_surface_python_path <- function() {
  candidates <- c(
    system.file("python", "nifti_surfaces.py", package = "ggbrat"),
    file.path("inst", "python", "nifti_surfaces.py")
  )
  path <- candidates[file.exists(candidates)][1]
  if (is.na(path) || !nzchar(path)) {
    stop("Could not locate `nifti_surfaces.py`.", call. = FALSE)
  }
  path
}

nifti_surface_load_python <- function() {
  if (!exists("nifti_to_surface", envir = nifti_surface_python_env, inherits = FALSE)) {
    reticulate::source_python(
      nifti_surface_python_path(),
      envir = nifti_surface_python_env
    )
  }
  invisible(TRUE)
}
