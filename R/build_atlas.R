#' Build a shifted polygon atlas with shading support
#'
#' This helper wraps the full atlas-building pipeline: visible vertex
#' extraction, view shifting, region polygon creation, and shade geometry
#' creation.
#'
#' @inheritParams brain_views
#' @param smoothing_factor Scaling factor used by `ashape_polygon_sf()`.
#' @param create_polygons Whether to convert each region's projected
#'   `MULTIPOINT` geometry to a polygon. When `FALSE`, the region multipoints
#'   are returned unchanged.
#' @param keep_z_coord Whether to retain projected display depth as a third
#'   coordinate in returned multipoints. When `create_polygons = TRUE`, region
#'   polygons are constructed from X and Y only, while other multipoint layers
#'   such as `cortex` retain Z.
#' @param shade_k Number of neighbours used by `knn_density_filter()` during
#'   shade creation.
#' @param shade_keep_quantile Quantile of dense points kept for shade creation.
#' @param cell_dx Horizontal spacing between shifted view cells.
#' @param cell_dy Vertical spacing between shifted view cells.
#' @param n_cols Number of columns in the shifted view grid.
#'
#' @return A list containing shifted atlas output in `atlas`, optional
#'   `silhouette`, `camera_positions`, `shade`, and optional `cortex` and
#'   `cortex_silhouette` glass-brain layers. `atlas` contains polygons when
#'   `create_polygons = TRUE` and region multipoints otherwise.
#'
#' @examples
#' \dontrun{
#' melbourne_mesh <- download_surface("Melbourne_S1", type = "subcortical")
#' subcortical_atlas <- build_brain_atlas(
#'   mesh_path = melbourne_mesh,
#'   add_cortex = TRUE,
#'   n_cols = 2
#' )
#' }
#' @export
build_brain_atlas <- function(
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
  smoothing_factor = 5,
  create_polygons = TRUE,
  keep_z_coord = FALSE,
  shade_k = 15,
  shade_keep_quantile = 0.2,
  cell_dx = 1.5,
  cell_dy = -1,
  n_cols = 2,
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
  cortex_max_points = 50000L,
  include_cortex_silhouette = TRUE,
  cortex_preview_opacity = 0.1,
  label_array = NULL
) {
  if (!is.null(label_array)) {
    warning("`label_array` is deprecated; use `region_array`.", call. = FALSE)
    region_array <- label_array
  }
  cortex_point_method <- match.arg(cortex_point_method)
  if (!is.logical(create_polygons) || length(create_polygons) != 1L ||
      is.na(create_polygons)) {
    stop("`create_polygons` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.logical(keep_z_coord) || length(keep_z_coord) != 1L ||
      is.na(keep_z_coord)) {
    stop("`keep_z_coord` must be TRUE or FALSE.", call. = FALSE)
  }
  if (keep_z_coord && create_polygons) {
    message(
      "`keep_z_coord = TRUE`: region polygons use X and Y only; ",
      "multipoint layers retain Z."
    )
  }
  message("Step 1/4: Building raw atlas views")
  atlas_raw <- brain_views(
    annot_path = annot_path,
    hemi = hemi,
    n_views = n_views,
    view_names = view_names,
    camera_positions = camera_positions,
    interactive = interactive,
    surf_dir = surf_dir,
    surface = surface,
    surface_path = surface_path,
    surf_blend_ratio = surf_blend_ratio,
    window_size = window_size,
    include_silhouette = include_silhouette,
    sil_decimate = sil_decimate,
    silhouette_min_length = silhouette_min_length,
    silhouette_tolerance = silhouette_tolerance,
    keep_z_coord = keep_z_coord,
    mesh_path = mesh_path,
    region_array = region_array,
    color_array = color_array,
    mesh_hemisphere = mesh_hemisphere,
    add_cortex = add_cortex,
    cortex_surf_dir = cortex_surf_dir,
    cortex_surface = cortex_surface,
    cortex_surface_path = cortex_surface_path,
    cortex_point_method = cortex_point_method,
    cortex_point_fraction = cortex_point_fraction,
    cortex_density_k = cortex_density_k,
    cortex_density_keep_quantile = cortex_density_keep_quantile,
    cortex_max_points = cortex_max_points,
    include_cortex_silhouette = include_cortex_silhouette,
    cortex_preview_opacity = cortex_preview_opacity
  )

  message("Step 2/4: Shifting atlas views into grid")
  atlas_shifted <- shift_brain_views(
    atlas_raw,
    cell_dx = cell_dx,
    cell_dy = cell_dy,
    n_cols = n_cols
  )

  ahulls <- NULL
  if (create_polygons) {
    message("Step 3/4: Creating region polygons")
    ahulls <- sf::st_sfc(crs = sf::st_crs(atlas_shifted$atlas))
    pb <- utils::txtProgressBar(0, nrow(atlas_shifted$atlas), style = 3)

    for (index in seq_len(nrow(atlas_shifted$atlas))) {
      ahull_poly <- ashape_polygon_sf(
        atlas_shifted$atlas$geometry[index],
        alpha = "auto",
        smoothing_factor = smoothing_factor
      )
      ahulls <- c(ahulls, ahull_poly)
      utils::setTxtProgressBar(pb, index)
    }

    close(pb)
  } else {
    message("Step 3/4: Keeping region multipoints")
  }

  message("Step 4/4: Creating shade geometry")
  shade_parts <- vector("list", length = 0L)
  atlas_crs <- sf::st_crs(atlas_shifted$atlas)

  for (hemi_i in unique(atlas_shifted$atlas$hemisphere)) {
    for (view_i in unique(atlas_shifted$atlas$view)) {
      coords <- sf::st_coordinates(
        atlas_shifted$atlas |>
          dplyr::filter(hemisphere == hemi_i, view == view_i) |>
          dplyr::pull(geometry)
      )[, 1:2, drop = FALSE]

      coords_filtered <- knn_density_filter(
        coords,
        k = shade_k,
        keep_quantile = shade_keep_quantile
      )

      points_df <- as.data.frame(coords_filtered$X_filtered)
      names(points_df) <- c("x", "y")
      points_sf <- sf::st_as_sf(points_df, coords = c("x", "y"), crs = atlas_crs)
      shade_parts[[length(shade_parts) + 1L]] <- sf::st_sf(
        hemisphere = hemi_i,
        view = view_i,
        geometry = sf::st_sfc(sf::st_combine(points_sf$geometry), crs = atlas_crs)
      )
    }
  }

  shade <- do.call(rbind, shade_parts)

  final_atlas <- atlas_shifted
  if (create_polygons) final_atlas$atlas$geometry <- ahulls
  final_atlas$shade <- shade

  message("Atlas build complete")
  final_atlas
}

#' Build an sf atlas from labelled SVG layers
#'
#' `build_atlas_svg()` reads SVG groups containing paths, samples their line
#' and Bezier geometry, and creates one polygon per labelled region. Exact
#' closed paths are preserved; hull reconstruction remains available for
#' legacy SVGs whose paths represent converted strokes rather than regions.
#'
#' @section Authoring SVG atlas templates:
#'
#' New templates should encode the anatomical boundaries directly instead of
#' relying on hull reconstruction:
#'
#' 1. Create one SVG group/layer for each anatomical region.
#' 2. Draw the region as a **closed, filled path**. Either the Bezier tool or a
#'    freehand tool is suitable, provided the final object is an ordinary closed
#'    path. The fill represents the region; a stroke is optional styling around
#'    its boundary.
#' 3. Give the region a stable, unique name. Names are resolved from `data-name`,
#'    a meaningful Inkscape layer label, a path `<title>`, and finally the group
#'    `id`. Generic labels such as `Layer 2` are ignored when a path title is
#'    available.
#' 4. Keep each path as a direct child of its region layer. A layer may contain
#'    multiple closed paths for a disconnected region. Alternatively, repeated
#'    layers can use the same region name; `combine_regions = TRUE` combines
#'    them into one multipart feature.
#' 5. Do not convert strokes to paths. That creates a thin compound outline
#'    rather than an anatomical polygon and requires reconstruction.
#' 6. Convert live path effects and shape objects to ordinary paths before the
#'    final export. Avoid clipping masks, clones, text, embedded raster images,
#'    and nested decorative groups in atlas layers.
#' 7. Save as plain or standard SVG. Line, cubic and quadratic Bezier path
#'    commands are supported. Convert elliptical arcs to Bezier curves. The
#'    importer supports `translate`, `scale`, `rotate`, and matrix transforms.
#'
#' Import new templates with `geometry_method = "path"`. The `"auto"` method
#' treats a path `<title>` as an exact-region marker; ID-only legacy drawings
#' are reconstructed with concaveman. Since concaveman is an optional suggested
#' dependency, install it only when legacy reconstruction is needed with
#' `install.packages("concaveman")`.
#'
#' SVG coordinates have a downward-positive Y axis. `flip_y = TRUE` converts
#' them to the conventional Cartesian orientation used by `sf` and ggplot2.
#'
#' @param svg_path Path to an SVG file.
#' @param curve_steps Number of straight segments used to approximate each
#'   Bezier curve.
#' @param geometry_method Geometry construction method. `"path"` preserves the
#'   authored boundary, `"concaveman"` reconstructs a boundary from sampled
#'   points, and `"auto"` uses exact paths for labelled region drawings and
#'   concaveman for legacy ID-only drawings.
#' @param concavity Concaveman concavity parameter. Smaller values produce a
#'   more detailed boundary; `Inf` produces a convex hull.
#' @param length_threshold Concaveman segment-length threshold. Segments shorter
#'   than this value are not refined further.
#' @param flip_y Whether to convert SVG's downward-positive Y coordinates to
#'   conventional Cartesian coordinates.
#' @param combine_regions Whether groups with the same region name should be
#'   combined into a single (possibly multipart) feature.
#'
#' @return An `sf` object with `region` and `geometry` columns.
#'
#' @examples
#' \dontrun{
#' # Select an SVG whose labelled groups contain the atlas regions.
#' atlas <- build_atlas_svg(
#'   svg_path = file.choose(),
#'   geometry_method = "path"
#' )
#'
#' # Only for legacy drawings whose paths are converted stroke outlines:
#' legacy_atlas <- build_atlas_svg(
#'   svg_path = file.choose(),
#'   geometry_method = "concaveman",
#'   concavity = 0,
#'   length_threshold = 2.5
#' )
#' }
#' @export
build_atlas_svg <- function(
  svg_path,
  curve_steps = 20L,
  geometry_method = c("auto", "path", "concaveman"),
  concavity = 0,
  length_threshold = 2.5,
  flip_y = TRUE,
  combine_regions = TRUE
) {
  geometry_method <- match.arg(geometry_method)
  if (!is.character(svg_path) || length(svg_path) != 1L ||
      is.na(svg_path) || !file.exists(svg_path)) {
    stop("`svg_path` must name an existing SVG file.", call. = FALSE)
  }
  if (!is.numeric(curve_steps) || length(curve_steps) != 1L ||
      is.na(curve_steps) || curve_steps < 2 ||
      curve_steps != as.integer(curve_steps)) {
    stop("`curve_steps` must be an integer of at least 2.", call. = FALSE)
  }
  if (!is.numeric(concavity) || length(concavity) != 1L ||
      is.na(concavity) || concavity < 0) {
    stop("`concavity` must be one non-negative number.", call. = FALSE)
  }
  if (!is.numeric(length_threshold) || length(length_threshold) != 1L ||
      is.na(length_threshold) || length_threshold < 0) {
    stop("`length_threshold` must be one non-negative number.", call. = FALSE)
  }

  document <- xml2::read_xml(svg_path)
  namespaces <- c(svg = "http://www.w3.org/2000/svg")
  groups <- xml2::xml_find_all(document, ".//svg:g[svg:path]", ns = namespaces)
  if (!length(groups)) groups <- xml2::xml_find_all(document, ".//g[path]")
  if (!length(groups)) {
    stop("No SVG groups containing paths were found.", call. = FALSE)
  }

  path_nodes <- lapply(groups, function(group) {
    paths <- xml2::xml_find_all(group, "./svg:path", ns = namespaces)
    if (!length(paths)) paths <- xml2::xml_find_all(group, "./path")
    paths
  })
  group_labels <- vapply(groups, function(group) {
    name <- xml2::xml_attr(group, "data-name")
    if (is.na(name) || !nzchar(name)) {
      name <- xml2::xml_attr(
        group, "label",
        ns = c(inkscape = "http://www.inkscape.org/namespaces/inkscape")
      )
    }
    name
  }, character(1))
  path_titles <- vapply(path_nodes, function(paths) {
    titles <- vapply(paths, function(path) {
      title <- xml2::xml_find_first(path, "./svg:title", ns = namespaces)
      if (inherits(title, "xml_missing")) title <- xml2::xml_find_first(path, "./title")
      if (inherits(title, "xml_missing")) NA_character_ else xml2::xml_text(title)
    }, character(1))
    titles <- unique(titles[!is.na(titles) & nzchar(titles)])
    if (length(titles) == 1L) titles else NA_character_
  }, character(1))
  meaningful_group_label <- !is.na(group_labels) & nzchar(group_labels) &
    !grepl("^Layer[[:space:]]+[0-9]+$", group_labels, ignore.case = TRUE)
  group_ids <- xml2::xml_attr(groups, "id")
  region_names <- ifelse(
    meaningful_group_label,
    group_labels,
    ifelse(!is.na(path_titles) & nzchar(path_titles), path_titles, group_ids)
  )
  if (any(is.na(region_names) | !nzchar(region_names))) {
    stop(
      "Every SVG group must have a region label, path title, or `id`.",
      call. = FALSE
    )
  }

  needs_concaveman <- geometry_method == "concaveman" ||
    (geometry_method == "auto" && any(is.na(path_titles)))
  if (needs_concaveman && !requireNamespace("concaveman", quietly = TRUE)) {
    stop(
      "SVG hull reconstruction requires the optional `concaveman` package. ",
      "Install it with `install.packages(\"concaveman\")`, or use a properly ",
      "closed template with `geometry_method = \"path\"`.",
      call. = FALSE
    )
  }

  geometries <- vector("list", length(groups))
  for (index in seq_along(groups)) {
    path_coordinates <- lapply(path_nodes[[index]], function(path) {
      coordinates <- svg_path_coordinates(
        xml2::xml_attr(path, "d"), as.integer(curve_steps)
      )
      coordinates <- svg_transform_coordinates(
        coordinates, xml2::xml_attr(path, "transform")
      )
      svg_transform_coordinates(coordinates, xml2::xml_attr(groups[[index]], "transform"))
    })
    coordinates <- do.call(rbind, path_coordinates)
    coordinates <- unique(coordinates[stats::complete.cases(coordinates), , drop = FALSE])
    if (nrow(coordinates) < 3L) {
      stop("Region `", region_names[[index]], "` has fewer than three points.", call. = FALSE)
    }
    method <- geometry_method
    if (method == "auto") {
      method <- if (!is.na(path_titles[[index]])) {
        "path"
      } else {
        "concaveman"
      }
    }
    if (method == "path") {
      pieces <- lapply(path_coordinates, function(xy) {
        if (!isTRUE(all.equal(xy[1L, ], xy[nrow(xy), ], tolerance = 1e-8))) {
          stop(
            "Region `", region_names[[index]], "` contains an open path; ",
            "close it or select a hull geometry method.",
            call. = FALSE
          )
        }
        sf::st_polygon(list(xy))
      })
      geometries[[index]] <- sf::st_union(
        sf::st_make_valid(sf::st_sfc(pieces, crs = sf::NA_crs_))
      )[[1]]
    } else {
      hull <- concaveman::concaveman(
        coordinates,
        concavity = concavity,
        length_threshold = length_threshold
      )
      if (!isTRUE(all.equal(hull[1L, ], hull[nrow(hull), ], tolerance = 1e-8))) {
        hull <- rbind(hull, hull[1L, ])
      }
      geometries[[index]] <- sf::st_polygon(list(hull))
    }
  }

  atlas <- sf::st_sf(
    region = region_names,
    geometry = sf::st_sfc(geometries, crs = sf::NA_crs_)
  )
  if (flip_y) {
    box <- sf::st_bbox(atlas)
    atlas <- atlas |>
      dplyr::mutate(
        geometry = geometry * matrix(c(1, 0, 0, -1), nrow = 2L) +
          c(0, box[["ymin"]] + box[["ymax"]])
      )
  }
  if (combine_regions) {
    region_order <- unique(atlas$region)
    atlas <- atlas |>
      dplyr::group_by(region) |>
      dplyr::summarise(geometry = sf::st_union(geometry), .groups = "drop") |>
      dplyr::mutate(.region_order = match(region, region_order)) |>
      dplyr::arrange(.region_order) |>
      dplyr::select(-.region_order)
  }
  sf::st_make_valid(atlas)
}

svg_transform_coordinates <- function(coordinates, transform) {
  if (is.na(transform) || !nzchar(trimws(transform))) return(coordinates)
  matches <- regmatches(
    transform,
    gregexpr("[A-Za-z]+\\s*\\([^)]*\\)", transform, perl = TRUE)
  )[[1]]
  if (!length(matches)) stop("Malformed SVG transform: ", transform, call. = FALSE)

  for (item in matches) {
    name <- tolower(sub("\\s*\\(.*$", "", item))
    argument_text <- sub("\\)$", "", sub("^[^(]*\\(", "", item))
    values <- scan(text = gsub(",", " ", argument_text), quiet = TRUE)
    matrix3 <- diag(3)
    if (name == "translate" && length(values) %in% 1:2) {
      matrix3[1:2, 3] <- c(values[[1]], if (length(values) == 2L) values[[2]] else 0)
    } else if (name == "scale" && length(values) %in% 1:2) {
      matrix3[1, 1] <- values[[1]]
      matrix3[2, 2] <- if (length(values) == 2L) values[[2]] else values[[1]]
    } else if (name == "matrix" && length(values) == 6L) {
      matrix3 <- matrix(
        c(values[[1]], values[[3]], values[[5]],
          values[[2]], values[[4]], values[[6]], 0, 0, 1),
        nrow = 3L,
        byrow = TRUE
      )
    } else if (name == "rotate" && length(values) %in% c(1L, 3L)) {
      angle <- values[[1]] * pi / 180
      rotation <- matrix(
        c(cos(angle), -sin(angle), 0, sin(angle), cos(angle), 0, 0, 0, 1),
        nrow = 3L,
        byrow = TRUE
      )
      if (length(values) == 3L) {
        center <- values[2:3]
        coordinates <- sweep(coordinates, 2L, center, "-")
        matrix3 <- rotation
        coordinates <- t(matrix3 %*% rbind(t(coordinates), 1))[, 1:2, drop = FALSE]
        coordinates <- sweep(coordinates, 2L, center, "+")
        next
      }
      matrix3 <- rotation
    } else {
      stop("Unsupported SVG transform: ", item, call. = FALSE)
    }
    coordinates <- t(matrix3 %*% rbind(t(coordinates), 1))[, 1:2, drop = FALSE]
  }
  coordinates
}

svg_path_coordinates <- function(path, curve_steps = 20L) {
  if (is.na(path) || !nzchar(path)) {
    stop("Encountered an SVG path without `d` coordinates.", call. = FALSE)
  }
  tokens <- regmatches(
    path,
    gregexpr(
      "[A-Za-z]|[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?)(?:[eE][-+]?[0-9]+)?",
      path,
      perl = TRUE
    )
  )[[1]]
  token_is_command <- grepl("^[A-Za-z]$", tokens)
  supported <- c("M", "m", "L", "l", "H", "h", "V", "v", "C", "c",
                 "S", "s", "Q", "q", "T", "t", "Z", "z")
  unsupported <- setdiff(unique(tokens[token_is_command]), supported)
  if (length(unsupported)) {
    stop(
      "Unsupported SVG path command(s): ", paste(unsupported, collapse = ", "),
      ". Convert arcs to Bezier curves before export.",
      call. = FALSE
    )
  }

  result <- matrix(numeric(), ncol = 2L, dimnames = list(NULL, c("x", "y")))
  current <- c(0, 0)
  subpath_start <- current
  last_control <- NULL
  previous_command <- NULL
  command <- NULL
  index <- 1L
  append_points <- function(points) {
    result <<- rbind(result, points)
    current <<- as.numeric(points[nrow(points), ])
  }
  numeric_values <- function(count) {
    positions <- index:(index + count - 1L)
    if (max(positions) > length(tokens) || any(token_is_command[positions])) {
      stop("Malformed SVG path data near command `", command, "`.", call. = FALSE)
    }
    values <- as.numeric(tokens[positions])
    index <<- index + count
    values
  }
  curve <- function(p0, p1, p2, p3 = NULL) {
    time <- seq(0, 1, length.out = curve_steps + 1L)[-1L]
    if (is.null(p3)) {
      outer((1 - time)^2, p0) + outer(2 * (1 - time) * time, p1) +
        outer(time^2, p2)
    } else {
      outer((1 - time)^3, p0) + outer(3 * (1 - time)^2 * time, p1) +
        outer(3 * (1 - time) * time^2, p2) + outer(time^3, p3)
    }
  }

  while (index <= length(tokens)) {
    if (token_is_command[[index]]) {
      command <- tokens[[index]]
      index <- index + 1L
      if (command %in% c("Z", "z")) {
        append_points(matrix(subpath_start, nrow = 1L))
        previous_command <- command
        last_control <- NULL
        command <- NULL
        next
      }
    }
    if (is.null(command)) stop("Malformed SVG path data.", call. = FALSE)
    relative <- command == tolower(command)
    upper <- toupper(command)

    if (upper == "M") {
      point <- numeric_values(2L)
      if (relative) point <- current + point
      append_points(matrix(point, nrow = 1L))
      subpath_start <- point
      command <- if (relative) "l" else "L"
      last_control <- NULL
    } else if (upper == "L") {
      point <- numeric_values(2L)
      if (relative) point <- current + point
      append_points(matrix(point, nrow = 1L))
      last_control <- NULL
    } else if (upper == "H") {
      value <- numeric_values(1L)
      point <- c(if (relative) current[[1]] + value else value, current[[2]])
      append_points(matrix(point, nrow = 1L))
      last_control <- NULL
    } else if (upper == "V") {
      value <- numeric_values(1L)
      point <- c(current[[1]], if (relative) current[[2]] + value else value)
      append_points(matrix(point, nrow = 1L))
      last_control <- NULL
    } else if (upper == "C") {
      values <- matrix(numeric_values(6L), ncol = 2L, byrow = TRUE)
      if (relative) values <- sweep(values, 2L, current, "+")
      append_points(curve(current, values[1L, ], values[2L, ], values[3L, ]))
      last_control <- values[2L, ]
    } else if (upper == "S") {
      values <- matrix(numeric_values(4L), ncol = 2L, byrow = TRUE)
      if (relative) values <- sweep(values, 2L, current, "+")
      smooth <- !is.null(previous_command) &&
        toupper(previous_command) %in% c("C", "S")
      control1 <- if (smooth) 2 * current - last_control else current
      append_points(curve(current, control1, values[1L, ], values[2L, ]))
      last_control <- values[1L, ]
    } else if (upper == "Q") {
      values <- matrix(numeric_values(4L), ncol = 2L, byrow = TRUE)
      if (relative) values <- sweep(values, 2L, current, "+")
      append_points(curve(current, values[1L, ], values[2L, ]))
      last_control <- values[1L, ]
    } else if (upper == "T") {
      point <- numeric_values(2L)
      if (relative) point <- current + point
      smooth <- !is.null(previous_command) &&
        toupper(previous_command) %in% c("Q", "T")
      control <- if (smooth) 2 * current - last_control else current
      append_points(curve(current, control, point))
      last_control <- control
    }
    previous_command <- upper
  }
  result
}
