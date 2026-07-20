#' Build a shifted polygon atlas with shading support
#'
#' This helper wraps the full atlas-building pipeline: visible vertex
#' extraction, view shifting, parcel polygon creation, and shade geometry
#' creation.
#'
#' @inheritParams brain_views
#' @param smoothing_factor Scaling factor used by `ashape_polygon_sf()`.
#' @param shade_k Number of neighbours used by `knn_density_filter()` during
#'   shade creation.
#' @param shade_keep_quantile Quantile of dense points kept for shade creation.
#' @param cell_dx Horizontal spacing between shifted view cells.
#' @param cell_dy Vertical spacing between shifted view cells.
#' @param n_cols Number of columns in the shifted view grid.
#'
#' @return A list containing shifted atlas output with polygon geometries in
#'   `atlas`, optional `silhouette`, `camera_positions`, and `shade`.
#'
#' @examples
#' \dontrun{
#' subcortical_atlas <- build_brain_atlas(
#'   mesh_path = "data/subcortical/surfaces/Melbourne_S1.vtp",
#'   n_cols = 1
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
  surf_dir = "data/fsaverage/surf",
  surface = "pial",
  surf_blend_ratio = NULL,
  window_size = c(800L, 600L),
  include_silhouette = FALSE,
  sil_decimate = 0.1,
  smoothing_factor = 5,
  shade_k = 15,
  shade_keep_quantile = 0.2,
  cell_dx = 1.5,
  cell_dy = -1,
  n_cols = 2,
  mesh_path = NULL,
  label_array = "parcel",
  color_array = "color",
  mesh_hemisphere = "subcortical"
) {
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
    surf_blend_ratio = surf_blend_ratio,
    window_size = window_size,
    include_silhouette = include_silhouette,
    sil_decimate = sil_decimate,
    mesh_path = mesh_path,
    label_array = label_array,
    color_array = color_array,
    mesh_hemisphere = mesh_hemisphere
  )

  message("Step 2/4: Shifting atlas views into grid")
  atlas_shifted <- shift_brain_views(
    atlas_raw,
    cell_dx = cell_dx,
    cell_dy = cell_dy,
    n_cols = n_cols
  )

  message("Step 3/4: Creating parcel polygons")
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
  final_atlas$atlas$geometry <- ahulls
  final_atlas$shade <- shade

  message("Atlas build complete")
  final_atlas
}
