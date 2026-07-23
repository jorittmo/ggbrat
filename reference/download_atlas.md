# Download premade ggbrat atlases

Download premade ggbrat atlases

## Usage

``` r
download_atlas(
  name,
  force = FALSE,
  refresh = FALSE,
  cache_dir = ggbrat_cache_dir(),
  quiet = FALSE
)
```

## Arguments

- name:

  Resource name, id, vector of names, or `"all"`.

- force:

  Whether to replace valid cached copies.

- refresh:

  Whether to refresh the mutable remote catalog before resolving and
  downloading resources. Use this together with `force = TRUE` after
  prerelease assets have been replaced.

- cache_dir:

  Resource cache directory.

- quiet:

  Whether to suppress download progress.

## Value

One cached RDS path, or a named vector of paths.
