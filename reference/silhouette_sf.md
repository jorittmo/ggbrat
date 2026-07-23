# Convert silhouette segments into merged sf lines

Convert silhouette segments into merged sf lines

Backward-compatible alias for the earlier misspelled helper

## Usage

``` r
silhouette_sf(
  sil,
  min_length = "auto",
  simplify_tolerance = "auto",
  window_size = c(800L, 600L)
)

silhoutte_sf(
  sil,
  min_length = "auto",
  simplify_tolerance = "auto",
  window_size = c(800L, 600L)
)
```

## Arguments

- sil:

  Data frame with columns `x0`, `y0`, `x1`, `y1`.

- min_length:

  Minimum retained path length, or `"auto"` for one pixel.

- simplify_tolerance:

  Simplification tolerance, or `"auto"` for half a pixel.

- window_size:

  Render window dimensions used by automatic thresholds.

## Value

An `sf` object.
