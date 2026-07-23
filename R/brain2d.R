# Read bundled camera positions when available.
brain2d_default_camera_positions <- function() {
  candidates <- c(
    system.file("extdata", "camera_positions.rds", package = "ggbrat"),
    file.path("inst", "extdata", "camera_positions.rds")
  )
  path <- candidates[file.exists(candidates)][1]

  if (is.na(path) || !nzchar(path)) {
    return(NULL)
  }

  readRDS(path)
}

brain2d_sequence_to_list <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }

  x_r <- tryCatch(reticulate::py_to_r(x), error = function(e) x)

  if (is.environment(x_r)) {
    return(as.list(reticulate::iterate(x_r)))
  }

  if (is.atomic(x_r)) {
    return(as.list(x_r))
  }

  if (is.list(x_r)) {
    return(x_r)
  }

  as.list(x_r)
}

brain2d_normalize_camera_position <- function(camera_position) {
  if (is.null(camera_position)) {
    return(NULL)
  }

  camera_position <- brain2d_sequence_to_list(camera_position)

  lapply(camera_position, function(component) {
    component <- brain2d_sequence_to_list(component)
    as.numeric(unlist(component, use.names = FALSE))
  })
}

brain2d_normalize_camera_positions <- function(camera_positions) {
  if (is.null(camera_positions)) {
    return(NULL)
  }

  stats::setNames(
    lapply(camera_positions, brain2d_normalize_camera_position),
    names(camera_positions)
  )
}

#' Build 2D atlas views from cortical or labelled surface meshes
#'
#' `brain_views()` is the package-facing orchestration layer for the 2D atlas
#' workflow. By default it expects pre-recorded camera presets so atlas builds
#' are deterministic. Set `interactive = TRUE` when you need to record new
#' camera positions for a custom view. After positioning the mesh, click the
#' green **Use this view** control or press `U` to save the camera and close the
#' viewer.
#'
#' @param annot_path For cortical surfaces, a path to a single `.annot` or
#'   `.label.gii` file, or a named vector/list with `left` and `right`. May be `NULL` when
#'   `mesh_path` is supplied.
#' @param mesh_path Optional path to a labelled VTK/VTP mesh, or a named pair
#'   with elements `left` and `right`. A pair follows the same mirrored-camera
#'   workflow as cortical hemispheres; a single mesh is rendered once per view.
#' @param region_array Name of the mesh point-data array containing region
#'   identifiers. Set this to another one-component point array, such as
#'   `"Label"`, when importing a mesh that does not contain `"region"`.
#' @param color_array Optional mesh point-data array containing region colors.
#'   When it is absent, deterministic colors are generated automatically.
#' @param label_array Deprecated alias for `region_array`.
#' @param mesh_hemisphere Value stored in the output `hemisphere` column for a
#'   generic mesh.
#' @param add_cortex Whether to add separately projected fsaverage surfaces as
#'   a glass-brain context layer. This currently requires paired meshes.
#' @param cortex_surf_dir Directory containing the left and right FreeSurfer
#'   cortical surfaces. The default uses `surf_dir`.
#' @param cortex_surface FreeSurfer surface name used for the glass layer.
#' @param cortex_surface_path Optional named `left`/`right` paths to FreeSurfer
#'   or GIFTI surfaces for the glass layer. Each hemisphere may alternatively
#'   contain two paths to blend. Overrides `cortex_surf_dir` and
#'   `cortex_surface`.
#' @param cortex_point_method How visible cortical points are retained:
#'   `"density"` keeps projected structural concentrations, `"sample"` takes
#'   a reproducible random sample, and `"all"` retains every visible vertex.
#' @param cortex_point_fraction Fraction of visible cortical vertices retained
#'   when `cortex_point_method = "sample"`.
#' @param cortex_density_k Number of neighbors used for projected cortical
#'   density estimation.
#' @param cortex_density_keep_quantile Fraction of the densest projected
#'   cortical vertices retained.
#' @param cortex_max_points Maximum density-filtered points retained per
#'   hemisphere and view. Use `NULL` for no cap.
#' @param include_cortex_silhouette Whether to return a cortical outline layer.
#' @param cortex_preview_opacity Opacity of the cortical surfaces shown only
#'   while interactively choosing a camera. This preview does not participate
#'   in target-mesh visibility calculations.
#' @param hemi Hemisphere to process for cortical surfaces.
#' @param n_views Number of views to build. If `camera_positions` is supplied,
#'   this defaults to `length(camera_positions)`.
#' @param view_names Optional names for the views.
#' @param camera_positions Optional list of saved PyVista camera positions.
#'   When `NULL` in non-interactive mode, bundled presets are used and the
#'   first `n_views` presets are selected.
#' @param interactive Whether to capture camera positions interactively.
#' @param surf_dir Directory containing FreeSurfer surface files. When `NULL`,
#'   the requested fsaverage surfaces are downloaded to and resolved from the
#'   user-specific ggbrat cache.
#' @param surface A single surface name or a pair of surfaces to blend.
#' @param surface_path Optional named `left`/`right` paths to FreeSurfer or
#'   `.surf.gii` files. Supply a named list in which each hemisphere contains
#'   two paths to blend explicit files. Overrides `surf_dir` and `surface`.
#' @param surf_blend_ratio Weight assigned to the first surface when `surface`
#'   or each `surface_path` hemisphere contains two surfaces. The second surface
#'   receives weight `1 - surf_blend_ratio`.
#' @param window_size PyVista window size.
#' @param include_silhouette Whether to compute and return silhouettes.
#' @param sil_decimate Fraction of silhouette polyline points to remove.
#' @param silhouette_min_length Minimum retained silhouette-path length, or
#'   `"auto"` for approximately one output pixel.
#' @param silhouette_tolerance Line-simplification tolerance, or `"auto"` for
#'   approximately half an output pixel.
#' @param keep_z_coord Whether visible vertices should retain projected depth as
#'   a third coordinate. The returned geometry is `MULTIPOINT Z`; Z is display
#'   depth in the selected camera projection, not the original surface-space Z.
#'
#' @return A list with `atlas`, optional `silhouette`, `camera_positions`, and,
#'   when requested, `cortex` and `cortex_silhouette` glass-brain layers.
#' @export
brain_views <- function(
  annot_path = NULL,
  hemi = c("both", "left", "right"),
  n_views = NULL,
  view_names = NULL,
  camera_positions = NULL,
  interactive = FALSE,
  surf_dir = NULL,
  surface = "pial",
  surface_path = NULL,
  surf_blend_ratio = NULL,
  window_size = c(800L, 600L),
  include_silhouette = FALSE,
  sil_decimate = 0.1,
  silhouette_min_length = "auto",
  silhouette_tolerance = "auto",
  mesh_path = NULL,
  region_array = "region",
  color_array = "color",
  mesh_hemisphere = "subcortical",
  add_cortex = FALSE,
  cortex_surf_dir = surf_dir,
  cortex_surface = "pial",
  cortex_surface_path = NULL,
  cortex_point_method = c("density", "sample", "all"),
  cortex_point_fraction = 0.05,
  cortex_density_k = 15L,
  cortex_density_keep_quantile = 0.15,
  cortex_max_points = 10000L,
  include_cortex_silhouette = TRUE,
  cortex_preview_opacity = 0.1,
  keep_z_coord = FALSE,
  label_array = NULL
) {
  if (!is.null(label_array)) {
    warning("`label_array` is deprecated; use `region_array`.", call. = FALSE)
    region_array <- label_array
  }
  if (!is.character(region_array) || length(region_array) != 1L ||
      is.na(region_array) || !nzchar(region_array)) {
    stop("`region_array` must be one non-empty string.", call. = FALSE)
  }
  hemi <- match.arg(hemi)
  cortex_point_method <- match.arg(cortex_point_method)
  window_size <- as.integer(window_size)
  if (!is.logical(keep_z_coord) || length(keep_z_coord) != 1L ||
      is.na(keep_z_coord)) {
    stop("`keep_z_coord` must be TRUE or FALSE.", call. = FALSE)
  }

  using_default_camera_positions <- FALSE
  if (interactive) {
    camera_positions <- NULL
  } else if (is.null(camera_positions)) {
    camera_positions <- brain2d_default_camera_positions()
    using_default_camera_positions <- !is.null(camera_positions)
  }

  if (!is.null(camera_positions)) {
    camera_positions <- brain2d_normalize_camera_positions(camera_positions)
  }

  view_spec <- brain2d_prepare_views(
    n_views = n_views,
    view_names = view_names,
    camera_positions = camera_positions,
    interactive = interactive,
    subset_camera_positions = using_default_camera_positions
  )

  brain2d_load_python()
  generic_mesh <- !is.null(mesh_path)
  paired_mesh <- generic_mesh && length(mesh_path) == 2L
  if (generic_mesh) {
    if (!is.character(mesh_path) || !length(mesh_path) %in% c(1L, 2L) ||
        any(!nzchar(mesh_path))) {
      stop("`mesh_path` must contain one path or a named `left`/`right` pair.", call. = FALSE)
    }
    if (paired_mesh && (!all(c("left", "right") %in% names(mesh_path)))) {
      stop("A two-element `mesh_path` must be named `left` and `right`.", call. = FALSE)
    }
    missing_meshes <- mesh_path[!file.exists(mesh_path)]
    if (length(missing_meshes)) {
      stop("Mesh file not found: ", missing_meshes[[1]], call. = FALSE)
    }
  } else {
    if (is.null(annot_path)) {
      stop("Supply either `annot_path` or `mesh_path`.", call. = FALSE)
    }
    surface_paths <- if (is.null(surface_path)) {
      brain2d_surface_paths(
        surf_dir = surf_dir,
        surface = surface,
        surf_blend_ratio = surf_blend_ratio
      )
    } else {
      brain2d_resolve_explicit_surfaces(
        brain2d_validate_paired_paths(surface_path, "surface_path", hemi),
        surf_blend_ratio
      )
    }
  }
  if (add_cortex && !paired_mesh) {
    stop("`add_cortex = TRUE` currently requires a named left/right `mesh_path` pair.", call. = FALSE)
  }
  if (!is.numeric(cortex_point_fraction) || length(cortex_point_fraction) != 1L ||
      is.na(cortex_point_fraction) || cortex_point_fraction <= 0 ||
      cortex_point_fraction > 1) {
    stop("`cortex_point_fraction` must be one number in (0, 1].", call. = FALSE)
  }
  if (!is.numeric(cortex_density_k) || length(cortex_density_k) != 1L ||
      is.na(cortex_density_k) || cortex_density_k < 1 ||
      cortex_density_k != as.integer(cortex_density_k)) {
    stop("`cortex_density_k` must be a positive integer.", call. = FALSE)
  }
  if (!is.numeric(cortex_density_keep_quantile) ||
      length(cortex_density_keep_quantile) != 1L ||
      is.na(cortex_density_keep_quantile) || cortex_density_keep_quantile <= 0 ||
      cortex_density_keep_quantile > 1) {
    stop("`cortex_density_keep_quantile` must be one number in (0, 1].", call. = FALSE)
  }
  if (!is.null(cortex_max_points) &&
      (!is.numeric(cortex_max_points) || length(cortex_max_points) != 1L ||
       is.na(cortex_max_points) || cortex_max_points < 1 ||
       cortex_max_points != as.integer(cortex_max_points))) {
    stop("`cortex_max_points` must be NULL or a positive integer.", call. = FALSE)
  }
  if (!is.numeric(cortex_preview_opacity) ||
      length(cortex_preview_opacity) != 1L ||
      is.na(cortex_preview_opacity) || cortex_preview_opacity <= 0 ||
      cortex_preview_opacity > 1) {
    stop("`cortex_preview_opacity` must be one number in (0, 1].", call. = FALSE)
  }
  if (add_cortex) {
    cortex_paths <- if (is.null(cortex_surface_path)) {
      brain2d_surface_paths(
        surf_dir = cortex_surf_dir,
        surface = cortex_surface,
        surf_blend_ratio = NULL
      )
    } else {
      brain2d_resolve_explicit_surfaces(
        brain2d_validate_paired_paths(
          cortex_surface_path, "cortex_surface_path", "both"
        ),
        0.5
      )
    }
    missing_cortex <- unlist(cortex_paths)[!file.exists(unlist(cortex_paths))]
    if (length(missing_cortex)) {
      stop("Cortical surface not found: ", missing_cortex[[1]], call. = FALSE)
    }
  }

  out <- list()
  out_sil <- if (include_silhouette) list() else NULL
  out_cortex <- if (add_cortex) list() else NULL
  out_cortex_sil <- if (add_cortex && include_cortex_silhouette) list() else NULL
  captured_cameras <- vector("list", view_spec$n_views)

  for (index in seq_len(view_spec$n_views)) {
    preset_camera <- if (interactive) NULL else view_spec$camera_positions[[index]]
    view_label <- view_spec$view_names[[index]]

    if (paired_mesh) {
      left_res <- brain2d_python_env$extract_visible_2d_vtk(
        mesh_path[["left"]],
        region_array = region_array,
        color_array = color_array,
        mirror_camera = preset_camera,
        window_size = window_size,
        return_silhouette = include_silhouette,
        sil_decimate = sil_decimate,
        hemisphere = "left",
        preview_surface_paths = if (interactive && add_cortex) {
          unname(unlist(cortex_paths))
        } else {
          NULL
        },
        preview_opacity = cortex_preview_opacity,
        keep_z_coord = keep_z_coord
      )
      captured_cameras[[index]] <- left_res[[2]]
      out[[length(out) + 1L]] <- brain2d_tag_view(left_res[[1]], "left", view_label, index)
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
          left_res[[3]], "left", view_label, index, window_size,
          silhouette_min_length, silhouette_tolerance
        )
      }

      right_res <- brain2d_python_env$extract_visible_2d_vtk(
        mesh_path[["right"]],
        region_array = region_array,
        color_array = color_array,
        mirror_camera = captured_cameras[[index]],
        window_size = window_size,
        return_silhouette = include_silhouette,
        sil_decimate = sil_decimate,
        hemisphere = "right",
        keep_z_coord = keep_z_coord
      )
      out[[length(out) + 1L]] <- brain2d_tag_view(right_res[[1]], "right", view_label, index)
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
          right_res[[3]], "right", view_label, index, window_size,
          silhouette_min_length, silhouette_tolerance
        )
      }
    } else if (generic_mesh) {
      mesh_res <- brain2d_python_env$extract_visible_2d_vtk(
        mesh_path,
        region_array = region_array,
        color_array = color_array,
        mirror_camera = preset_camera,
        window_size = window_size,
        return_silhouette = include_silhouette,
        sil_decimate = sil_decimate,
        hemisphere = NULL,
        keep_z_coord = keep_z_coord
      )
      captured_cameras[[index]] <- mesh_res[[2]]
      out[[length(out) + 1L]] <- brain2d_tag_view(
        mesh_res[[1]], mesh_hemisphere, view_label, index
      )
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
          mesh_res[[3]], mesh_hemisphere, view_label, index, window_size,
          silhouette_min_length, silhouette_tolerance
        )
      }
    } else if (hemi %in% c("left", "both")) {
      left_res <- brain2d_python_env$extract_visible_2d(
        surface_paths$left,
        brain2d_annot_path(annot_path, "left"),
        hemisphere = "left",
        mirror_camera = preset_camera,
        window_size = window_size,
        return_silhouette = include_silhouette,
        sil_decimate = sil_decimate,
        keep_z_coord = keep_z_coord
      )
      captured_cameras[[index]] <- left_res[[2]]
      out[[length(out) + 1L]] <- brain2d_tag_view(left_res[[1]], "left", view_label, index)
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
          left_res[[3]], "left", view_label, index, window_size,
          silhouette_min_length, silhouette_tolerance
        )
      }

      if (hemi == "both") {
        right_res <- brain2d_python_env$extract_visible_2d(
          surface_paths$right,
          brain2d_annot_path(annot_path, "right"),
          hemisphere = "right",
          mirror_camera = captured_cameras[[index]],
          window_size = window_size,
          return_silhouette = include_silhouette,
          sil_decimate = sil_decimate,
          keep_z_coord = keep_z_coord
        )
        out[[length(out) + 1L]] <- brain2d_tag_view(right_res[[1]], "right", view_label, index)
        if (include_silhouette) {
          out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
            right_res[[3]], "right", view_label, index, window_size,
            silhouette_min_length, silhouette_tolerance
          )
        }
      }
    } else {
      right_res <- brain2d_python_env$extract_visible_2d(
        surface_paths$right,
        brain2d_annot_path(annot_path, "right"),
        hemisphere = "right",
        mirror_camera = preset_camera,
        window_size = window_size,
        return_silhouette = include_silhouette,
        sil_decimate = sil_decimate,
        keep_z_coord = keep_z_coord
      )
      captured_cameras[[index]] <- right_res[[2]]
      out[[length(out) + 1L]] <- brain2d_tag_view(right_res[[1]], "right", view_label, index)
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
          right_res[[3]], "right", view_label, index, window_size,
          silhouette_min_length, silhouette_tolerance
        )
      }
    }

    if (add_cortex) {
      python_point_fraction <- if (cortex_point_method == "sample") {
        cortex_point_fraction
      } else {
        1
      }
      left_cortex <- brain2d_python_env$extract_visible_2d_surface(
        cortex_paths$left,
        hemisphere = "left",
        mirror_camera = captured_cameras[[index]],
        window_size = window_size,
        point_fraction = python_point_fraction,
        random_seed = index,
        return_silhouette = include_cortex_silhouette,
        sil_decimate = sil_decimate,
        keep_z_coord = keep_z_coord
      )
      right_cortex <- brain2d_python_env$extract_visible_2d_surface(
        cortex_paths$right,
        hemisphere = "right",
        mirror_camera = captured_cameras[[index]],
        window_size = window_size,
        point_fraction = python_point_fraction,
        random_seed = index,
        return_silhouette = include_cortex_silhouette,
        sil_decimate = sil_decimate,
        keep_z_coord = keep_z_coord
      )
      left_cortex_df <- brain2d_filter_cortex_points(
        left_cortex[[1]], cortex_point_method, cortex_density_k,
        cortex_density_keep_quantile, cortex_max_points
      )
      right_cortex_df <- brain2d_filter_cortex_points(
        right_cortex[[1]], cortex_point_method, cortex_density_k,
        cortex_density_keep_quantile, cortex_max_points
      )
      out_cortex[[length(out_cortex) + 1L]] <- brain2d_tag_view(
        left_cortex_df, "left", view_label, index
      )
      out_cortex[[length(out_cortex) + 1L]] <- brain2d_tag_view(
        right_cortex_df, "right", view_label, index
      )
      if (include_cortex_silhouette) {
        out_cortex_sil[[length(out_cortex_sil) + 1L]] <- brain2d_tag_silhouette(
          left_cortex[[3]], "left", view_label, index, window_size,
          silhouette_min_length, silhouette_tolerance
        )
        out_cortex_sil[[length(out_cortex_sil) + 1L]] <- brain2d_tag_silhouette(
          right_cortex[[3]], "right", view_label, index, window_size,
          silhouette_min_length, silhouette_tolerance
        )
      }
    }
  }

  atlas <- brain2d_vertices_to_sf(do.call(rbind, out))
  result <- list(
    atlas = atlas,
    camera_positions = brain2d_normalize_camera_positions(
      stats::setNames(captured_cameras, view_spec$view_names)
    )
  )

  if (include_silhouette) {
    result$silhouette <- do.call(rbind, out_sil)
  }
  if (add_cortex) {
    result$cortex <- brain2d_vertices_to_sf(do.call(rbind, out_cortex))
    if (include_cortex_silhouette) {
      result$cortex_silhouette <- do.call(rbind, out_cortex_sil)
    }
  }

  result
}

#' Capture camera presets for later atlas builds
#'
#' @inheritParams brain_views
#' @param preset_hemi Hemisphere used to capture camera positions.
#'
#' @return A named list of camera positions.
#' @export
capture_brain_view_presets <- function(
  annot_path = NULL,
  preset_hemi = c("left", "right"),
  n_views = 1,
  view_names = NULL,
  surf_dir = NULL,
  surface = "pial",
  surface_path = NULL,
  surf_blend_ratio = NULL,
  window_size = c(800L, 600L),
  sil_decimate = 0.1,
  mesh_path = NULL,
  region_array = "region",
  color_array = "color",
  mesh_hemisphere = "subcortical",
  label_array = NULL
) {
  if (!is.null(label_array)) {
    warning("`label_array` is deprecated; use `region_array`.", call. = FALSE)
    region_array <- label_array
  }
  preset_hemi <- match.arg(preset_hemi)
  result <- brain_views(
    annot_path = annot_path,
    hemi = preset_hemi,
    n_views = n_views,
    view_names = view_names,
    interactive = TRUE,
    surf_dir = surf_dir,
    surface = surface,
    surface_path = surface_path,
    surf_blend_ratio = surf_blend_ratio,
    window_size = window_size,
    include_silhouette = FALSE,
    sil_decimate = sil_decimate,
    mesh_path = mesh_path,
    region_array = region_array,
    color_array = color_array,
    mesh_hemisphere = mesh_hemisphere
  )

  result$camera_positions
}

#' Convert silhouette segments into merged sf lines
#'
#' @param sil Data frame with columns `x0`, `y0`, `x1`, `y1`.
#' @param min_length Minimum retained path length, or `"auto"` for one pixel.
#' @param simplify_tolerance Simplification tolerance, or `"auto"` for half a
#'   pixel.
#' @param window_size Render window dimensions used by automatic thresholds.
#'
#' @return An `sf` object.
#' @export
silhouette_sf <- function(
  sil,
  min_length = "auto",
  simplify_tolerance = "auto",
  window_size = c(800L, 600L)
) {
  if (is.null(sil) || nrow(sil) == 0L) {
    return(sf::st_sf(
      group_id = integer(),
      geometry = sf::st_sfc(crs = sf::NA_crs_)
    ))
  }

  window_size <- as.numeric(window_size)
  if (length(window_size) != 2L || any(!is.finite(window_size)) || any(window_size <= 0)) {
    stop("`window_size` must contain two positive numbers.", call. = FALSE)
  }
  pixel_size <- 2 / max(window_size)
  resolve_threshold <- function(value, auto_value, name) {
    if (identical(value, "auto")) return(auto_value)
    if (!is.numeric(value) || length(value) != 1L || is.na(value) || value < 0) {
      stop("`", name, "` must be `\"auto\"` or one non-negative number.", call. = FALSE)
    }
    value
  }
  min_length <- resolve_threshold(min_length, pixel_size, "min_length")
  simplify_tolerance <- resolve_threshold(
    simplify_tolerance, pixel_size / 2, "simplify_tolerance"
  )

  same_point <- function(x0, y0, x1, y1) {
    isTRUE(all.equal(c(x0, y0), c(x1, y1), tolerance = 1e-10))
  }
  starts_new <- logical(nrow(sil))
  starts_new[[1]] <- TRUE
  if (nrow(sil) > 1L) {
    for (index in 2:nrow(sil)) {
      starts_new[[index]] <- !same_point(
        sil$x0[[index]], sil$y0[[index]],
        sil$x1[[index - 1L]], sil$y1[[index - 1L]]
      )
    }
  }
  group_id <- cumsum(starts_new)
  groups <- split(seq_len(nrow(sil)), group_id)
  lines <- lapply(groups, function(indices) {
    xy <- rbind(
      c(sil$x0[[indices[[1]]]], sil$y0[[indices[[1]]]]),
      cbind(sil$x1[indices], sil$y1[indices])
    )
    xy <- xy[c(TRUE, rowSums(abs(diff(xy))) > 1e-12), , drop = FALSE]
    if (nrow(xy) < 2L) return(NULL)
    sf::st_linestring(xy, dim = "XY")
  })
  lines <- Filter(Negate(is.null), lines)
  if (!length(lines)) {
    return(sf::st_sf(group_id = integer(), geometry = sf::st_sfc(crs = sf::NA_crs_)))
  }

  geometry <- sf::st_sfc(lines, crs = sf::NA_crs_)
  if (simplify_tolerance > 0) {
    geometry <- sf::st_simplify(geometry, dTolerance = simplify_tolerance)
  }
  result <- sf::st_sf(group_id = seq_along(geometry), geometry = geometry)
  result$geom_length <- as.numeric(sf::st_length(result))
  result[result$geom_length >= min_length, , drop = FALSE]
}

#' Backward-compatible alias for the earlier misspelled helper
#' @rdname silhouette_sf
#' @export
silhoutte_sf <- silhouette_sf

#' Shift atlas views into a plotting grid
#'
#' @param sf_obj An `sf` object with `hemisphere` and `view` columns, or the
#'   raw list returned by `brain_views()`.
#' @param cell_dx Horizontal spacing between cells.
#' @param cell_dy Vertical spacing between cells.
#' @param n_cols Number of columns in the output grid.
#'
#' @return An `sf` object with shifted geometry, or a raw atlas list with
#'   shifted `atlas` and optional shifted `silhouette`.
#' @export
shift_brain_views <- function(
  sf_obj,
  cell_dx = 1.5,
  cell_dy = -1,
  n_cols = 2
) {
  shift_one <- function(x) {
    x <- sf::st_as_sf(x)

    if ("int_view" %in% names(x)) {
      view_index <- x$int_view - 1L
    } else {
      view_levels <- unique(x$view)
      view_index <- match(x$view, view_levels) - 1L
    }

    x <- x |>
      dplyr::mutate(
        hemi_n = ifelse(.data$hemisphere == "right", 1L, 0L),
        idx = view_index * n_cols + .data$hemi_n,
        row = .data$idx %/% n_cols,
        col = .data$idx %% n_cols,
        shift_x = .data$col * cell_dx,
        shift_y = .data$row * cell_dy
      )

    shifted_geom <- mapply(
      function(geom, dx, dy) {
        coordinate_names <- colnames(sf::st_coordinates(geom))
        offset <- if ("Z" %in% coordinate_names) c(dx, dy, 0) else c(dx, dy)
        geom + offset
      },
      x$geometry,
      x$shift_x,
      x$shift_y,
      SIMPLIFY = FALSE
    )

    x$geometry <- sf::st_sfc(shifted_geom, crs = sf::st_crs(x))
    dplyr::select(
      x,
      -dplyr::all_of(c("hemi_n", "idx", "row", "col", "shift_x", "shift_y"))
    )
  }

  if (is.list(sf_obj) && "atlas" %in% names(sf_obj)) {
    shift_layers <- c("atlas", "silhouette", "cortex", "cortex_silhouette")
    for (layer in shift_layers) {
      if (layer %in% names(sf_obj) && !is.null(sf_obj[[layer]])) {
        sf_obj[[layer]] <- shift_one(sf_obj[[layer]])
      }
    }
    return(sf_obj)
  }

  shift_one(sf_obj)
}

#' Estimate alpha radius for an alpha hull
#' @param xy Matrix of scaled coordinates.
#' @param k Number of nearest neighbours.
#' @param factor Scaling factor for the median distance.
#' @return Numeric alpha radius.
#' @export
auto_alpha <- function(xy, k = 1, factor = 3) {
  d <- FNN::get.knn(xy, k = k + 1)$nn.dist[, 2:(k + 1), drop = FALSE]
  base <- if (k == 1) d else rowMeans(d)
  factor * stats::median(base)
}

#' Convert a point cloud to polygonal geometry using an alpha hull
#' @param pts Point geometry.
#' @param alpha Alpha radius or `"auto"`.
#' @param smoothing_factor Scaling applied when `alpha = "auto"`.
#' @return An `sfc` geometry vector.
#' @export
ashape_polygon_sf <- function(pts, alpha = "auto", smoothing_factor = 3) {
  xy <- sf::st_coordinates(pts)
  xy <- xy[!duplicated(xy), 1:2, drop = FALSE]

  empty_polygon <- function() {
    sf::st_sfc(sf::st_polygon(), crs = sf::st_crs(pts))
  }

  if (nrow(xy) < 3L) return(empty_polygon())

  coordinate_scale <- apply(xy, 2L, stats::sd)
  coordinate_scale[!is.finite(coordinate_scale) | coordinate_scale == 0] <- 1
  xy_scaled <- sweep(xy, 2L, colMeans(xy), "-")
  xy_scaled <- sweep(xy_scaled, 2L, coordinate_scale, "/")

  radius <- if (identical(alpha, "auto")) {
    auto_alpha(xy_scaled, k = 1, factor = smoothing_factor)
  } else {
    alpha
  }

  polygonize_radius <- function(candidate_radius) {
    a <- tryCatch(
      alphahull::ahull(xy_scaled, alpha = candidate_radius),
      error = function(error) NULL
    )
    if (is.null(a)) return(NULL)

    edges <- a[["ashape.obj"]][["edges"]]
    if (is.null(edges) || nrow(edges) == 0L) return(NULL)

    idx <- edges[, c("ind1", "ind2"), drop = FALSE]
    lines <- lapply(seq_len(nrow(idx)), function(i) {
      sf::st_linestring(rbind(xy[idx[i, 1], ], xy[idx[i, 2], ]))
    })

    lines <- sf::st_sfc(lines, crs = sf::st_crs(pts))
    polys <- suppressWarnings(
      lines |>
        sf::st_union() |>
        sf::st_line_merge() |>
        sf::st_polygonize() |>
        sf::st_collection_extract("POLYGON")
    )
    if (length(polys) == 0L || all(sf::st_is_empty(polys))) return(NULL)

    if (length(polys) > 1L) {
      polys <- polys |>
        sf::st_union() |>
        sf::st_cast("MULTIPOLYGON")
    }
    polys
  }

  retry_multipliers <- c(1, 1.5, 2, 3, 5)
  for (multiplier in retry_multipliers) {
    polys <- polygonize_radius(radius * multiplier)
    if (!is.null(polys)) return(polys)
  }

  fallback <- suppressWarnings(
    sf::st_convex_hull(sf::st_combine(sf::st_sfc(
      lapply(seq_len(nrow(xy)), function(i) sf::st_point(xy[i, ])),
      crs = sf::st_crs(pts)
    )))
  )
  if (length(fallback) == 1L &&
      !sf::st_is_empty(fallback) &&
      as.character(sf::st_geometry_type(fallback)) %in% c("POLYGON", "MULTIPOLYGON")) {
    return(fallback)
  }

  empty_polygon()
}

#' Filter points by local kNN density
#' @param X Coordinate matrix.
#' @param k Number of nearest neighbours.
#' @param keep_quantile Quantile of dense points to keep.
#' @param dim Point dimensionality.
#' @return A list with filtered points and density diagnostics.
#' @export
knn_density_filter <- function(X, k = 10, keep_quantile = 0.5, dim = 2) {
  nn <- FNN::get.knnx(X, X, k = k + 1)
  r_k <- nn$nn.dist[, k + 1]
  rho <- switch(
    as.character(dim),
    "2" = k / (pi * (r_k^dim)),
    "3" = k / ((4 / 3) * pi * (r_k^dim)),
    1 / r_k
  )

  threshold <- stats::quantile(rho, probs = 1 - keep_quantile, na.rm = TRUE)
  keep <- rho >= threshold

  list(
    X_filtered = X[keep, , drop = FALSE],
    keep = keep,
    rho = rho
  )
}

brain2d_prepare_views <- function(
  n_views,
  view_names,
  camera_positions,
  interactive,
  subset_camera_positions = FALSE
) {
  if (is.null(n_views)) {
    n_views <- if (is.null(camera_positions)) 1L else length(camera_positions)
  }

  n_views <- as.integer(n_views)
  if (length(n_views) != 1L || is.na(n_views) || n_views < 1L) {
    stop("`n_views` must be a single positive integer.", call. = FALSE)
  }

  if (!interactive && is.null(camera_positions)) {
    stop(
      "Preset workflow requires `camera_positions`. Use `interactive = TRUE` to capture new presets.",
      call. = FALSE
    )
  }

  if (subset_camera_positions && !is.null(camera_positions) &&
      length(camera_positions) >= n_views) {
    camera_positions <- camera_positions[seq_len(n_views)]
  }

  if (!is.null(camera_positions) && length(camera_positions) != n_views) {
    stop("`camera_positions` must have length `n_views`.", call. = FALSE)
  }

  if (is.null(view_names)) {
    if (!is.null(names(camera_positions)) && all(nzchar(names(camera_positions)))) {
      view_names <- names(camera_positions)
    } else {
      view_names <- paste0("view_", seq_len(n_views))
    }
  }

  if (length(view_names) != n_views) {
    stop("`view_names` must have one entry per view.", call. = FALSE)
  }

  list(
    n_views = n_views,
    view_names = as.character(view_names),
    camera_positions = camera_positions
  )
}

brain2d_python_env <- new.env(parent = baseenv())

brain2d_python_path <- function() {
  candidates <- c(
    system.file("python", "brain2d.py", package = "ggbrat"),
    file.path("inst", "python", "brain2d.py")
  )
  path <- candidates[file.exists(candidates)][1]

  if (is.na(path) || !nzchar(path)) {
    stop("Could not locate `brain2d.py`.", call. = FALSE)
  }

  path
}

brain2d_load_python <- function() {
  if (!exists("extract_visible_2d", envir = brain2d_python_env, inherits = FALSE)) {
    if (utils::packageVersion("reticulate") >= "1.41.0") {
      reticulate::py_require(c("nibabel", "numpy", "pandas", "pyvista", "vtk"))
    }
    reticulate::source_python(
      brain2d_python_path(),
      envir = brain2d_python_env
    )
  }
  invisible(TRUE)
}

brain2d_surface_paths <- function(surf_dir, surface, surf_blend_ratio) {
  if (is.null(surf_dir)) {
    if (!length(surface) %in% c(1L, 2L)) {
      stop("`surface` must contain one surface name or a pair to blend.", call. = FALSE)
    }
    downloaded <- lapply(surface, function(name) {
      download_surface(paste0("fsaverage_", name), type = "cortical")
    })
    if (length(downloaded) == 1L) return(as.list(downloaded[[1L]]))
    paths <- list(
      left = vapply(downloaded, `[[`, character(1), "left"),
      right = vapply(downloaded, `[[`, character(1), "right")
    )
    return(brain2d_resolve_explicit_surfaces(paths, surf_blend_ratio))
  }
  if (length(surface) == 2L) {
    if (is.null(surf_blend_ratio)) {
      surf_blend_ratio <- 0.5
    }

    blend_paths <- brain2d_python_env$blend_hemispheres(
      surf_dir = surf_dir,
      surface1 = surface[[1]],
      surface2 = surface[[2]],
      output_dir = tempdir(),
      ratio = surf_blend_ratio
    )

    return(list(left = blend_paths[[1]], right = blend_paths[[2]]))
  }

  if (length(surface) != 1L) {
    stop("`surface` must contain one surface name or a pair to blend.", call. = FALSE)
  }

  list(
    left = file.path(surf_dir, paste0("lh.", surface)),
    right = file.path(surf_dir, paste0("rh.", surface))
  )
}

brain2d_validate_paired_paths <- function(paths, name, hemi = "both") {
  if (is.character(paths)) {
    if (!length(paths) || length(paths) > 2L || anyNA(paths) || any(!nzchar(paths))) {
      stop("`", name, "` must contain one path or a named left/right pair.", call. = FALSE)
    }
    if (length(paths) == 1L) {
      if (identical(hemi, "both")) {
        stop("`", name, "` must provide named left and right paths for both hemispheres.",
             call. = FALSE)
      }
      paths <- stats::setNames(list(paths), hemi)
    } else {
      if (!all(c("left", "right") %in% names(paths))) {
        stop("A two-element `", name, "` must be named `left` and `right`.", call. = FALSE)
      }
      paths <- as.list(paths[c("left", "right")])
    }
  } else if (is.list(paths)) {
    required <- if (identical(hemi, "both")) c("left", "right") else hemi
    if (!all(required %in% names(paths))) {
      stop("`", name, "` must contain the named hemisphere",
           if (length(required) > 1L) "s `left` and `right`." else paste0(" `", hemi, "`."),
           call. = FALSE)
    }
    paths <- paths[required]
  } else {
    stop("`", name, "` must be a path vector or a named hemisphere list.", call. = FALSE)
  }
  valid <- vapply(paths, function(value) {
    is.character(value) && length(value) %in% c(1L, 2L) &&
      !anyNA(value) && all(nzchar(value))
  }, logical(1))
  if (!all(valid)) {
    stop(
      "Each hemisphere in `", name,
      "` must contain one surface path or two paths to blend.",
      call. = FALSE
    )
  }
  missing <- unlist(paths, use.names = FALSE)
  missing <- missing[!file.exists(missing)]
  if (length(missing)) stop("Surface file not found: ", missing[[1]], call. = FALSE)
  paths
}

brain2d_resolve_explicit_surfaces <- function(paths, ratio = NULL) {
  needs_blend <- lengths(paths) == 2L
  if (!any(needs_blend)) return(paths)
  if (is.null(ratio)) ratio <- 0.5
  if (!is.numeric(ratio) || length(ratio) != 1L || is.na(ratio) ||
      !is.finite(ratio) || ratio < 0 || ratio > 1) {
    stop("`surf_blend_ratio` must be one number between 0 and 1.", call. = FALSE)
  }
  for (hemisphere in names(paths)[needs_blend]) {
    output <- tempfile(paste0("ggbrat-", hemisphere, "-blend-"), fileext = ".surf")
    paths[[hemisphere]] <- brain2d_python_env$blend_surface_files(
      unname(paths[[hemisphere]]), output, ratio = ratio
    )
  }
  paths
}

brain2d_annot_path <- function(annot_path, hemisphere) {
  if (length(annot_path) == 1L) {
    return(annot_path[[1]])
  }

  idx <- c(left = "left", right = "right")[[hemisphere]]
  if (!idx %in% names(annot_path)) {
    stop("When `annot_path` has length > 1 it must be named `left` and `right`.", call. = FALSE)
  }

  annot_path[[idx]]
}

brain2d_tag_view <- function(df, hemisphere, view_label, view_index) {
  df$hemisphere <- hemisphere
  df$view <- view_label
  df$int_view <- view_index
  df
}

brain2d_tag_silhouette <- function(
  df,
  hemisphere,
  view_label,
  view_index,
  window_size = c(800L, 600L),
  min_length = "auto",
  simplify_tolerance = "auto"
) {
  sil <- silhouette_sf(
    df,
    min_length = min_length,
    simplify_tolerance = simplify_tolerance,
    window_size = window_size
  )
  sil$hemisphere <- hemisphere
  sil$view <- view_label
  sil$int_view <- view_index
  sil
}

brain2d_vertices_to_sf <- function(out) {
  coordinate_columns <- if ("z" %in% names(out)) c("x", "y", "z") else c("x", "y")
  pts_vert <- sf::st_as_sfc(
    sf::st_as_sf(out, coords = coordinate_columns, crs = NA)
  )
  pts_vert <- sf::st_sf(
    geometry = pts_vert,
    color = out$color,
    region = out$region,
    hemisphere = out$hemisphere,
    view = out$view,
    int_view = out$int_view
  )

  pts_vert |>
    dplyr::group_by(
      .data$region, .data$hemisphere, .data$view, .data$int_view, .data$color
    ) |>
    dplyr::summarise(
      vert_size = dplyr::n(),
      geometry = sf::st_combine(.data$geometry),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$vert_size > 5)
}

brain2d_filter_cortex_points <- function(
  points,
  method = c("density", "sample", "all"),
  k = 15L,
  keep_quantile = 0.15,
  max_points = 10000L
) {
  method <- match.arg(method)
  if (method != "density" || nrow(points) < 3L) {
    return(points)
  }

  k <- min(as.integer(k), nrow(points) - 1L)
  density <- knn_density_filter(
    as.matrix(points[, c("x", "y")]),
    k = k,
    keep_quantile = keep_quantile
  )
  indices <- which(density$keep)
  if (!is.null(max_points) && length(indices) > max_points) {
    indices <- indices[order(density$rho[indices], decreasing = TRUE)]
    indices <- indices[seq_len(max_points)]
  }
  points[sort(indices), , drop = FALSE]
}
