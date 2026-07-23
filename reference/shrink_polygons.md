# Shrink polygon geometries

Applies a negative buffer to an `sf` object after repairing invalid
geometries. This is useful for creating a small visual gap between
adjacent atlas regions. Features may become empty when `dist` is large
relative to the polygon.

## Usage

``` r
shrink_polygons(x, dist = 0.005)
```

## Arguments

- x:

  An `sf` object containing polygon or multipolygon geometries.

- dist:

  Non-negative buffer distance used to shrink each polygon. The value is
  interpreted in the coordinate units of `x`; its absolute value is
  used.

## Value

An `sf` object with inward-buffered geometries and the same attribute
columns as `x`.

## Examples

``` r
square <- sf::st_sf(
  region = "example",
  geometry = sf::st_sfc(sf::st_polygon(list(matrix(
    c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE
  ))))
)
smaller <- shrink_polygons(square, dist = 0.05)
```
