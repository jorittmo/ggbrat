#' Build orthogonal 2D atlases from volumetric NIfTI images
#'
#' `build_atlas_vol()` combines a discrete-label subcortical atlas with a
#' thresholded gray-matter or anatomical context image and converts orthogonal
#' slices into `sf` polygons. Region boundaries are polygonized directly from
#' raster cells; no hull reconstruction is performed.
#'
#' By default, the nearest voxel plane to world coordinate zero is selected for
#' axial, sagittal, and coronal views. The input images must currently share the
#' same dimensions and voxel-to-world affine transformation.
#'
#' @param atlas_path Path to a discrete-label NIfTI atlas.
#' @param lookup_path Optional CSV whose first two columns contain numeric labels
#'   and region names. Headerless files are supported.
#' @param gray_matter_path Path to the gray-matter probability or anatomical
#'   context NIfTI. When `NULL`, the function searches `data/nifti`, preferring
#'   a filename containing `GM` or `probseg`.
#' @param gray_matter_threshold Values greater than or equal to this threshold
#'   are included in the context mask.
#' @param views Any ordered subset of `"axial"`, `"sagittal"`, and
#'   `"coronal"`.
#' @param slice_coordinates Named world coordinates for the requested views.
#'   Defaults to coordinate zero for every view.
#' @param labels Optional numeric atlas labels to include. The default includes
#'   every nonzero label intersecting a selected slice.
#' @param include_gray_matter Whether to include the thresholded context region.
#' @param gray_matter_region Region name assigned to the context polygons.
#'   May be `NA_character_` when the context should not be treated as an atlas
#'   region.
#' @param exclude_atlas_from_gray_matter Whether atlas-labelled cells should be
#'   removed from the context mask so the returned polygons form a nonoverlapping
#'   categorical atlas.
#' @param smooth_iterations Strength of geometric outline smoothing, expressed
#'   in voxel-width steps. Zero (the default) preserves exact voxel boundaries;
#'   values from 1 to 3 progressively round atlas-region stair-step edges.
#'   Fractional values are supported. Smoothing uses
#'   morphological buffers followed by simplification and does not repeatedly
#'   multiply the number of boundary vertices.
#' @param gray_matter_smooth_iterations Smoothing strength for the gray-matter
#'   context outline. By default this inherits `smooth_iterations`; set it
#'   separately when the cortex needs less smoothing than the atlas regions.
#' @param interactive If `TRUE`, open an interactive slice selector. The user
#'   can switch anatomical axes, scroll through slices, and save `n_views`
#'   selections before polygon construction begins. Requires the suggested
#'   package `shiny`.
#' @param n_views Number of slices to save in interactive mode.
#'
#' @return An `sf` object with region polygons and columns `region`, `label`,
#'   `tissue`, `axis`, `int_view`, `view`, `selection_order`, `slice_index`,
#'   `slice_coordinate`, and `requested_coordinate`. `int_view` numbers slices
#'   within each anatomical axis and `view` combines the axis and number, for
#'   example `"axial_2"`. Use `ggplot2::facet_wrap(~view)` to display views
#'   separately.
#'
#' @examples
#' \dontrun{
#' atlas <- build_atlas_vol(
#'   atlas_path = paste0(
#'     "data/subcortical/MNI152NLin2009cAsym/Melbourne_S1/",
#'     "Melbourne_S1.nii.gz"
#'   ),
#'   lookup_path = paste0(
#'     "data/subcortical/MNI152NLin2009cAsym/Melbourne_S1/",
#'     "Melbourne_S1_lookup.csv"
#'   )
#' )
#'
#' ggplot2::ggplot(atlas) +
#'   ggplot2::geom_sf(ggplot2::aes(fill = region), linewidth = 0.2) +
#'   ggplot2::facet_wrap(~view) +
#'   ggplot2::theme_void()
#' }
#' @export
build_atlas_vol <- function(
  atlas_path,
  lookup_path = NULL,
  gray_matter_path = NULL,
  gray_matter_threshold = 0.5,
  views = c("axial", "sagittal", "coronal"),
  slice_coordinates = c(axial = 0, sagittal = 0, coronal = 0),
  labels = NULL,
  include_gray_matter = TRUE,
  gray_matter_region = "gray_matter",
  exclude_atlas_from_gray_matter = TRUE,
  smooth_iterations = 0,
  gray_matter_smooth_iterations = smooth_iterations,
  interactive = FALSE,
  n_views = NULL
) {
  vol_validate_file(atlas_path, "atlas_path")
  gray_matter_path <- vol_resolve_context_path(gray_matter_path)
  vol_validate_file(gray_matter_path, "gray_matter_path")

  allowed_views <- c("axial", "sagittal", "coronal")
  if (!is.character(views) || !length(views) || anyDuplicated(views) ||
      any(!views %in% allowed_views)) {
    stop(
      "`views` must be a unique subset of \"axial\", \"sagittal\", and \"coronal\".",
      call. = FALSE
    )
  }
  if (!is.logical(interactive) || length(interactive) != 1L || is.na(interactive)) {
    stop("`interactive` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!interactive && (!is.numeric(slice_coordinates) ||
      is.null(names(slice_coordinates)) ||
      any(!views %in% names(slice_coordinates)) ||
      any(!is.finite(slice_coordinates[views])))) {
    stop("`slice_coordinates` must provide one finite named value per view.", call. = FALSE)
  }
  if (interactive && (!is.numeric(n_views) || length(n_views) != 1L ||
      is.na(n_views) || !is.finite(n_views) || n_views < 1 ||
      n_views != round(n_views))) {
    stop("`n_views` must be one positive integer in interactive mode.", call. = FALSE)
  }
  if (!is.numeric(gray_matter_threshold) || length(gray_matter_threshold) != 1L ||
      is.na(gray_matter_threshold) || !is.finite(gray_matter_threshold)) {
    stop("`gray_matter_threshold` must be one finite number.", call. = FALSE)
  }
  for (option in c("include_gray_matter", "exclude_atlas_from_gray_matter")) {
    value <- get(option)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("`", option, "` must be TRUE or FALSE.", call. = FALSE)
    }
  }
  if (!is.character(gray_matter_region) || length(gray_matter_region) != 1L ||
      (!is.na(gray_matter_region) && !nzchar(gray_matter_region))) {
    stop("`gray_matter_region` must be one non-empty string or `NA_character_`.",
         call. = FALSE)
  }
  for (argument in c("smooth_iterations", "gray_matter_smooth_iterations")) {
    value <- get(argument)
    if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
        !is.finite(value) || value < 0) {
      stop("`", argument, "` must be one non-negative number.", call. = FALSE)
    }
  }

  atlas_image <- RNifti::readNifti(atlas_path, internal = FALSE)
  context_image <- RNifti::readNifti(gray_matter_path, internal = FALSE)
  atlas <- vol_as_3d_array(atlas_image, "atlas_path")
  context <- vol_as_3d_array(context_image, "gray_matter_path")
  atlas_xform <- RNifti::xform(atlas_image)
  context_xform <- RNifti::xform(context_image)

  if (!identical(dim(atlas), dim(context)) ||
      !isTRUE(all.equal(atlas_xform, context_xform, tolerance = 1e-5,
                        check.attributes = FALSE))) {
    stop(
      "The atlas and context NIfTI images must have identical dimensions and ",
      "voxel-to-world affine transformations.",
      call. = FALSE
    )
  }
  axis_map <- vol_axis_map(atlas_xform)

  atlas_values <- atlas[is.finite(atlas) & atlas != 0]
  if (length(atlas_values) && any(abs(atlas_values - round(atlas_values)) > 1e-5)) {
    stop("`atlas_path` must contain discrete integer labels.", call. = FALSE)
  }
  atlas <- round(atlas)
  finite_context <- context[is.finite(context)]
  if (!length(finite_context)) {
    stop("`gray_matter_path` does not contain any finite values.", call. = FALSE)
  }
  context_range <- range(finite_context)
  if (include_gray_matter &&
      (context_range[[1]] < -1e-6 || context_range[[2]] > 1 + 1e-6) &&
      identical(gray_matter_threshold, 0.5)) {
    warning(
      "The context image is not in the probability range [0, 1]; ",
      "`gray_matter_threshold = 0.5` may not represent gray matter.",
      call. = FALSE
    )
  }

  lookup <- vol_read_lookup(lookup_path)
  if (!is.null(labels) && (!is.numeric(labels) || any(!is.finite(labels)))) {
    stop("`labels` must be a vector of finite numeric atlas labels.", call. = FALSE)
  }
  requested_labels <- if (is.null(labels)) NULL else unique(as.numeric(labels))
  pieces <- list()
  slice_axes <- c(sagittal = 1L, coronal = 2L, axial = 3L)
  display_axes <- list(
    sagittal = c(2L, 3L),
    coronal = c(1L, 3L),
    axial = c(1L, 2L)
  )

  selections <- if (interactive) {
    vol_select_slices_interactive(
      atlas = atlas,
      context = context,
      xform = atlas_xform,
      axis_map = axis_map,
      axes = views,
      n_views = as.integer(n_views),
      threshold = gray_matter_threshold,
      requested_labels = requested_labels
    )
  } else {
    vol_slice_selections(
      views, slice_coordinates, dim(atlas), atlas_xform, axis_map
    )
  }
  if (is.null(selections) || !nrow(selections)) {
    stop("Interactive slice selection was cancelled; no atlas was built.", call. = FALSE)
  }

  for (selection_index in seq_len(nrow(selections))) {
    axis <- selections$axis[[selection_index]]
    view <- selections$view[[selection_index]]
    world_slice_axis <- slice_axes[[axis]]
    voxel_slice_axis <- axis_map$world_to_voxel[[world_slice_axis]]
    slice_world_values <- vol_axis_coordinates(
      dim(atlas)[[voxel_slice_axis]], voxel_slice_axis, world_slice_axis, atlas_xform
    )
    slice_index <- selections$slice_index[[selection_index]]
    atlas_slice <- vol_extract_slice(atlas, voxel_slice_axis, slice_index)
    context_slice <- vol_extract_slice(context, voxel_slice_axis, slice_index)

    wanted_world_axes <- display_axes[[axis]]
    remaining_voxel_axes <- setdiff(seq_len(3L), voxel_slice_axis)
    wanted_voxel_axes <- axis_map$world_to_voxel[wanted_world_axes]
    permutation <- match(wanted_voxel_axes, remaining_voxel_axes)
    atlas_slice <- aperm(atlas_slice, permutation)
    context_slice <- aperm(context_slice, permutation)
    horizontal <- vol_axis_coordinates(
      nrow(atlas_slice), wanted_voxel_axes[[1]], wanted_world_axes[[1]], atlas_xform
    )
    vertical <- vol_axis_coordinates(
      ncol(atlas_slice), wanted_voxel_axes[[2]], wanted_world_axes[[2]], atlas_xform
    )

    label_values <- sort(unique(atlas_slice[atlas_slice != 0]))
    if (!is.null(requested_labels)) {
      label_values <- intersect(label_values, requested_labels)
    }
    if (include_gray_matter) {
      context_mask <- is.finite(context_slice) & context_slice >= gray_matter_threshold
      if (exclude_atlas_from_gray_matter) context_mask <- context_mask & atlas_slice == 0
      geometry <- vol_mask_polygon(context_mask, horizontal, vertical)
      if (!is.null(geometry)) {
        geometry <- vol_smooth_geometry(
          geometry, gray_matter_smooth_iterations,
          vol_slice_resolution(horizontal, vertical)
        )
        pieces[[length(pieces) + 1L]] <- vol_slice_feature(
          gray_matter_region, NA_real_, "gray_matter", axis, view,
          selections$int_view[[selection_index]], selection_index,
          slice_index, slice_world_values[[slice_index]],
          selections$requested_coordinate[[selection_index]], geometry
        )
      }
    }
    for (label in label_values) {
      geometry <- vol_mask_polygon(atlas_slice == label, horizontal, vertical)
      if (is.null(geometry)) next
      geometry <- vol_smooth_geometry(
        geometry, smooth_iterations,
        vol_slice_resolution(horizontal, vertical)
      )
      region <- lookup$region[match(label, lookup$label)]
      if (is.na(region)) region <- paste0("label_", format(label, trim = TRUE))
      pieces[[length(pieces) + 1L]] <- vol_slice_feature(
        region, label, "subcortical", axis, view,
        selections$int_view[[selection_index]], selection_index, slice_index,
        slice_world_values[[slice_index]],
        selections$requested_coordinate[[selection_index]], geometry
      )
    }
  }

  if (!length(pieces)) {
    return(sf::st_sf(
      region = character(), label = numeric(), tissue = character(),
      axis = character(), view = character(), int_view = integer(),
      selection_order = integer(), slice_index = integer(),
      slice_coordinate = numeric(), requested_coordinate = numeric(),
      geometry = sf::st_sfc(crs = sf::NA_crs_)
    ))
  }
  do.call(rbind, pieces)
}

vol_validate_file <- function(path, name) {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path) || !file.exists(path)) {
    stop("`", name, "` must name an existing NIfTI file.", call. = FALSE)
  }
}

vol_resolve_context_path <- function(path) {
  if (!is.null(path)) return(path)
  directories <- unique(c(
    file.path("data", "nifti"),
    system.file("data", "nifti", package = "ggbrat")
  ))
  directories <- directories[nzchar(directories) & dir.exists(directories)]
  candidates <- unique(normalizePath(unlist(lapply(directories, function(directory) {
    Sys.glob(file.path(directory, "*.nii*"))
  }), use.names = FALSE), mustWork = FALSE))
  preferred <- candidates[grepl("GM|probseg", basename(candidates), ignore.case = TRUE)]
  selected <- if (length(preferred) == 1L) preferred else candidates
  if (length(selected) != 1L) {
    stop(
      "Could not identify one context NIfTI in `data/nifti`; ",
      "supply `gray_matter_path` explicitly.",
      call. = FALSE
    )
  }
  selected[[1]]
}

vol_as_3d_array <- function(image, name) {
  array <- as.array(image)
  dimensions <- dim(array)
  if (length(dimensions) > 3L && all(dimensions[-seq_len(3L)] == 1L)) {
    dim(array) <- dimensions[seq_len(3L)]
  }
  if (length(dim(array)) != 3L) {
    stop("`", name, "` must contain one three-dimensional volume.", call. = FALSE)
  }
  array
}

vol_axis_map <- function(xform, tolerance = 1e-6) {
  linear <- xform[1:3, 1:3, drop = FALSE]
  world_to_voxel <- apply(abs(linear), 1L, which.max)
  if (length(unique(world_to_voxel)) != 3L) {
    stop("The NIfTI affine does not define three distinct anatomical axes.", call. = FALSE)
  }
  selected <- linear[cbind(seq_len(3L), world_to_voxel)]
  residual <- linear
  residual[cbind(seq_len(3L), world_to_voxel)] <- 0
  if (any(abs(residual) > tolerance) || any(abs(selected) <= tolerance)) {
    stop("Oblique NIfTI affines are not currently supported.", call. = FALSE)
  }
  list(world_to_voxel = world_to_voxel)
}

vol_axis_coordinates <- function(n, voxel_axis, world_axis, xform) {
  xform[[world_axis, 4L]] + xform[[world_axis, voxel_axis]] * (seq_len(n) - 1L)
}

vol_extract_slice <- function(array, axis, index) {
  indices <- rep(list(TRUE), 3L)
  indices[[axis]] <- index
  do.call(`[`, c(list(array), indices, list(drop = TRUE)))
}

vol_slice_selections <- function(axes, coordinates, dimensions, xform, axis_map) {
  slice_axes <- c(sagittal = 1L, coronal = 2L, axial = 3L)
  selections <- lapply(seq_along(axes), function(index) {
    axis <- axes[[index]]
    world_axis <- slice_axes[[axis]]
    voxel_axis <- axis_map$world_to_voxel[[world_axis]]
    world_values <- vol_axis_coordinates(
      dimensions[[voxel_axis]], voxel_axis, world_axis, xform
    )
    slice_index <- which.min(abs(world_values - coordinates[[axis]]))
    data.frame(
      axis = axis,
      int_view = 1L,
      view = paste0(axis, "_1"),
      selection_order = index,
      slice_index = slice_index,
      requested_coordinate = coordinates[[axis]],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, selections)
}

vol_slice_preview <- function(
  atlas, context, axis, slice_index, axis_map, threshold, requested_labels = NULL
) {
  slice_axes <- c(sagittal = 1L, coronal = 2L, axial = 3L)
  voxel_axis <- axis_map$world_to_voxel[[slice_axes[[axis]]]]
  atlas_slice <- vol_extract_slice(atlas, voxel_axis, slice_index)
  context_slice <- vol_extract_slice(context, voxel_axis, slice_index)
  labels <- sort(unique(atlas_slice[is.finite(atlas_slice) & atlas_slice != 0]))
  if (!is.null(requested_labels)) labels <- intersect(labels, requested_labels)

  preview <- matrix(0L, nrow(atlas_slice), ncol(atlas_slice))
  preview[is.finite(context_slice) & context_slice >= threshold] <- 1L
  for (index in seq_along(labels)) {
    preview[atlas_slice == labels[[index]]] <- index + 1L
  }
  list(values = preview, labels = labels)
}

vol_select_slices_interactive <- function(
  atlas, context, xform, axis_map, axes, n_views, threshold,
  requested_labels = NULL
) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop(
      "Interactive slice selection requires the suggested package `shiny`. ",
      "Install it with install.packages(\"shiny\").",
      call. = FALSE
    )
  }
  slice_axes <- c(sagittal = 1L, coronal = 2L, axial = 3L)
  axis_info <- lapply(axes, function(axis) {
    world_axis <- slice_axes[[axis]]
    voxel_axis <- axis_map$world_to_voxel[[world_axis]]
    coordinates <- vol_axis_coordinates(
      dim(atlas)[[voxel_axis]], voxel_axis, world_axis, xform
    )
    list(voxel_axis = voxel_axis, coordinates = coordinates)
  })
  names(axis_info) <- axes

  ui <- shiny::fluidPage(
    shiny::tags$head(
      shiny::tags$style(htmltools::HTML(
        paste0(
          "body{background:#151719;color:#eee;font-family:system-ui,-apple-system,",
          "BlinkMacSystemFont,'Segoe UI',sans-serif}",
          ".container-fluid{max-width:1380px;margin:0 auto;padding:24px}",
          ".atlas-title{margin:0 0 20px 2px;font-size:27px;font-weight:650}",
          ".atlas-layout{display:grid;grid-template-columns:minmax(280px,340px) ",
          "minmax(0,1fr);gap:20px;align-items:start}",
          ".atlas-card{background:#232629;border:1px solid #383c40;",
          "border-radius:18px;padding:22px;box-shadow:0 10px 30px rgba(0,0,0,.22)}",
          ".atlas-preview{padding:12px 16px 16px;min-width:0}",
          ".atlas-card-title{font-size:16px;font-weight:650;margin:0 0 18px}",
          ".control-label{color:#e8e8e8;font-weight:550}",
          ".form-control{background:#181a1c;color:#eee;border-color:#4a4e52;",
          "border-radius:9px}",
          ".irs--shiny .irs-bar,.irs--shiny .irs-single{background:#337ab7;",
          "border-color:#337ab7}",
          ".atlas-actions{display:flex;gap:9px;flex-wrap:wrap}",
          "#use_view{border-radius:12px;padding:9px 16px;font-weight:650}",
          "#undo_view{border-radius:12px;padding:9px 16px;background:#34383c;",
          "color:#eee;border-color:#50555a}",
          ".atlas-progress{margin:18px 0 8px;font-weight:600;color:#cfd4d8}",
          "#saved{font-size:12px;color:#ddd}",
          "#saved table{background:transparent}",
          ".modal-content{background:#232629;color:#eee;border:1px solid #454a4f;",
          "border-radius:18px;box-shadow:0 18px 55px rgba(0,0,0,.45)}",
          ".modal-header{border-bottom-color:#3d4246}",
          ".atlas-done{text-align:center;padding:10px 8px 16px}",
          ".atlas-done h2{font-size:27px;font-weight:700;margin:4px 0 10px}",
          ".atlas-done p{color:#cbd0d4;margin-bottom:22px}",
          "#return_to_r{border-radius:12px;padding:10px 22px;font-weight:650}",
          "#slice_plot{cursor:ns-resize;width:100%}",
          "@media(max-width:800px){.atlas-layout{grid-template-columns:1fr}}"
        )
      )),
      shiny::tags$script(htmltools::HTML(
        "$(document).on('wheel', '#slice_plot', function(e) {\n",
        "  e.preventDefault();\n",
        "  Shiny.setInputValue('slice_wheel', {",
        "delta: e.originalEvent.deltaY > 0 ? -1 : 1, nonce: Math.random()",
        "}, {priority: 'event'});\n",
        "});"
      ))
    ),
    shiny::tags$h1("Choose volumetric atlas slices", class = "atlas-title"),
    shiny::tags$div(
      class = "atlas-layout",
      shiny::tags$section(
        class = "atlas-card atlas-controls",
        shiny::tags$h2("Slice controls", class = "atlas-card-title"),
        shiny::selectInput("axis", "Anatomical axis", choices = axes),
        shiny::sliderInput("slice", "Slice", min = 1, max = 2, value = 1,
                           step = 1, animate = FALSE),
        shiny::textOutput("coordinate"),
        shiny::hr(),
        shiny::tags$div(
          class = "atlas-actions",
          shiny::actionButton("use_view", "Use this view", class = "btn-primary"),
          shiny::actionButton("undo_view", "Undo last view")
        ),
        shiny::tags$div(class = "atlas-progress", shiny::textOutput("progress")),
        shiny::tableOutput("saved")
      ),
      shiny::tags$section(
        class = "atlas-card atlas-preview",
        shiny::tags$h2("Brain preview", class = "atlas-card-title"),
        shiny::plotOutput("slice_plot", height = "650px")
      )
    )
  )

  server <- function(input, output, session) {
    saved <- shiny::reactiveVal(data.frame(
      axis = character(), slice_index = integer(), slice_coordinate = numeric(),
      stringsAsFactors = FALSE
    ))

    update_axis <- function(axis) {
      info <- axis_info[[axis]]
      middle <- which.min(abs(info$coordinates))
      shiny::updateSliderInput(
        session, "slice", min = 1L, max = length(info$coordinates), value = middle
      )
    }
    shiny::observeEvent(input$axis, update_axis(input$axis), ignoreInit = FALSE)
    shiny::observeEvent(input$slice_wheel, {
      shiny::req(input$slice)
      maximum <- length(axis_info[[input$axis]]$coordinates)
      value <- max(1L, min(maximum, input$slice + input$slice_wheel$delta))
      shiny::updateSliderInput(session, "slice", value = value)
    })

    output$coordinate <- shiny::renderText({
      shiny::req(input$axis, input$slice)
      coordinate <- axis_info[[input$axis]]$coordinates[[input$slice]]
      sprintf("Voxel %d · world coordinate %.2f mm", input$slice, coordinate)
    })
    output$progress <- shiny::renderText({
      sprintf("Saved views: %d of %d", nrow(saved()), n_views)
    })
    output$saved <- shiny::renderTable({
      selected <- saved()
      if (!nrow(selected)) return(NULL)
      selected
    }, rownames = FALSE, digits = 2)
    output$slice_plot <- shiny::renderPlot({
      shiny::req(input$axis, input$slice)
      preview <- vol_slice_preview(
        atlas, context, input$axis, input$slice, axis_map, threshold,
        requested_labels
      )
      palette <- c("#171717", "#b8b8b8")
      if (length(preview$labels)) {
        palette <- c(palette, grDevices::hcl.colors(length(preview$labels), "Set 2"))
      }
      graphics::par(mar = c(0, 0, 2, 0), bg = "#171717")
      # Rotate the display counterclockwise relative to the raw matrix. This is
      # presentation-only and does not affect the selected voxel plane.
      display_values <- preview$values[nrow(preview$values):1L, , drop = FALSE]
      graphics::image(
        display_values, axes = FALSE, asp = 1,
        col = palette, useRaster = TRUE,
        main = paste(tools::toTitleCase(input$axis), "slice", input$slice),
        col.main = "white"
      )
    }, bg = "#171717")

    shiny::observeEvent(input$use_view, {
      shiny::req(input$axis, input$slice)
      selected <- saved()
      coordinate <- axis_info[[input$axis]]$coordinates[[input$slice]]
      selected <- rbind(selected, data.frame(
        axis = input$axis,
        slice_index = as.integer(input$slice),
        slice_coordinate = coordinate,
        stringsAsFactors = FALSE
      ))
      saved(selected)
      if (nrow(selected) >= n_views) {
        shiny::showModal(shiny::modalDialog(
          shiny::tags$div(
            class = "atlas-done",
            shiny::tags$h2("Atlas done!"),
            shiny::tags$p(
              "All requested views have been selected. Return to R to build the atlas."
            ),
            shiny::actionButton(
              "return_to_r", "Return to R", class = "btn-primary"
            )
          ),
          footer = NULL,
          easyClose = FALSE,
          size = "s"
        ))
      }
    })
    shiny::observeEvent(input$return_to_r, {
      selected <- saved()
      if (nrow(selected) >= n_views) shiny::stopApp(selected)
    })
    shiny::observeEvent(input$undo_view, {
      selected <- saved()
      if (nrow(selected)) saved(selected[-nrow(selected), , drop = FALSE])
    })
    session$onSessionEnded(function() shiny::stopApp(NULL))
  }

  selected <- shiny::runApp(shiny::shinyApp(ui, server), launch.browser = TRUE)
  if (is.null(selected) || !nrow(selected)) return(NULL)
  selected$selection_order <- seq_len(nrow(selected))
  selected$int_view <- ave(
    selected$selection_order, selected$axis, FUN = seq_along
  )
  selected$view <- paste(selected$axis, selected$int_view, sep = "_")
  selected$requested_coordinate <- selected$slice_coordinate
  selected[c(
    "axis", "int_view", "view", "selection_order", "slice_index",
    "requested_coordinate"
  )]
}

vol_mask_polygon <- function(mask, horizontal, vertical) {
  if (!any(mask, na.rm = TRUE)) return(NULL)
  mask[is.na(mask)] <- FALSE
  horizontal_step <- if (length(horizontal) > 1L) stats::median(diff(horizontal)) else 1
  vertical_step <- if (length(vertical) > 1L) stats::median(diff(vertical)) else 1
  if (horizontal_step < 0) {
    horizontal <- rev(horizontal)
    mask <- mask[nrow(mask):1L, , drop = FALSE]
    horizontal_step <- -horizontal_step
  }
  if (vertical_step < 0) {
    vertical <- rev(vertical)
    mask <- mask[, ncol(mask):1L, drop = FALSE]
    vertical_step <- -vertical_step
  }
  padded <- matrix(FALSE, nrow(mask) + 2L, ncol(mask) + 2L)
  padded[2:(nrow(mask) + 1L), 2:(ncol(mask) + 1L)] <- mask
  x <- c(horizontal[[1]] - horizontal_step, horizontal,
         horizontal[[length(horizontal)]] + horizontal_step)
  y <- c(vertical[[1]] - vertical_step, vertical,
         vertical[[length(vertical)]] + vertical_step)
  bands <- isoband::isobands(x, y, t(padded) * 1, 0.5, 1.5)
  isoband::iso_to_sfg(bands)[[1]]
}

vol_slice_resolution <- function(horizontal, vertical) {
  steps <- c(diff(horizontal), diff(vertical))
  min(abs(steps[is.finite(steps) & steps != 0]))
}

vol_smooth_geometry <- function(geometry, iterations, resolution = 1) {
  if (iterations == 0L) return(geometry)
  distance <- iterations * resolution
  original <- sf::st_sfc(geometry, crs = sf::NA_crs_)

  # Closing fills narrow notches; the following, gentler opening rounds outward
  # voxel corners. Low nQuadSegs keeps curved outlines compact.
  smoothed <- sf::st_buffer(original, distance, nQuadSegs = 4)
  smoothed <- sf::st_buffer(smoothed, -distance, nQuadSegs = 4)
  opening_distance <- distance / 2
  opened <- sf::st_buffer(smoothed, -opening_distance, nQuadSegs = 4)
  if (!all(sf::st_is_empty(opened))) {
    smoothed <- sf::st_buffer(opened, opening_distance, nQuadSegs = 4)
  }
  smoothed <- sf::st_simplify(
    smoothed,
    preserveTopology = TRUE,
    dTolerance = resolution / 4
  )
  smoothed <- sf::st_make_valid(smoothed)
  polygons <- suppressWarnings(sf::st_collection_extract(smoothed, "POLYGON"))
  if (!length(polygons) || all(sf::st_is_empty(polygons))) return(geometry)
  sf::st_cast(polygons, "MULTIPOLYGON")[[1]]
}

vol_slice_feature <- function(
  region, label, tissue, axis, view, view_index, selection_order, slice_index,
  slice_coordinate, requested_coordinate, geometry
) {
  sf::st_sf(
    region = region,
    label = label,
    tissue = tissue,
    axis = axis,
    view = view,
    int_view = as.integer(view_index),
    selection_order = as.integer(selection_order),
    slice_index = as.integer(slice_index),
    slice_coordinate = slice_coordinate,
    requested_coordinate = requested_coordinate,
    geometry = sf::st_sfc(geometry, crs = sf::NA_crs_)
  )
}

vol_read_lookup <- function(path) {
  if (is.null(path)) return(data.frame(label = numeric(), region = character()))
  vol_validate_file(path, "lookup_path")
  lookup <- utils::read.csv(
    path, header = FALSE, stringsAsFactors = FALSE,
    check.names = FALSE, fileEncoding = "UTF-8-BOM"
  )
  if (ncol(lookup) < 2L) stop("`lookup_path` must contain at least two columns.", call. = FALSE)
  numeric_labels <- suppressWarnings(as.numeric(lookup[[1]]))
  if (is.na(numeric_labels[[1]]) && nrow(lookup) > 1L) {
    lookup <- lookup[-1L, , drop = FALSE]
    numeric_labels <- suppressWarnings(as.numeric(lookup[[1]]))
  }
  if (anyNA(numeric_labels)) {
    stop("The first lookup column must contain numeric labels.", call. = FALSE)
  }
  data.frame(label = numeric_labels, region = as.character(lookup[[2]]))
}
