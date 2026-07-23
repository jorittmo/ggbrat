# Download cortical or subcortical surface resources

Download cortical or subcortical surface resources

## Usage

``` r
download_surface(
  name,
  type = c("auto", "cortical", "subcortical"),
  force = FALSE,
  refresh = FALSE,
  cache_dir = ggbrat_cache_dir(),
  quiet = FALSE
)
```

## Arguments

- name:

  Resource name, id, vector of names, or `"all"`.

- type:

  Surface category to resolve: `"auto"` searches both cortical surfaces
  and subcortical meshes, `"cortical"` searches FreeSurfer-style
  surfaces, and `"subcortical"` searches generated meshes.

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

Named surface paths, or a named list for multiple resources.
