# List downloadable ggbrat resources

List downloadable ggbrat resources

## Usage

``` r
list_resources(
  type = NULL,
  installed = NULL,
  refresh = FALSE,
  cache_dir = ggbrat_cache_dir()
)
```

## Arguments

- type:

  Optional resource category: `"atlas"`, `"surface"`, `"annotation"`,
  `"volume"`, or `"mesh"`.

- installed:

  Optionally restrict output to installed (`TRUE`) or missing (`FALSE`)
  resources.

- refresh:

  Whether to refresh the mutable remote catalog.

- cache_dir:

  Resource cache directory.

## Value

A resource catalog data frame. The `citation` column gives the
recommended source citation for each resource.
