# Build a shifted polygon atlas with shading support

This helper wraps the full atlas-building pipeline: visible vertex
extraction, view shifting, region polygon creation, and shade geometry
creation.

## Usage

``` r
build_atlas_surf(
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
)
```

## Arguments

- annot_path:

  For cortical surfaces, a path to a single `.annot` or `.label.gii`
  file, or a named vector/list with `left` and `right`. May be `NULL`
  when `mesh_path` is supplied.

- hemi:

  Hemisphere to process for cortical surfaces.

- n_views:

  Number of views to build. If `camera_positions` is supplied, this
  defaults to `length(camera_positions)`.

- view_names:

  Optional names for the views.

- camera_positions:

  Optional list of saved PyVista camera positions. When `NULL` in
  non-interactive mode, bundled presets are used and the first `n_views`
  presets are selected.

- interactive:

  Whether to capture camera positions interactively.

- surf_dir:

  Directory containing FreeSurfer surface files. When `NULL`, the
  requested fsaverage surfaces are downloaded to and resolved from the
  user-specific ggbrat cache.

- surface:

  A single surface name or a pair of surfaces to blend.

- surface_path:

  Optional named `left`/`right` paths to FreeSurfer or `.surf.gii`
  files. Supply a named list in which each hemisphere contains two paths
  to blend explicit files. Overrides `surf_dir` and `surface`.

- surf_blend_ratio:

  Weight assigned to the first surface when `surface` or each
  `surface_path` hemisphere contains two surfaces. The second surface
  receives weight `1 - surf_blend_ratio`.

- window_size:

  PyVista window size.

- include_silhouette:

  Whether to compute and return silhouettes.

- sil_decimate:

  Fraction of silhouette polyline points to remove.

- silhouette_min_length:

  Minimum retained silhouette-path length, or `"auto"` for approximately
  one output pixel.

- silhouette_tolerance:

  Line-simplification tolerance, or `"auto"` for approximately half an
  output pixel.

- smoothing_factor:

  Scaling factor used by
  [`ashape_polygon_sf()`](https://jorittmo.github.io/ggbrat/reference/ashape_polygon_sf.md).

- create_polygons:

  Whether to convert each region's projected `MULTIPOINT` geometry to a
  polygon. When `FALSE`, the region multipoints are returned unchanged.

- keep_z_coord:

  Whether to retain projected display depth as a third coordinate in
  returned multipoints. When `create_polygons = TRUE`, region polygons
  are constructed from X and Y only, while other multipoint layers such
  as `cortex` retain Z.

- shade_k:

  Number of neighbours used by
  [`knn_density_filter()`](https://jorittmo.github.io/ggbrat/reference/knn_density_filter.md)
  during shade creation.

- shade_keep_quantile:

  Quantile of dense points kept for shade creation.

- cell_dx:

  Horizontal spacing between shifted view cells.

- cell_dy:

  Vertical spacing between shifted view cells.

- n_cols:

  Number of columns in the shifted view grid.

- mesh_path:

  Optional path to a labelled VTK/VTP mesh, or a named pair with
  elements `left` and `right`. A pair follows the same mirrored-camera
  workflow as cortical hemispheres; a single mesh is rendered once per
  view.

- region_array:

  Name of the mesh point-data array containing region identifiers. Set
  this to another one-component point array, such as `"Label"`, when
  importing a mesh that does not contain `"region"`.

- color_array:

  Optional mesh point-data array containing region colors. When it is
  absent, deterministic colors are generated automatically.

- mesh_hemisphere:

  Value stored in the output `hemisphere` column for a generic mesh.

- add_cortex:

  Whether to add separately projected fsaverage surfaces as a
  glass-brain context layer. This currently requires paired meshes.

- cortex_surf_dir:

  Directory containing the left and right FreeSurfer cortical surfaces.
  The default uses `surf_dir`.

- cortex_surface:

  FreeSurfer surface name used for the glass layer.

- cortex_surface_path:

  Optional named `left`/`right` paths to FreeSurfer or GIFTI surfaces
  for the glass layer. Each hemisphere may alternatively contain two
  paths to blend. Overrides `cortex_surf_dir` and `cortex_surface`.

- cortex_point_method:

  How visible cortical points are retained: `"density"` keeps projected
  structural concentrations, `"sample"` takes a reproducible random
  sample, and `"all"` retains every visible vertex.

- cortex_point_fraction:

  Fraction of visible cortical vertices retained when
  `cortex_point_method = "sample"`.

- cortex_density_k:

  Number of neighbors used for projected cortical density estimation.

- cortex_density_keep_quantile:

  Fraction of the densest projected cortical vertices retained.

- cortex_max_points:

  Maximum density-filtered points retained per hemisphere and view. Use
  `NULL` for no cap.

- include_cortex_silhouette:

  Whether to return a cortical outline layer.

- cortex_preview_opacity:

  Opacity of the cortical surfaces shown only while interactively
  choosing a camera. This preview does not participate in target-mesh
  visibility calculations.

- label_array:

  Deprecated alias for `region_array`.

## Value

A list containing shifted atlas output in `atlas`, optional
`silhouette`, `camera_positions`, `shade`, and optional `cortex` and
`cortex_silhouette` glass-brain layers. `atlas` contains polygons when
`create_polygons = TRUE` and region multipoints otherwise.

## Examples

``` r
if (FALSE) { # \dontrun{
melbourne_mesh <- download_surface("Melbourne_S1", type = "subcortical")
subcortical_atlas <- build_atlas_surf(
  mesh_path = melbourne_mesh,
  add_cortex = TRUE,
  n_cols = 2
)
} # }
```
