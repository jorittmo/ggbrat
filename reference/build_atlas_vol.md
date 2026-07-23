# Build orthogonal 2D atlases from volumetric NIfTI images

`build_atlas_vol()` combines a discrete-label subcortical atlas with a
thresholded gray-matter or anatomical context image and converts
orthogonal slices into `sf` polygons. Region boundaries are polygonized
directly from raster cells; no hull reconstruction is performed.

## Usage

``` r
build_atlas_vol(
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
)
```

## Arguments

- atlas_path:

  Path to a discrete-label NIfTI atlas.

- lookup_path:

  Optional CSV whose first two columns contain numeric labels and region
  names. Headerless files are supported.

- gray_matter_path:

  Path to the gray-matter probability or anatomical context NIfTI. When
  `NULL`, the MNI152NLin2009cAsym gray-matter probability map is
  downloaded to and resolved from the ggbrat cache.

- gray_matter_threshold:

  Values greater than or equal to this threshold are included in the
  context mask.

- views:

  Any ordered subset of `"axial"`, `"sagittal"`, and `"coronal"`.

- slice_coordinates:

  Named world coordinates for the requested views. Defaults to
  coordinate zero for every view.

- labels:

  Optional numeric atlas labels to include. The default includes every
  nonzero label intersecting a selected slice.

- include_gray_matter:

  Whether to include the thresholded context region.

- gray_matter_region:

  Region name assigned to the context polygons. May be `NA_character_`
  when the context should not be treated as an atlas region.

- exclude_atlas_from_gray_matter:

  Whether atlas-labelled cells should be removed from the context mask
  so the returned polygons form a nonoverlapping categorical atlas.

- smooth_iterations:

  Strength of geometric outline smoothing, expressed in voxel-width
  steps. Zero (the default) preserves exact voxel boundaries; values
  from 1 to 3 progressively round atlas-region stair-step edges.
  Fractional values are supported. Smoothing uses morphological buffers
  followed by simplification and does not repeatedly multiply the number
  of boundary vertices.

- gray_matter_smooth_iterations:

  Smoothing strength for the gray-matter context outline. By default
  this inherits `smooth_iterations`; set it separately when the cortex
  needs less smoothing than the atlas regions.

- interactive:

  If `TRUE`, open an interactive slice selector. The user can switch
  anatomical axes, scroll through slices, and save `n_views` selections
  before polygon construction begins. Requires the suggested package
  `shiny`.

- n_views:

  Number of slices to save in interactive mode.

## Value

An `sf` object with region polygons and columns `region`, `label`,
`tissue`, `axis`, `int_view`, `view`, `selection_order`, `slice_index`,
`slice_coordinate`, and `requested_coordinate`. `int_view` numbers
slices within each anatomical axis and `view` combines the axis and
number, for example `"axial_2"`. Use `ggplot2::facet_wrap(~view)` to
display views separately.

## Details

By default, the nearest voxel plane to world coordinate zero is selected
for axial, sagittal, and coronal views. The input images must currently
share the same dimensions and voxel-to-world affine transformation.

## Examples

``` r
if (FALSE) { # \dontrun{
melbourne <- download_volume_atlas("Melbourne_S1")
atlas <- build_atlas_vol(
  atlas_path = melbourne$nifti,
  lookup_path = melbourne$lookup
)

ggplot2::ggplot(atlas) +
  ggplot2::geom_sf(ggplot2::aes(fill = region), linewidth = 0.2) +
  ggplot2::facet_wrap(~view) +
  ggplot2::theme_void()
} # }
```
