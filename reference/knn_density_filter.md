# Filter points by local kNN density

Filter points by local kNN density

## Usage

``` r
knn_density_filter(X, k = 10, keep_quantile = 0.5, dim = 2)
```

## Arguments

- X:

  Coordinate matrix.

- k:

  Number of nearest neighbours.

- keep_quantile:

  Quantile of dense points to keep.

- dim:

  Point dimensionality.

## Value

A list with filtered points and density diagnostics.
