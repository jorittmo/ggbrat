# Scale an entire atlas

Scales all atlas coordinates around the centre of the main atlas
bounding box. The complete layout, including the distances between
views, is scaled as one object. This is useful when cortical and
subcortical atlases need to be displayed at comparable sizes in the same
figure.

## Usage

``` r
atlas_size(atlas, factor = 1)
```

## Arguments

- atlas:

  An `sf` atlas or a list containing an `sf` component named `atlas`.

- factor:

  A positive numeric scale factor. Values greater than one enlarge the
  atlas and values between zero and one shrink it.

## Value

An object of the same form as `atlas`, with scaled geometries.

## Details

When `atlas` is a list, the same transformation is applied to every `sf`
component, including atlas polygons, shading, silhouettes, and
glass-cortex layers. Non-spatial components are left unchanged. For
geometries containing Z or M coordinates, only X and Y are scaled.

## Examples

``` r
if (FALSE) { # \dontrun{
cortical <- load_atlas("Schaefer2018_400Parcels_7Networks_order")
subcortical <- load_atlas("Melbourne_S1")

subcortical <- atlas_size(subcortical, factor = 1.4)
} # }
```
