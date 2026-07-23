# Smooth polygon boundaries

Smooths the geometries of an `sf` object using
[`smoothr::smooth()`](https://strimas.com/smoothr/reference/smooth.html).
Attribute columns are retained. The available methods and the
interpretation of `smoothness` are defined by `smoothr`.

## Usage

``` r
smooth_polygons(x, method = "ksmooth", smoothness = 3)
```

## Arguments

- x:

  An `sf` object containing polygon or multipolygon geometries.

- method:

  Smoothing method passed to
  [`smoothr::smooth()`](https://strimas.com/smoothr/reference/smooth.html).
  Common choices include `"ksmooth"`, `"chaikin"`, `"spline"`, and
  `"densify"`.

- smoothness:

  Smoothing parameter passed to the selected method through
  [`smoothr::smooth()`](https://strimas.com/smoothr/reference/smooth.html).

## Value

An `sf` object with smoothed geometries and the same attribute columns
as `x`.

## Examples

``` r
square <- sf::st_sf(
  region = "example",
  geometry = sf::st_sfc(sf::st_polygon(list(matrix(
    c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0), ncol = 2, byrow = TRUE
  ))))
)
smoothed <- smooth_polygons(square, method = "ksmooth", smoothness = 3)
```
