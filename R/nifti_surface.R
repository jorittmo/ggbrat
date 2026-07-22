#' Create a labelled surface mesh from a NIfTI atlas
#'
#' Creates each nonzero atlas region independently using marching cubes, then
#' combines the disconnected components in one VTP file. The numeric `label`
#' and character `region` arrays are stored as both point and cell data.
#'
#' @param nifti_path Path to a discrete-label `.nii` or `.nii.gz` image, a
#'   directory of standalone region images, or a character vector of standalone
#'   region images.
#' @param lookup_path Optional CSV whose first two columns contain numeric labels
#'   and region names. Headerless files are supported.
#' @param output_file Destination `.vtp` file. By default it is named after the
#'   NIfTI image under `data/subcortical/surfaces`.
#' @param labels Optional numeric labels to include. The default uses every
#'   nonzero label in the image.
#' @param split_hemispheres Whether to create separate `_left.vtp` and
#'   `_right.vtp` meshes. Hemispheres are inferred from region-name components
#'   such as `_L`, `_R`, `left`, `right`, `lh`, and `rh` in the lookup table.
#' @param mask_threshold For standalone images, voxel values greater than or
#'   equal to this threshold are included in the region mask.
#' @param surface_style Standalone-mask surface style. `"faithful"` preserves
#'   the input mask; `"display"` enables cleanup and volume-preserving display
#'   geometry.
#' @param minimum_component_voxels Display-mode voxel islands smaller than this
#'   are removed.
#' @param closing_iterations Display-mode binary-closing iterations.
#' @param fill_voxel_holes Whether display mode fills enclosed voxel holes.
#' @param distance_upsampling Display-mode signed-distance upsampling factor.
#' @param preserve_volume Whether display-mode meshes are rescaled to the
#'   cleaned mask volume after smoothing.
#' @param small_region_method Either `"ellipsoid"` or `"mesh"` for very small
#'   standalone masks.
#' @param small_region_threshold Masks with fewer voxels use the selected small
#'   region method.
#' @param topology_correction Standalone display-mode topology correction.
#'   `"genus0"` adaptively closes tunnels; `"none"` preserves topology.
#' @param closing_radius Initial spherical closing radius in world-coordinate
#'   units for topology correction.
#' @param max_closing_radius Maximum adaptive spherical closing radius.
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
#'
#' @examples
#' \dontrun{
#' brainstem <- nifti_to_surface(
#'   nifti_path = "data/subcortical/MNI152NLin2009cAsym/Brainstem_Navigator",
#'   lookup_path = paste0(
#'     "data/subcortical/MNI152NLin2009cAsym/Brainstem_Navigator/",
#'     "Brainstem_Navigator_lookup.csv"
#'   ),
#'   output_file = "data/subcortical/surfaces/Brainstem_Navigator.vtp"
#' )
#' }
#' @export
nifti_to_surface <- function(
  nifti_path,
  lookup_path = NULL,
  output_file = NULL,
  labels = NULL,
  split_hemispheres = FALSE,
  mask_threshold = 0.5,
  surface_style = c("faithful", "display"),
  minimum_component_voxels = 2L,
  closing_iterations = 1L,
  fill_voxel_holes = TRUE,
  distance_upsampling = 2L,
  preserve_volume = TRUE,
  small_region_method = c("ellipsoid", "mesh"),
  small_region_threshold = 20L,
  topology_correction = c("none", "genus0"),
  closing_radius = 1,
  max_closing_radius = 2,
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
  surface_style <- match.arg(surface_style)
  small_region_method <- match.arg(small_region_method)
  topology_correction <- match.arg(topology_correction)
  if (!is.character(nifti_path) || !length(nifti_path) || any(!nzchar(nifti_path))) {
    stop("`nifti_path` must contain one or more non-empty paths.", call. = FALSE)
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
  if (!is.numeric(mask_threshold) || length(mask_threshold) != 1L ||
      is.na(mask_threshold) || !is.finite(mask_threshold)) {
    stop("`mask_threshold` must be one finite number.", call. = FALSE)
  }
  integer_option <- function(value, minimum, maximum = Inf, name) {
    if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
        value < minimum || value > maximum || value != as.integer(value)) {
      stop(
        "`", name, "` must be an integer between ", minimum, " and ", maximum, ".",
        call. = FALSE
      )
    }
  }
  integer_option(minimum_component_voxels, 1, name = "minimum_component_voxels")
  integer_option(closing_iterations, 0, name = "closing_iterations")
  integer_option(distance_upsampling, 1, 4, "distance_upsampling")
  integer_option(small_region_threshold, 1, name = "small_region_threshold")
  for (option in c("fill_voxel_holes", "preserve_volume")) {
    value <- get(option)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("`", option, "` must be TRUE or FALSE.", call. = FALSE)
    }
  }
  if (!is.numeric(closing_radius) || length(closing_radius) != 1L ||
      is.na(closing_radius) || closing_radius <= 0) {
    stop("`closing_radius` must be one positive number.", call. = FALSE)
  }
  if (!is.numeric(max_closing_radius) || length(max_closing_radius) != 1L ||
      is.na(max_closing_radius) || max_closing_radius < closing_radius) {
    stop("`max_closing_radius` must be at least `closing_radius`.", call. = FALSE)
  }

  nifti_surface_load_python()
  standalone <- length(nifti_path) > 1L || dir.exists(nifti_path[[1]])
  if (standalone) {
    if (split_hemispheres) {
      stop("Standalone NIfTI collections cannot currently be split by hemisphere.", call. = FALSE)
    }
    if (length(nifti_path) == 1L && dir.exists(nifti_path[[1]])) {
      source_dir <- nifti_path[[1]]
      nifti_files <- list.files(
        source_dir,
        pattern = "\\.nii(\\.gz)?$",
        full.names = TRUE,
        ignore.case = TRUE
      )
    } else {
      nifti_files <- nifti_path
      source_dir <- dirname(nifti_files[[1]])
    }
    nifti_files <- sort(normalizePath(nifti_files, mustWork = FALSE))
    if (!length(nifti_files)) {
      stop("No NIfTI files were found in `nifti_path`.", call. = FALSE)
    }
    if (is.null(output_file)) {
      output_file <- file.path(
        "data", "subcortical", "surfaces", paste0(basename(source_dir), ".vtp")
      )
    }
    result <- nifti_surface_python_env$nifti_files_to_surface(
      nifti_paths = nifti_files,
      output_file = output_file,
      lookup_path = if (is.null(lookup_path)) NULL else normalizePath(lookup_path, mustWork = FALSE),
      labels = labels,
      mask_threshold = mask_threshold,
      reduction = reduction,
      subdivision = as.integer(subdivision),
      voxel_smoothing_sigma = voxel_smoothing_sigma,
      smoothing_method = smoothing_method,
      smoothing_iterations = as.integer(smoothing_iterations),
      smoothing_factor = smoothing_factor,
      minimum_vertices = as.integer(minimum_vertices),
      minimum_volume = minimum_volume,
      surface_style = surface_style,
      minimum_component_voxels = as.integer(minimum_component_voxels),
      closing_iterations = as.integer(closing_iterations),
      fill_voxel_holes = fill_voxel_holes,
      distance_upsampling = as.integer(distance_upsampling),
      preserve_volume = preserve_volume,
      small_region_method = small_region_method,
      small_region_threshold = as.integer(small_region_threshold),
      topology_correction = topology_correction,
      closing_radius = closing_radius,
      max_closing_radius = max_closing_radius,
      overwrite = overwrite
    )
    return(reticulate::py_to_r(result))
  }

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
    if (utils::packageVersion("reticulate") >= "1.41.0") {
      reticulate::py_require(c(
        "nibabel", "numpy", "scipy", "scikit-image", "vtk"
      ))
    }
    reticulate::source_python(
      nifti_surface_python_path(),
      envir = nifti_surface_python_env
    )
  }
  invisible(TRUE)
}
