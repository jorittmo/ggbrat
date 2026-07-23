# Capture camera presets for later atlas builds

Capture camera presets for later atlas builds

## Usage

``` r
capture_brain_view_presets(
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
)
```

## Arguments

- annot_path:

  For cortical surfaces, a path to a single `.annot` or `.label.gii`
  file, or a named vector/list with `left` and `right`. May be `NULL`
  when `mesh_path` is supplied.

- preset_hemi:

  Hemisphere used to capture camera positions.

- n_views:

  Number of views to build. If `camera_positions` is supplied, this
  defaults to `length(camera_positions)`.

- view_names:

  Optional names for the views.

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

- sil_decimate:

  Fraction of silhouette polyline points to remove.

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

- label_array:

  Deprecated alias for `region_array`.

## Value

A named list of camera positions.
