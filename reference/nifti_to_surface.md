# Create a labelled surface mesh from a NIfTI atlas

Creates each nonzero atlas region independently using marching cubes,
then combines the disconnected components in one VTP file. The numeric
`label` and character `region` arrays are stored as both point and cell
data.

## Usage

``` r
nifti_to_surface(
  nifti_path,
  lookup_path = NULL,
  output_file = NULL,
  labels = NULL,
  split_hemispheres = FALSE,
  mask_threshold = 0.5,
  surface_style = c("faithful", "display"),
  minimum_component_voxels = 2L,
  closing_iterations = 1L,
  fill_voxel_holes = TRUE,
  distance_upsampling = 2L,
  preserve_volume = TRUE,
  small_region_method = c("ellipsoid", "mesh"),
  small_region_threshold = 20L,
  topology_correction = c("none", "genus0"),
  closing_radius = 1,
  max_closing_radius = 2,
  reduction = 0,
  subdivision = 0L,
  voxel_smoothing_sigma = 0,
  smoothing_method = c("windowed_sinc", "laplacian"),
  smoothing_iterations = 0L,
  smoothing_factor = 0.1,
  minimum_vertices = 4L,
  minimum_volume = 0.01,
  overwrite = FALSE
)
```

## Arguments

- nifti_path:

  Path to a discrete-label `.nii` or `.nii.gz` image, a directory of
  standalone region images, or a character vector of standalone region
  images.

- lookup_path:

  Optional CSV whose first two columns contain numeric labels and region
  names. Headerless files are supported.

- output_file:

  Destination `.vtp` file. By default it is named after the NIfTI image
  under the ggbrat user cache's `generated/surfaces` directory.

- labels:

  Optional numeric labels to include. The default uses every nonzero
  label in the image.

- split_hemispheres:

  Whether to create separate `_left.vtp` and `_right.vtp` meshes.
  Hemispheres are inferred from region-name components such as `_L`,
  `_R`, `left`, `right`, `lh`, and `rh` in the lookup table.

- mask_threshold:

  For standalone images, voxel values greater than or equal to this
  threshold are included in the region mask.

- surface_style:

  Standalone-mask surface style. `"faithful"` preserves the input mask;
  `"display"` enables cleanup and volume-preserving display geometry.

- minimum_component_voxels:

  Display-mode voxel islands smaller than this are removed.

- closing_iterations:

  Display-mode binary-closing iterations.

- fill_voxel_holes:

  Whether display mode fills enclosed voxel holes.

- distance_upsampling:

  Display-mode signed-distance upsampling factor.

- preserve_volume:

  Whether display-mode meshes are rescaled to the cleaned mask volume
  after smoothing.

- small_region_method:

  Either `"ellipsoid"` or `"mesh"` for very small standalone masks.

- small_region_threshold:

  Masks with fewer voxels use the selected small region method.

- topology_correction:

  Standalone display-mode topology correction. `"genus0"` adaptively
  closes tunnels; `"none"` preserves topology.

- closing_radius:

  Initial spherical closing radius in world-coordinate units for
  topology correction.

- max_closing_radius:

  Maximum adaptive spherical closing radius.

- reduction:

  Proportion of triangles to remove from each region, in `[0, 1)`.
  Cannot be combined with `subdivision`.

- subdivision:

  Number of linear subdivision levels from 0 through 3. Each level
  creates approximately four times as many triangles. This adds sampling
  vertices but does not add anatomical detail beyond the NIfTI.

- voxel_smoothing_sigma:

  Standard deviation, in voxels, for Gaussian smoothing of each label's
  signed-distance field before marching cubes. Zero preserves the exact
  voxel-derived boundary; values around 0.5 to 1.5 progressively reduce
  its staircase appearance.

- smoothing_method:

  Either `"windowed_sinc"`, which better preserves volume, or
  `"laplacian"`, which more strongly rounds voxel edges.

- smoothing_iterations:

  Number of windowed-sinc smoothing iterations.

- smoothing_factor:

  Smoothing strength in `(0, 1]`: the relaxation factor for Laplacian
  smoothing or passband for windowed-sinc smoothing.

- minimum_vertices:

  Connected components with fewer vertices are removed.

- minimum_volume:

  Connected components with a smaller volume in cubic world-coordinate
  units are removed.

- overwrite:

  Whether an existing output file may be replaced.

## Value

A list containing `output_file`, per-region mesh summaries, and total
vertex and face counts.

## Examples

``` r
if (FALSE) { # \dontrun{
brainstem_files <- download_volume_atlas("Brainstem_Navigator")
brainstem <- nifti_to_surface(
  nifti_path = brainstem_files$nifti,
  lookup_path = brainstem_files$lookup
)
} # }
```
