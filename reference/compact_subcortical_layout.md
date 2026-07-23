# Compact a subcortical atlas layout

Repositions complete hemisphere/view groups according to their
subcortical bounding boxes. Parcel shapes and their relative positions
within each group are unchanged. This is useful when the cortex is
omitted and cortex-sized grid spacing leaves excessive empty space
between subcortical structures.

## Usage

``` r
compact_subcortical_layout(
  x,
  horizontal_gap = 0.05,
  vertical_gap = 0.05,
  drop_cortex = TRUE
)
```

## Arguments

- x:

  An `sf` atlas or a list returned by
  [`build_atlas_surf()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_surf.md).

- horizontal_gap:

  Horizontal gap between hemisphere groups.

- vertical_gap:

  Vertical gap between view rows.

- drop_cortex:

  When `TRUE`, remove `cortex` and `cortex_silhouette` from list inputs
  because the compact layout is intended for cortex-free plots.

## Value

An object of the same form as `x`, with compactly shifted geometry.
