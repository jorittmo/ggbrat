# Shift atlas views into a plotting grid

Shift atlas views into a plotting grid

## Usage

``` r
shift_brain_views(sf_obj, cell_dx = 1.5, cell_dy = -1, n_cols = 2)
```

## Arguments

- sf_obj:

  An `sf` object with `hemisphere` and `view` columns, or the raw list
  returned by
  [`brain_views()`](https://jorittmo.github.io/ggbrat/reference/brain_views.md).

- cell_dx:

  Horizontal spacing between cells.

- cell_dy:

  Vertical spacing between cells.

- n_cols:

  Number of columns in the output grid.

## Value

An `sf` object with shifted geometry, or a raw atlas list with shifted
`atlas` and optional shifted `silhouette`.
