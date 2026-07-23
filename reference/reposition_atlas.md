# Reposition atlas panels with a text-based layout

Arranges atlas panels using a compact design string. Panels are inferred
from the atlas in the order in which they first appear and assigned the
letters `A`, `B`, `C`, and so on. For a surface atlas, a panel is each
unique `view` and `hemisphere` combination. For an atlas without
multiple hemispheres, including a volumetric atlas, a panel is each
unique `view`.

## Usage

``` r
reposition_atlas(x, layout, horizontal_gap = 0.05, vertical_gap = 0.05)
```

## Arguments

- x:

  An `sf` atlas, or a list returned by
  [`build_atlas_surf()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_surf.md).

- layout:

  A single character string describing the grid. Each non-empty cell
  must be a letter assigned to one inferred panel. Newlines separate
  rows; `.`, `#`, and spaces denote empty cells.

- horizontal_gap:

  Horizontal distance between adjacent view bounding boxes, in the
  coordinate units of the atlas.

- vertical_gap:

  Vertical distance between adjacent view bounding boxes, in the
  coordinate units of the atlas.

## Value

An object of the same form as `x`, with repositioned geometries. A data
frame mapping layout letters to panel metadata is stored in the
`layout_key` attribute.

## Details

For example, `"ABCD"` places four panels in one row, while `"AB\nCD"`
creates a two-by-two grid. Use `.`, `#`, or a space for an empty cell.
Letter matching is case-insensitive.

When `x` is the list returned by
[`build_atlas_surf()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_surf.md),
the same translations are applied to the `atlas`, `shade`, `silhouette`,
`cortex`, and `cortex_silhouette` layers. Camera positions and other
non-spatial components are left unchanged.

## Examples

``` r
if (FALSE) { # \dontrun{
atlas <- load_atlas("Schaefer2018_400Parcels_7Networks_order")

# Put four panels in one row.
atlas <- reposition_atlas(atlas, layout = "ABCD")

# Put the same panels in a two-by-two grid.
atlas <- reposition_atlas(atlas, layout = "AB\nCD")

# Inspect which panel was assigned to each letter.
attr(atlas, "layout_key")
} # }
```
