# Convert a point cloud to polygonal geometry using an alpha hull

Convert a point cloud to polygonal geometry using an alpha hull

## Usage

``` r
ashape_polygon_sf(pts, alpha = "auto", smoothing_factor = 3)
```

## Arguments

- pts:

  Point geometry.

- alpha:

  Alpha radius or `"auto"`.

- smoothing_factor:

  Scaling applied when `alpha = "auto"`.

## Value

An `sfc` geometry vector.
