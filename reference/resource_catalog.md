# Inspect the ggbrat resource catalog

The package ships with a catalog snapshot. Set `refresh = TRUE` to read
the current catalog from the mutable resources prerelease.

## Usage

``` r
resource_catalog(refresh = FALSE, quiet = FALSE)
```

## Arguments

- refresh:

  Whether to download the current remote catalog.

- quiet:

  Whether to suppress download progress.

## Value

A data frame containing one row per resource, including its recommended
source `citation`. The associated file table is stored in the `files`
attribute.
