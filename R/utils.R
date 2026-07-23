#' Shrink polygon geometries
#'
#' Applies a negative buffer to an `sf` object after repairing invalid
#' geometries. This is useful for creating a small visual gap between adjacent
#' atlas regions. Features may become empty when `dist` is large relative to
#' the polygon.
#'
#' @param x An `sf` object containing polygon or multipolygon geometries.
#' @param dist Non-negative buffer distance used to shrink each polygon. The
#'   value is interpreted in the coordinate units of `x`; its absolute value is
#'   used.
#'
#' @return An `sf` object with inward-buffered geometries and the same attribute
#'   columns as `x`.
#' @export
#'
#' @examples
#' square <- sf::st_sf(
#'   region = "example",
#'   geometry = sf::st_sfc(sf::st_polygon(list(matrix(
#'     c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE
#'   ))))
#' )
#' smaller <- shrink_polygons(square, dist = 0.05)
shrink_polygons <- function(x, dist = 0.005) {
  stopifnot(inherits(x, "sf"))

  x |>
    sf::st_make_valid() |>
    sf::st_buffer(dist = -abs(dist))
}


#' Smooth polygon boundaries
#'
#' Smooths the geometries of an `sf` object using [smoothr::smooth()]. Attribute
#' columns are retained. The available methods and the interpretation of
#' `smoothness` are defined by `smoothr`.
#'
#' @param x An `sf` object containing polygon or multipolygon geometries.
#' @param method Smoothing method passed to [smoothr::smooth()]. Common choices
#'   include `"ksmooth"`, `"chaikin"`, `"spline"`, and `"densify"`.
#' @param smoothness Smoothing parameter passed to the selected method through
#'   [smoothr::smooth()].
#'
#' @return An `sf` object with smoothed geometries and the same attribute
#'   columns as `x`.
#' @export
#'
#' @examples
#' square <- sf::st_sf(
#'   region = "example",
#'   geometry = sf::st_sfc(sf::st_polygon(list(matrix(
#'     c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE
#'   ))))
#' )
#' smoothed <- smooth_polygons(square, method = "ksmooth", smoothness = 3)
smooth_polygons <- function(x, method = "ksmooth", smoothness = 3) {
  smoothr::smooth(x, method = method, smoothness = smoothness)
}


#' Reposition atlas panels with a text-based layout
#'
#' Arranges atlas panels using a compact design string. Panels are inferred
#' from the atlas in the order in which they first appear and assigned the
#' letters `A`, `B`, `C`, and so on. For a surface atlas, a panel is each unique
#' `view` and `hemisphere` combination. For an atlas without multiple
#' hemispheres, including a volumetric atlas, a panel is each unique `view`.
#'
#' For example, `"ABCD"` places four panels in one row, while `"AB\nCD"`
#' creates a two-by-two grid. Use `.`, `#`, or a space for an empty cell.
#' Letter matching is case-insensitive.
#'
#' When `x` is the list returned by [build_atlas_surf()], the same translations
#' are applied to the `atlas`, `shade`, `silhouette`, `cortex`, and
#' `cortex_silhouette` layers. Camera positions and other non-spatial
#' components are left unchanged.
#'
#' @param x An `sf` atlas, or a list returned by [build_atlas_surf()].
#' @param layout A single character string describing the grid. Each non-empty
#'   cell must be a letter assigned to one inferred panel. Newlines separate
#'   rows; `.`, `#`, and spaces denote empty cells.
#' @param horizontal_gap Horizontal distance between adjacent view bounding
#'   boxes, in the coordinate units of the atlas.
#' @param vertical_gap Vertical distance between adjacent view bounding boxes,
#'   in the coordinate units of the atlas.
#'
#' @return An object of the same form as `x`, with repositioned geometries. A
#'   data frame mapping layout letters to panel metadata is stored in the
#'   `layout_key` attribute.
#' @export
#'
#' @examples
#' \dontrun{
#' atlas <- load_atlas("Schaefer2018_400Parcels_7Networks_order")
#'
#' # Put four panels in one row.
#' atlas <- reposition_atlas(atlas, layout = "ABCD")
#'
#' # Put the same panels in a two-by-two grid.
#' atlas <- reposition_atlas(atlas, layout = "AB\nCD")
#'
#' # Inspect which panel was assigned to each letter.
#' attr(atlas, "layout_key")
#' }
reposition_atlas <- function(
  x,
  layout,
  horizontal_gap = 0.05,
  vertical_gap = 0.05
) {
  if (!is.character(layout) || length(layout) != 1L || is.na(layout) ||
      !nzchar(layout)) {
    stop("`layout` must be one non-empty character string.", call. = FALSE)
  }
  for (argument in c("horizontal_gap", "vertical_gap")) {
    value <- get(argument)
    if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
        !is.finite(value) || value < 0) {
      stop("`", argument, "` must be one non-negative number.", call. = FALSE)
    }
  }

  is_atlas_list <- is.list(x) && !inherits(x, "sf") && "atlas" %in% names(x)
  atlas <- if (is_atlas_list) x$atlas else x
  if (!inherits(atlas, "sf")) {
    stop("`x` must be an sf object or an atlas list containing `atlas`.",
         call. = FALSE)
  }
  if (!"view" %in% names(atlas) && !"int_view" %in% names(atlas)) {
    stop("The atlas must contain a `view` or `int_view` column.", call. = FALSE)
  }

  layout <- toupper(layout)
  lines <- strsplit(gsub("\r\n?", "\n", layout), "\n", fixed = TRUE)[[1L]]
  while (length(lines) > 1L && !nzchar(lines[[1L]])) lines <- lines[-1L]
  while (length(lines) > 1L && !nzchar(lines[[length(lines)]])) {
    lines <- lines[-length(lines)]
  }
  cells <- lapply(lines, function(line) {
    if (!nzchar(line)) character() else strsplit(line, "", fixed = TRUE)[[1L]]
  })
  n_columns <- max(lengths(cells))
  grid <- matrix(NA_character_, nrow = length(cells), ncol = n_columns)
  for (row_index in seq_along(cells)) {
    if (length(cells[[row_index]])) {
      grid[row_index, seq_along(cells[[row_index]])] <- cells[[row_index]]
    }
  }

  empty_cell <- is.na(grid) | grid %in% c(" ", ".", "#")
  invalid <- !empty_cell & !grepl("^[A-Z]$", grid)
  if (any(invalid)) {
    stop(
      "`layout` cells must be letters, spaces, `.`, or `#`.",
      call. = FALSE
    )
  }
  layout_panels <- grid[!empty_cell]
  if (anyDuplicated(layout_panels)) {
    stop("Every panel may appear only once in `layout`.", call. = FALSE)
  }

  panel_columns <- if ("view" %in% names(atlas)) "view" else "int_view"
  if ("hemisphere" %in% names(atlas)) {
    hemispheres <- unique(atlas$hemisphere[!is.na(atlas$hemisphere)])
    if (length(hemispheres) > 1L) {
      panel_columns <- c(panel_columns, "hemisphere")
    }
  }

  panel_key <- function(data, layer_name) {
    missing_columns <- setdiff(panel_columns, names(data))
    if (length(missing_columns)) {
      stop(
        "Layer `", layer_name, "` cannot be matched to atlas panels; missing ",
        paste(missing_columns, collapse = ", "), ".",
        call. = FALSE
      )
    }
    values <- lapply(data[panel_columns], function(value) {
      value <- as.character(value)
      value[is.na(value)] <- "<NA>"
      value
    })
    do.call(paste, c(values, sep = "\r"))
  }

  atlas_panel_keys <- panel_key(sf::st_drop_geometry(atlas), "atlas")
  unique_panel_keys <- unique(atlas_panel_keys)
  panel_count <- length(unique_panel_keys)
  if (panel_count > length(LETTERS)) {
    stop(
      "`reposition_atlas()` currently supports at most 26 inferred panels.",
      call. = FALSE
    )
  }
  panel_letters <- LETTERS[seq_len(panel_count)]
  if (!setequal(layout_panels, panel_letters)) {
    missing <- setdiff(panel_letters, layout_panels)
    unknown <- setdiff(layout_panels, panel_letters)
    details <- c(
      if (length(missing)) paste0("missing: ", paste(missing, collapse = ", ")),
      if (length(unknown)) paste0("unknown: ", paste(unknown, collapse = ", "))
    )
    stop(
      "`layout` must contain every inferred panel exactly once (",
      paste(details, collapse = "; "), ").",
      call. = FALSE
    )
  }

  panel_bounds <- lapply(seq_along(unique_panel_keys), function(panel_index) {
    selected <- atlas_panel_keys == unique_panel_keys[[panel_index]]
    bbox <- sf::st_bbox(atlas[selected, ])
    data.frame(
      panel = panel_letters[[panel_index]],
      panel_key = unique_panel_keys[[panel_index]],
      xmin = unname(bbox["xmin"]),
      ymin = unname(bbox["ymin"]),
      xmax = unname(bbox["xmax"]),
      ymax = unname(bbox["ymax"])
    )
  })
  panel_bounds <- do.call(rbind, panel_bounds)
  panel_bounds$width <- panel_bounds$xmax - panel_bounds$xmin
  panel_bounds$height <- panel_bounds$ymax - panel_bounds$ymin

  cell_width <- max(panel_bounds$width)
  cell_height <- max(panel_bounds$height)
  positions <- which(!empty_cell, arr.ind = TRUE)
  position_panels <- grid[!empty_cell]
  positions <- positions[
    match(panel_letters, position_panels), , drop = FALSE
  ]
  panel_bounds$dx <- (positions[, "col"] - 1L) *
    (cell_width + horizontal_gap) -
    (panel_bounds$xmin + panel_bounds$xmax) / 2
  panel_bounds$dy <- -(positions[, "row"] - 1L) *
    (cell_height + vertical_gap) -
    (panel_bounds$ymin + panel_bounds$ymax) / 2

  shift_layer <- function(layer, layer_name) {
    if (!inherits(layer, "sf")) return(layer)
    layer_panel_keys <- panel_key(sf::st_drop_geometry(layer), layer_name)
    map_index <- match(layer_panel_keys, panel_bounds$panel_key)
    if (anyNA(map_index)) {
      stop("Layer `", layer_name, "` contains an unknown panel.",
           call. = FALSE)
    }
    shifted <- mapply(
      function(geometry, dx, dy) {
        coordinate_names <- colnames(sf::st_coordinates(geometry))
        offset <- if ("Z" %in% coordinate_names) c(dx, dy, 0) else c(dx, dy)
        geometry + offset
      },
      sf::st_geometry(layer),
      panel_bounds$dx[map_index],
      panel_bounds$dy[map_index],
      SIMPLIFY = FALSE
    )
    sf::st_geometry(layer) <- sf::st_sfc(shifted, crs = sf::st_crs(layer))
    layer
  }

  panel_metadata <- sf::st_drop_geometry(atlas)[
    match(unique_panel_keys, atlas_panel_keys),
    panel_columns,
    drop = FALSE
  ]
  layout_key <- cbind(
    data.frame(
      panel = panel_letters,
      row = positions[, "row"],
      column = positions[, "col"],
      stringsAsFactors = FALSE
    ),
    panel_metadata
  )

  if (!is_atlas_list) {
    result <- shift_layer(atlas, "atlas")
    attr(result, "layout_key") <- layout_key
    return(result)
  }

  spatial_layers <- c(
    "atlas", "shade", "silhouette", "cortex", "cortex_silhouette"
  )
  for (layer_name in spatial_layers) {
    if (layer_name %in% names(x) && !is.null(x[[layer_name]])) {
      x[[layer_name]] <- shift_layer(x[[layer_name]], layer_name)
    }
  }
  attr(x, "layout_key") <- layout_key
  x
}


#' Scale an entire atlas
#'
#' Scales all atlas coordinates around the centre of the main atlas bounding
#' box. The complete layout, including the distances between views, is scaled
#' as one object. This is useful when cortical and subcortical atlases need to
#' be displayed at comparable sizes in the same figure.
#'
#' When `atlas` is a list, the same transformation is applied to every `sf`
#' component, including atlas polygons, shading, silhouettes, and glass-cortex
#' layers. Non-spatial components are left unchanged. For geometries containing
#' Z or M coordinates, only X and Y are scaled.
#'
#' @param atlas An `sf` atlas or a list containing an `sf` component named
#'   `atlas`.
#' @param factor A positive numeric scale factor. Values greater than one
#'   enlarge the atlas and values between zero and one shrink it.
#'
#' @return An object of the same form as `atlas`, with scaled geometries.
#' @export
#'
#' @examples
#' \dontrun{
#' cortical <- load_atlas("Schaefer2018_400Parcels_7Networks_order")
#' subcortical <- load_atlas("Melbourne_S1")
#'
#' subcortical <- atlas_size(subcortical, factor = 1.4)
#' }
atlas_size <- function(atlas, factor = 1) {
  if (!is.numeric(factor) || length(factor) != 1L || is.na(factor) ||
      !is.finite(factor) || factor <= 0) {
    stop("`factor` must be one positive number.", call. = FALSE)
  }

  is_atlas_list <- is.list(atlas) && !inherits(atlas, "sf") &&
    "atlas" %in% names(atlas)
  main_atlas <- if (is_atlas_list) atlas$atlas else atlas
  if (!inherits(main_atlas, "sf")) {
    stop(
      "`atlas` must be an sf object or a list containing an sf `atlas`.",
      call. = FALSE
    )
  }
  if (!nrow(main_atlas) || all(sf::st_is_empty(main_atlas))) {
    stop("The main atlas contains no geometry to scale.", call. = FALSE)
  }
  if (factor == 1) return(atlas)

  bbox <- sf::st_bbox(main_atlas)
  centre <- c(
    as.numeric((bbox["xmin"] + bbox["xmax"]) / 2),
    as.numeric((bbox["ymin"] + bbox["ymax"]) / 2)
  )

  scale_layer <- function(layer) {
    if (!inherits(layer, "sf")) return(layer)
    scaled <- lapply(sf::st_geometry(layer), function(geometry) {
      coordinates <- sf::st_coordinates(geometry)
      dimensions <- max(
        2L,
        sum(c("X", "Y", "Z", "M") %in% colnames(coordinates))
      )
      origin <- c(centre, rep(0, dimensions - 2L))
      multiplier <- c(rep(factor, 2L), rep(1, dimensions - 2L))
      (geometry - origin) * multiplier + origin
    })
    sf::st_geometry(layer) <- sf::st_sfc(scaled, crs = sf::st_crs(layer))
    layer
  }

  if (!is_atlas_list) return(scale_layer(atlas))

  for (component in names(atlas)) {
    if (inherits(atlas[[component]], "sf")) {
      atlas[[component]] <- scale_layer(atlas[[component]])
    }
  }
  atlas
}


#' Compact a subcortical atlas layout
#'
#' Repositions complete hemisphere/view groups according to their subcortical
#' bounding boxes. Parcel shapes and their relative positions within each group
#' are unchanged. This is useful when the cortex is omitted and cortex-sized
#' grid spacing leaves excessive empty space between subcortical structures.
#'
#' @param x An `sf` atlas or a list returned by [build_atlas_surf()].
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
