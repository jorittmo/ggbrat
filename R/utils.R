shrink_polygons <- function(x, dist) {
  stopifnot(inherits(x, "sf"))

  x |>
    st_make_valid() |>
    st_buffer(dist = -abs(distance))
}


smooth_polygons <- function(x, method = "ksmooth", smoothness = 3) {
  smoothr::smooth(x, method = method, smoothness = smoothness)
}


#' Compact a subcortical atlas layout
#'
#' Repositions complete hemisphere/view groups according to their subcortical
#' bounding boxes. Parcel shapes and their relative positions within each group
#' are unchanged. This is useful when the cortex is omitted and cortex-sized
#' grid spacing leaves excessive empty space between subcortical structures.
#'
#' @param x An `sf` atlas or a list returned by [build_brain_atlas()].
#' @param horizontal_gap Horizontal gap between hemisphere groups.
#' @param vertical_gap Vertical gap between view rows.
#' @param drop_cortex When `TRUE`, remove `cortex` and `cortex_silhouette` from
#'   list inputs because the compact layout is intended for cortex-free plots.
#'
#' @return An object of the same form as `x`, with compactly shifted geometry.
#' @export
compact_subcortical_layout <- function(
  x,
  horizontal_gap = 0.05,
  vertical_gap = 0.05,
  drop_cortex = TRUE
) {
  if (!is.numeric(horizontal_gap) || length(horizontal_gap) != 1L ||
      is.na(horizontal_gap) || horizontal_gap < 0) {
    stop("`horizontal_gap` must be one non-negative number.", call. = FALSE)
  }
  if (!is.numeric(vertical_gap) || length(vertical_gap) != 1L ||
      is.na(vertical_gap) || vertical_gap < 0) {
    stop("`vertical_gap` must be one non-negative number.", call. = FALSE)
  }
  if (!is.logical(drop_cortex) || length(drop_cortex) != 1L || is.na(drop_cortex)) {
    stop("`drop_cortex` must be TRUE or FALSE.", call. = FALSE)
  }

  is_atlas_list <- is.list(x) && !inherits(x, "sf") && "atlas" %in% names(x)
  atlas <- if (is_atlas_list) x$atlas else x
  if (!inherits(atlas, "sf")) {
    stop("`x` must be an sf object or an atlas list containing `atlas`.", call. = FALSE)
  }
  required <- c("hemisphere", "view")
  if (!all(required %in% names(atlas))) {
    stop("Atlas geometry must contain `hemisphere` and `view` columns.", call. = FALSE)
  }

  view_id <- if ("int_view" %in% names(atlas)) {
    as.integer(atlas$int_view)
  } else {
    match(atlas$view, unique(atlas$view))
  }
  atlas_info <- sf::st_drop_geometry(atlas)
  atlas_info$.compact_view <- view_id
  group_keys <- unique(atlas_info[c("hemisphere", "view", ".compact_view")])

  bounds <- lapply(seq_len(nrow(group_keys)), function(index) {
    key <- group_keys[index, ]
    selected <- atlas$hemisphere == key$hemisphere & view_id == key$.compact_view
    bbox <- sf::st_bbox(atlas[selected, , drop = FALSE])
    data.frame(
      hemisphere = key$hemisphere,
      view = key$view,
      int_view = key$.compact_view,
      xmin = unname(bbox["xmin"]),
      ymin = unname(bbox["ymin"]),
      xmax = unname(bbox["xmax"]),
      ymax = unname(bbox["ymax"])
    )
  })
  bounds <- do.call(rbind, bounds)
  bounds$width <- bounds$xmax - bounds$xmin
  bounds$height <- bounds$ymax - bounds$ymin
  bounds$dx <- 0
  bounds$dy <- 0

  view_order <- sort(unique(bounds$int_view))
  row_top <- 0
  for (view_index in view_order) {
    row_indices <- which(bounds$int_view == view_index)
    hemi_rank <- match(bounds$hemisphere[row_indices], c("left", "right"))
    hemi_rank[is.na(hemi_rank)] <- 2L + rank(bounds$hemisphere[row_indices][is.na(hemi_rank)])
    row_indices <- row_indices[order(hemi_rank)]

    row_height <- max(bounds$height[row_indices])
    row_center <- row_top - row_height / 2
    x_cursor <- 0
    for (index in row_indices) {
      bounds$dx[index] <- x_cursor - bounds$xmin[index]
      bounds$dy[index] <- row_center - (bounds$ymin[index] + bounds$ymax[index]) / 2
      x_cursor <- x_cursor + bounds$width[index] + horizontal_gap
    }
    row_top <- row_top - row_height - vertical_gap
  }

  shift_layer <- function(layer) {
    if (!inherits(layer, "sf") || !all(required %in% names(layer))) {
      return(layer)
    }
    layer_view_id <- if ("int_view" %in% names(layer)) {
      as.integer(layer$int_view)
    } else {
      match(layer$view, unique(atlas$view))
    }
    map_index <- match(
      paste(layer$hemisphere, layer_view_id),
      paste(bounds$hemisphere, bounds$int_view)
    )
    if (anyNA(map_index)) {
      stop("A layer contains hemisphere/view groups absent from `atlas`.", call. = FALSE)
    }
    shifted <- mapply(
      function(geometry, dx, dy) geometry + c(dx, dy),
      sf::st_geometry(layer),
      bounds$dx[map_index],
      bounds$dy[map_index],
      SIMPLIFY = FALSE
    )
    sf::st_geometry(layer) <- sf::st_sfc(shifted, crs = sf::st_crs(layer))
    layer
  }

  if (!is_atlas_list) {
    return(shift_layer(atlas))
  }

  for (layer_name in c("atlas", "shade", "silhouette")) {
    if (layer_name %in% names(x) && !is.null(x[[layer_name]])) {
      x[[layer_name]] <- shift_layer(x[[layer_name]])
    }
  }
  if (drop_cortex) {
    x$cortex <- NULL
    x$cortex_silhouette <- NULL
  } else {
    for (layer_name in c("cortex", "cortex_silhouette")) {
      if (layer_name %in% names(x) && !is.null(x[[layer_name]])) {
        x[[layer_name]] <- shift_layer(x[[layer_name]])
      }
    }
  }
  x
}


