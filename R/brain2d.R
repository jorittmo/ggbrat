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
#' camera positions for a custom view.
#'
#' @param annot_path For cortical surfaces, a path to a single `.annot` file or
#'   a named vector/list with `left` and `right`. May be `NULL` when
#'   `mesh_path` is supplied.
#' @param mesh_path Optional path to a labelled VTK/VTP mesh, or a named pair
#'   with elements `left` and `right`. A pair follows the same mirrored-camera
#'   workflow as cortical hemispheres; a single mesh is rendered once per view.
#' @param label_array Name of the mesh point-data array containing parcel names.
#' @param color_array Optional mesh point-data array containing parcel colors.
#'   When it is absent, deterministic colors are generated automatically.
#' @param mesh_hemisphere Value stored in the output `hemisphere` column for a
#'   generic mesh.
#' @param hemi Hemisphere to process for cortical surfaces.
#' @param n_views Number of views to build. If `camera_positions` is supplied,
#'   this defaults to `length(camera_positions)`.
#' @param view_names Optional names for the views.
#' @param camera_positions Optional list of saved PyVista camera positions.
#' @param interactive Whether to capture camera positions interactively.
#' @param surf_dir Directory containing FreeSurfer surface files.
#' @param surface A single surface name or a pair of surfaces to blend.
#' @param surf_blend_ratio Blend ratio used when `surface` has length 2.
#' @param window_size PyVista window size.
#' @param include_silhouette Whether to compute and return silhouettes.
#' @param sil_decimate Fraction of silhouette polyline points to remove.
#'
#' @return A list with `atlas`, optional `silhouette`, and `camera_positions`.
#' @export
brain_views <- function(
  annot_path = NULL,
  hemi = c("both", "left", "right"),
  n_views = NULL,
  view_names = NULL,
  camera_positions = NULL,
  interactive = FALSE,
  surf_dir = "data/fsaverage/surf",
  surface = "pial",
  surf_blend_ratio = NULL,
  window_size = c(800L, 600L),
  include_silhouette = FALSE,
  sil_decimate = 0.1,
  mesh_path = NULL,
  label_array = "parcel",
  color_array = "color",
  mesh_hemisphere = "subcortical"
) {
  hemi <- match.arg(hemi)
  window_size <- as.integer(window_size)

  if (interactive) {
    camera_positions <- NULL
  } else if (is.null(camera_positions)) {
    camera_positions <- brain2d_default_camera_positions()
  }

  if (!is.null(camera_positions)) {
    camera_positions <- brain2d_normalize_camera_positions(camera_positions)
  }

  view_spec <- brain2d_prepare_views(
    n_views = n_views,
    view_names = view_names,
    camera_positions = camera_positions,
    interactive = interactive
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
    surface_paths <- brain2d_surface_paths(
      surf_dir = surf_dir,
      surface = surface,
      surf_blend_ratio = surf_blend_ratio
    )
  }

  out <- list()
  out_sil <- if (include_silhouette) list() else NULL
  captured_cameras <- vector("list", view_spec$n_views)

  for (index in seq_len(view_spec$n_views)) {
    preset_camera <- if (interactive) NULL else view_spec$camera_positions[[index]]
    view_label <- view_spec$view_names[[index]]

    if (paired_mesh) {
      left_res <- brain2d_python_env$extract_visible_2d_vtk(
        mesh_path[["left"]],
        label_array = label_array,
        color_array = color_array,
        mirror_camera = preset_camera,
        window_size = window_size,
        return_silhouette = include_silhouette,
        sil_decimate = sil_decimate,
        hemisphere = "left"
      )
      captured_cameras[[index]] <- left_res[[2]]
      out[[length(out) + 1L]] <- brain2d_tag_view(left_res[[1]], "left", view_label, index)
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
          left_res[[3]], "left", view_label, index
        )
      }

      right_res <- brain2d_python_env$extract_visible_2d_vtk(
        mesh_path[["right"]],
        label_array = label_array,
        color_array = color_array,
        mirror_camera = captured_cameras[[index]],
        window_size = window_size,
        return_silhouette = include_silhouette,
        sil_decimate = sil_decimate,
        hemisphere = "right"
      )
      out[[length(out) + 1L]] <- brain2d_tag_view(right_res[[1]], "right", view_label, index)
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
          right_res[[3]], "right", view_label, index
        )
      }
    } else if (generic_mesh) {
      mesh_res <- brain2d_python_env$extract_visible_2d_vtk(
        mesh_path,
        label_array = label_array,
        color_array = color_array,
        mirror_camera = preset_camera,
        window_size = window_size,
        return_silhouette = include_silhouette,
        sil_decimate = sil_decimate,
        hemisphere = NULL
      )
      captured_cameras[[index]] <- mesh_res[[2]]
      out[[length(out) + 1L]] <- brain2d_tag_view(
        mesh_res[[1]], mesh_hemisphere, view_label, index
      )
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(
          mesh_res[[3]], mesh_hemisphere, view_label, index
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
        sil_decimate = sil_decimate
      )
      captured_cameras[[index]] <- left_res[[2]]
      out[[length(out) + 1L]] <- brain2d_tag_view(left_res[[1]], "left", view_label, index)
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(left_res[[3]], "left", view_label, index)
      }

      if (hemi == "both") {
        right_res <- brain2d_python_env$extract_visible_2d(
          surface_paths$right,
          brain2d_annot_path(annot_path, "right"),
          hemisphere = "right",
          mirror_camera = captured_cameras[[index]],
          window_size = window_size,
          return_silhouette = include_silhouette,
          sil_decimate = sil_decimate
        )
        out[[length(out) + 1L]] <- brain2d_tag_view(right_res[[1]], "right", view_label, index)
        if (include_silhouette) {
          out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(right_res[[3]], "right", view_label, index)
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
        sil_decimate = sil_decimate
      )
      captured_cameras[[index]] <- right_res[[2]]
      out[[length(out) + 1L]] <- brain2d_tag_view(right_res[[1]], "right", view_label, index)
      if (include_silhouette) {
        out_sil[[length(out_sil) + 1L]] <- brain2d_tag_silhouette(right_res[[3]], "right", view_label, index)
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
  surf_dir = "data/fsaverage/surf",
  surface = "pial",
  surf_blend_ratio = NULL,
  window_size = c(800L, 600L),
  sil_decimate = 0.1,
  mesh_path = NULL,
  label_array = "parcel",
  color_array = "color",
  mesh_hemisphere = "subcortical"
) {
  preset_hemi <- match.arg(preset_hemi)
  result <- brain_views(
    annot_path = annot_path,
    hemi = preset_hemi,
    n_views = n_views,
    view_names = view_names,
    interactive = TRUE,
    surf_dir = surf_dir,
    surface = surface,
    surf_blend_ratio = surf_blend_ratio,
    window_size = window_size,
    include_silhouette = FALSE,
    sil_decimate = sil_decimate,
    mesh_path = mesh_path,
    label_array = label_array,
    color_array = color_array,
    mesh_hemisphere = mesh_hemisphere
  )

  result$camera_positions
}

#' Convert silhouette segments into merged sf lines
#'
#' @param sil Data frame with columns `x0`, `y0`, `x1`, `y1`.
#'
#' @return An `sf` object.
#' @export
silhouette_sf <- function(sil) {
  if (is.null(sil) || nrow(sil) == 0L) {
    return(sf::st_sf(
      group_id = integer(),
      geometry = sf::st_sfc(crs = sf::NA_crs_)
    ))
  }

  round3 <- function(x) signif(x, digits = 4)

  coords <- sil |>
    dplyr::mutate(dplyr::across(c("x0", "y0", "x1", "y1"), round3)) |>
    dplyr::mutate(
      start = paste(x0, y0, sep = "_"),
      end = paste(x1, y1, sep = "_"),
      next_start = dplyr::lead(start),
      connected = end == next_start,
      new_group = !connected | is.na(connected),
      group_id = cumsum(dplyr::lag(new_group, default = TRUE))
    )

  lines_sf <- coords |>
    dplyr::rowwise() |>
    dplyr::mutate(
      geometry = list(
        sf::st_linestring(
          matrix(c(x0, y0, x1, y1), ncol = 2, byrow = TRUE),
          dim = "XY"
        )
      )
    ) |>
    dplyr::ungroup() |>
    sf::st_as_sf()

  merge_group <- function(geom) {
    geom |>
      sf::st_union() |>
      sf::st_cast("MULTILINESTRING") |>
      sf::st_line_merge()
  }

  lines_sf |>
    dplyr::group_by(group_id) |>
    dplyr::summarise(geometry = merge_group(geometry), .groups = "drop") |>
    dplyr::mutate(geom_length = as.numeric(sf::st_length(geometry))) |>
    dplyr::filter(geom_length > 0.1) |>
    sf::st_sf()
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
        hemi_n = ifelse(hemisphere == "right", 1L, 0L),
        idx = view_index * n_cols + hemi_n,
        row = idx %/% n_cols,
        col = idx %% n_cols,
        shift_x = col * cell_dx,
        shift_y = row * cell_dy
      )

    shifted_geom <- mapply(
      function(geom, dx, dy) geom + c(dx, dy),
      x$geometry,
      x$shift_x,
      x$shift_y,
      SIMPLIFY = FALSE
    )

    x$geometry <- sf::st_sfc(shifted_geom, crs = sf::st_crs(x))
    dplyr::select(x, -hemi_n, -idx, -row, -col, -shift_x, -shift_y)
  }

  if (is.list(sf_obj) && "atlas" %in% names(sf_obj)) {
    sf_obj$atlas <- shift_one(sf_obj$atlas)
    if ("silhouette" %in% names(sf_obj) && !is.null(sf_obj$silhouette)) {
      sf_obj$silhouette <- shift_one(sf_obj$silhouette)
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
  xy_scaled <- scale(xy)

  radius <- if (identical(alpha, "auto")) {
    auto_alpha(xy_scaled, k = 1, factor = smoothing_factor)
  } else {
    alpha
  }

  a <- alphahull::ahull(xy_scaled, alpha = radius)
  edges <- a[["ashape.obj"]][["edges"]]
  if (nrow(edges) == 0L) {
    return(sf::st_sfc(crs = sf::st_crs(pts)))
  }

  idx <- edges[, c("ind1", "ind2")]
  lines <- lapply(seq_len(nrow(idx)), function(i) {
    sf::st_linestring(rbind(xy[idx[i, 1], ], xy[idx[i, 2], ]))
  })

  lines <- sf::st_sfc(lines, crs = sf::st_crs(pts))
  polys <- lines |>
    sf::st_union() |>
    sf::st_line_merge() |>
    sf::st_polygonize() |>
    sf::st_collection_extract("POLYGON")

  if (length(polys) > 1L) {
    polys <- polys |>
      sf::st_union() |>
      sf::st_cast("MULTIPOLYGON")
  }

  polys
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

brain2d_prepare_views <- function(n_views, view_names, camera_positions, interactive) {
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
    reticulate::source_python(
      brain2d_python_path(),
      envir = brain2d_python_env
    )
  }
  invisible(TRUE)
}

brain2d_surface_paths <- function(surf_dir, surface, surf_blend_ratio) {
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

brain2d_tag_silhouette <- function(df, hemisphere, view_label, view_index) {
  sil <- silhouette_sf(df)
  sil$hemisphere <- hemisphere
  sil$view <- view_label
  sil$int_view <- view_index
  sil
}

brain2d_vertices_to_sf <- function(out) {
  pts_vert <- sf::st_as_sfc(sf::st_as_sf(out, coords = c("x", "y"), crs = NA))
  pts_vert <- sf::st_sf(
    geometry = pts_vert,
    color = out$color,
    region = out$parcel,
    hemisphere = out$hemisphere,
    view = out$view,
    int_view = out$int_view
  )

  pts_vert |>
    dplyr::group_by(region, hemisphere, view, int_view, color) |>
    dplyr::summarise(
      vert_size = dplyr::n(),
      geometry = sf::st_combine(geometry),
      .groups = "drop"
    ) |>
    dplyr::filter(vert_size > 5)
}
