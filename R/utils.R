shrink_polygons <- function(x, dist) {
  stopifnot(inherits(x, "sf"))

  x |>
    st_make_valid() |>
    st_buffer(dist = -abs(distance))
}


smooth_polygons <- function(x, method = "ksmooth", smoothness = 3) {
  require(smoothr)
  smooth(x, method = method, smoothness = smoothness)
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


#' Interactively edit silhouette lines
#'
#' Opens a Shiny editor for silhouette layers returned by
#' [build_brain_atlas()]. Individual lines can be selected by clicking near
#' them, deleted, or smoothed with a live preview. Edits are only returned after
#' pressing **Save and return to R**.
#'
#' @param x An `sf` object containing `LINESTRING` or `MULTILINESTRING`
#'   geometries, or an atlas list containing such a layer.
#' @param layer Name of the silhouette layer when `x` is an atlas list. Defaults
#'   to `"silhouette"`; `"cortex_silhouette"` is another common choice.
#' @param click_tolerance Maximum selection distance as a fraction of the
#'   displayed view's bounding-box diagonal. Increase this when thin lines are
#'   difficult to select.
#'
#' @return An edited `sf` object, or an atlas list with its selected layer
#'   replaced. Closing the app without saving returns `x` unchanged.
#' @export
edit_silhouette <- function(x, layer = "silhouette", click_tolerance = 0.025) {
  is_atlas_list <- is.list(x) && !inherits(x, "sf")
  silhouette <- if (is_atlas_list) x[[layer]] else x
  if (!inherits(silhouette, "sf")) {
    stop(
      "`x` must be an sf silhouette or an atlas list containing the requested layer.",
      call. = FALSE
    )
  }
  geometry_types <- unique(as.character(sf::st_geometry_type(silhouette)))
  if (!length(geometry_types) ||
      any(!geometry_types %in% c("LINESTRING", "MULTILINESTRING"))) {
    stop("The silhouette must contain only line geometries.", call. = FALSE)
  }
  if (!is.character(layer) || length(layer) != 1L || is.na(layer) || !nzchar(layer)) {
    stop("`layer` must be one non-empty string.", call. = FALSE)
  }
  if (!is.numeric(click_tolerance) || length(click_tolerance) != 1L ||
      is.na(click_tolerance) || !is.finite(click_tolerance) ||
      click_tolerance <= 0) {
    stop("`click_tolerance` must be one positive number.", call. = FALSE)
  }
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop(
      "Silhouette editing requires the suggested package `shiny`. ",
      "Install it with install.packages(\"shiny\").",
      call. = FALSE
    )
  }

  original <- silhouette_prepare_lines(silhouette)
  edited <- silhouette_editor_app(original, click_tolerance)
  if (is.null(edited)) return(x)
  edited$.silhouette_id <- NULL
  edited$.source_feature <- NULL
  edited$.editor_group <- NULL
  if (!is_atlas_list) return(edited)
  x[[layer]] <- edited
  x
}

silhouette_prepare_lines <- function(x) {
  x$.source_feature <- seq_len(nrow(x))
  lines <- suppressWarnings(sf::st_cast(x, "LINESTRING"))
  lines$.silhouette_id <- seq_len(nrow(lines))
  lines
}

silhouette_smooth_line <- function(geometry, strength) {
  if (strength <= 0) return(geometry)
  coordinates <- unclass(geometry)
  if (nrow(coordinates) < 4L) return(geometry)
  closed <- isTRUE(all.equal(
    coordinates[1L, ], coordinates[nrow(coordinates), ], tolerance = 1e-10
  ))
  points <- if (closed) coordinates[-nrow(coordinates), , drop = FALSE] else coordinates
  if (nrow(points) < 3L) return(geometry)

  radius <- max(1L, ceiling(strength * 2))
  offsets <- seq.int(-radius, radius)
  sigma <- max(strength, 0.35)
  weights <- exp(-0.5 * (offsets / sigma)^2)
  smoothed <- points
  for (index in seq_len(nrow(points))) {
    neighbours <- index + offsets
    if (closed) {
      neighbours <- ((neighbours - 1L) %% nrow(points)) + 1L
      local_weights <- weights
    } else {
      keep <- neighbours >= 1L & neighbours <= nrow(points)
      neighbours <- neighbours[keep]
      local_weights <- weights[keep]
    }
    local_weights <- local_weights / sum(local_weights)
    smoothed[index, ] <- colSums(points[neighbours, , drop = FALSE] * local_weights)
  }
  if (closed) {
    smoothed <- rbind(smoothed, smoothed[1L, , drop = FALSE])
  } else {
    smoothed[1L, ] <- coordinates[1L, ]
    smoothed[nrow(smoothed), ] <- coordinates[nrow(coordinates), ]
  }
  sf::st_linestring(smoothed)
}

silhouette_editor_groups <- function(lines) {
  group_columns <- intersect(c("hemisphere", "view"), names(lines))
  if (length(group_columns)) {
    group_data <- sf::st_drop_geometry(lines)[group_columns]
    group_data[] <- lapply(group_data, function(value) {
      value <- as.character(value)
      value[is.na(value)] <- "missing"
      value
    })
    lines$.editor_group <- apply(group_data, 1L, paste, collapse = " · ")
    view_values <- unique(lines$.editor_group)
  } else {
    lines$.editor_group <- "All lines"
  }
  lines
}

silhouette_editor_app <- function(lines, click_tolerance) {
  lines <- silhouette_editor_groups(lines)
  view_values <- unique(lines$.editor_group)

  ui <- shiny::fluidPage(
    shiny::tags$head(
      shiny::tags$style(htmltools::HTML(paste0(
        "body{background:#151719;color:#eee;font-family:system-ui,-apple-system,",
        "BlinkMacSystemFont,'Segoe UI',sans-serif}",
        ".container-fluid{max-width:1380px;margin:0 auto;padding:24px}",
        ".sil-title{margin:0 0 20px 2px;font-size:27px;font-weight:650}",
        ".sil-layout{display:grid;grid-template-columns:minmax(290px,350px) ",
        "minmax(0,1fr);gap:20px;align-items:start}",
        ".sil-card{background:#232629;border:1px solid #383c40;border-radius:18px;",
        "padding:22px;box-shadow:0 10px 30px rgba(0,0,0,.22)}",
        ".sil-preview{padding:12px 16px 16px;min-width:0}",
        ".sil-card-title{font-size:16px;font-weight:650;margin:0 0 18px}",
        ".form-control{background:#181a1c;color:#eee;border-color:#4a4e52;",
        "border-radius:9px}",
        ".sil-actions{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}",
        ".sil-actions .btn,#save_silhouette{border-radius:12px;padding:9px 14px}",
        "#save_silhouette{font-weight:650;margin-top:12px}",
        "#delete_line{background:#8f3535;color:white;border-color:#a94442}",
        ".sil-status{min-height:42px;color:#cbd0d4;margin:12px 0}",
        "#silhouette_plot{cursor:crosshair;width:100%}",
        "@media(max-width:800px){.sil-layout{grid-template-columns:1fr}}"
      ))),
      shiny::tags$script(htmltools::HTML(paste0(
        "$(document).on('keydown keyup', function(e){",
        "Shiny.setInputValue('shift_down', e.shiftKey, {priority:'event'});",
        "});"
      )))
    ),
    shiny::tags$h1("Edit silhouette", class = "sil-title"),
    shiny::tags$div(
      class = "sil-layout",
      shiny::tags$section(
        class = "sil-card",
        shiny::tags$h2("Editing controls", class = "sil-card-title"),
        shiny::selectInput("edit_view", "Hemisphere and view", choices = view_values),
        shiny::sliderInput(
          "smooth_strength", "Selected-line smoothing",
          min = 0, max = 6, value = 1, step = 0.25
        ),
        shiny::tags$div(class = "sil-status", shiny::textOutput("selection_status")),
        shiny::tags$div(
          class = "sil-actions",
          shiny::actionButton(
            "apply_smoothing", "Smooth selected", class = "btn-primary"
          ),
          shiny::actionButton("delete_line", "Delete selected"),
          shiny::actionButton("undo_edit", "Undo"),
          shiny::actionButton("redo_edit", "Redo")
        ),
        shiny::actionButton(
          "reset_view", "Reset current view", class = "btn-default"
        ),
        shiny::br(),
        shiny::actionButton(
          "save_silhouette", "Save and return to R", class = "btn-success"
        )
      ),
      shiny::tags$section(
        class = "sil-card sil-preview",
        shiny::tags$h2(
          "Click, Shift-click, or drag to select lines",
          class = "sil-card-title"
        ),
        shiny::plotOutput(
          "silhouette_plot",
          click = "silhouette_click",
          brush = shiny::brushOpts(
            id = "silhouette_brush", direction = "xy", resetOnNew = TRUE,
            delay = 100, delayType = "debounce"
          ),
          height = "700px"
        )
      )
    )
  )

  server <- function(input, output, session) {
    current <- shiny::reactiveVal(lines)
    selected_ids <- shiny::reactiveVal(integer())
    undo_stack <- shiny::reactiveVal(list())
    redo_stack <- shiny::reactiveVal(list())

    visible_indices <- shiny::reactive({
      value <- current()
      which(value$.editor_group == input$edit_view)
    })
    save_history <- function() {
      undo_stack(c(undo_stack(), list(current())))
      redo_stack(list())
    }
    selection_index <- shiny::reactive({
      which(current()$.silhouette_id %in% selected_ids())
    })
    preview_geometry <- shiny::reactive({
      indices <- selection_index()
      if (!length(indices)) return(sf::st_sfc(crs = sf::st_crs(current())))
      sf::st_sfc(lapply(indices, function(index) {
        silhouette_smooth_line(
          sf::st_geometry(current())[[index]], input$smooth_strength
        )
      }), crs = sf::st_crs(current()))
    })

    output$selection_status <- shiny::renderText({
      indices <- selection_index()
      if (!length(indices)) {
        "No lines selected. Click near a line or drag a selection box."
      } else {
        sprintf(
          "%d line%s selected · %d coordinates",
          length(indices), if (length(indices) == 1L) "" else "s",
          sum(vapply(indices, function(index) {
            nrow(sf::st_coordinates(sf::st_geometry(current())[[index]]))
          }, integer(1)))
        )
      }
    })
    output$silhouette_plot <- shiny::renderPlot({
      value <- current()
      indices <- visible_indices()
      if (!length(indices)) {
        graphics::plot.new()
        graphics::title("No lines remain in this view", col.main = "white")
        return()
      }
      graphics::par(mar = c(1, 1, 1, 1), bg = "#171717")
      graphics::plot(
        sf::st_geometry(value[indices, , drop = FALSE]),
        col = "#c4c9cc", lwd = 1.3, axes = FALSE, asp = 1
      )
      selected <- selection_index()
      if (length(selected) && any(selected %in% indices)) {
        graphics::plot(
          preview_geometry()[selected %in% indices],
          add = TRUE, col = "#ffb347", lwd = 3
        )
      }
    })

    shiny::observeEvent(input$edit_view, selected_ids(integer()), ignoreInit = TRUE)
    shiny::observeEvent(input$silhouette_click, {
      indices <- visible_indices()
      if (!length(indices)) return()
      value <- current()[indices, , drop = FALSE]
      point <- sf::st_sfc(
        sf::st_point(c(input$silhouette_click$x, input$silhouette_click$y)),
        crs = sf::st_crs(value)
      )
      distances <- as.numeric(sf::st_distance(point, value))
      nearest <- which.min(distances)
      bounds <- sf::st_bbox(value)
      diagonal <- sqrt((bounds[["xmax"]] - bounds[["xmin"]])^2 +
                         (bounds[["ymax"]] - bounds[["ymin"]])^2)
      if (length(nearest) && is.finite(distances[[nearest]]) &&
          distances[[nearest]] <= diagonal * click_tolerance) {
        clicked <- value$.silhouette_id[[nearest]]
        if (isTRUE(input$shift_down)) {
          existing <- selected_ids()
          selected_ids(if (clicked %in% existing) {
            setdiff(existing, clicked)
          } else {
            c(existing, clicked)
          })
        } else {
          selected_ids(clicked)
        }
      } else {
        if (!isTRUE(input$shift_down)) selected_ids(integer())
      }
    })
    shiny::observeEvent(input$silhouette_brush, {
      brush <- input$silhouette_brush
      indices <- visible_indices()
      if (is.null(brush) || !length(indices)) return()
      rectangle <- sf::st_polygon(list(matrix(c(
        brush$xmin, brush$ymin,
        brush$xmax, brush$ymin,
        brush$xmax, brush$ymax,
        brush$xmin, brush$ymax,
        brush$xmin, brush$ymin
      ), ncol = 2L, byrow = TRUE)))
      hits <- lengths(sf::st_intersects(
        current()[indices, , drop = FALSE],
        sf::st_sfc(rectangle, crs = sf::st_crs(current()))
      )) > 0L
      brushed <- current()$.silhouette_id[indices[hits]]
      if (isTRUE(input$shift_down)) {
        selected_ids(unique(c(selected_ids(), brushed)))
      } else {
        selected_ids(brushed)
      }
    })
    shiny::observeEvent(input$apply_smoothing, {
      indices <- selection_index()
      if (!length(indices)) return()
      save_history()
      value <- current()
      geometry <- sf::st_geometry(value)
      geometry[indices] <- preview_geometry()
      sf::st_geometry(value) <- geometry
      current(value)
    })
    shiny::observeEvent(input$delete_line, {
      indices <- selection_index()
      if (!length(indices)) return()
      save_history()
      value <- current()[-indices, , drop = FALSE]
      current(value)
      selected_ids(integer())
    })
    shiny::observeEvent(input$reset_view, {
      indices <- visible_indices()
      save_history()
      value <- current()
      keep <- value$.editor_group != input$edit_view
      original_view <- lines[lines$.editor_group == input$edit_view, , drop = FALSE]
      current(rbind(value[keep, , drop = FALSE], original_view))
      selected_ids(integer())
    })
    shiny::observeEvent(input$undo_edit, {
      history <- undo_stack()
      if (!length(history)) return()
      redo_stack(c(redo_stack(), list(current())))
      current(history[[length(history)]])
      undo_stack(history[-length(history)])
      selected_ids(integer())
    })
    shiny::observeEvent(input$redo_edit, {
      future <- redo_stack()
      if (!length(future)) return()
      undo_stack(c(undo_stack(), list(current())))
      current(future[[length(future)]])
      redo_stack(future[-length(future)])
      selected_ids(integer())
    })
    shiny::observeEvent(input$save_silhouette, shiny::stopApp(current()))
    session$onSessionEnded(function() shiny::stopApp(NULL))
  }

  shiny::runApp(shiny::shinyApp(ui, server), launch.browser = TRUE)
}

