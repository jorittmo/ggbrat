# Resources and caching

``` r

library(ggbrat)
```

## Why are resources downloaded separately?

R packages are not allowed to be very large, so ggbrat ships with only a
few example datasets. Premade atlases, annotations, surfaces, meshes,
and NIfTI files are downloaded on demand and then cached locally, ready
to be used again whenever you need them.

The package includes a catalog describing the available resources:

``` r

list_resources()
list_resources(type = "atlas")
```

> \[!NOTE\] All of the resources provided by ggbrat are available
> online, and their provenance, license and correct citation will be
> included. This is however work still being done.

Use
[`resource_info()`](https://jorittmo.github.io/ggbrat/reference/resource_info.md)
when you want metadata for a particular item:

``` r

resource_info("Melbourne_S1")
```

## Premade atlases

[`download_atlas()`](https://jorittmo.github.io/ggbrat/reference/download_atlas.md)
returns the path to a cached RDS file.
[`load_atlas()`](https://jorittmo.github.io/ggbrat/reference/load_atlas.md)
reads the atlas directly (and downloads if necessary):

``` r

atlas_path <- download_atlas("Yeo2011_7Networks_N1000")
yeo <- load_atlas("Yeo2011_7Networks_N1000")
```

## Builder resources

Different builder workflows need different source files:

``` r

annotation <- download_annotation("aparc")
cortical_surface <- download_surface("fsaverage_inflated")
subcortical_mesh <- download_surface("Melbourne_S1")
volume <- download_volume_atlas("Melbourne_S1")
```

[`download_annotation()`](https://jorittmo.github.io/ggbrat/reference/download_annotation.md)
and cortical
[`download_surface()`](https://jorittmo.github.io/ggbrat/reference/download_surface.md)
calls generally return named left/right paths. A volume resource
contains its NIfTI path or paths and, where available, a lookup table.

Use `"all"` to download a complete category:

``` r

download_annotation("all")
download_atlas("all")
```

## Cache location

Inspect the cache location with:

``` r

ggbrat_cache_dir()
```

Set a different location before downloading:

``` r

options(ggbrat.cache_dir = "/path/to/another/cache")
```

Individual resources can be removed with
[`remove_resource()`](https://jorittmo.github.io/ggbrat/reference/remove_resource.md).
To remove the complete ggbrat resource cache, use
[`clear_resource_cache()`](https://jorittmo.github.io/ggbrat/reference/clear_resource_cache.md):

``` r

remove_resource("aparc", type = "annotation")
clear_resource_cache()
```

The prerelease catalog is mutable. If a resource has been replaced
upstream, refresh the catalog and force a fresh download:

``` r

atlas <- load_atlas(
  "Schaefer2018_1000Parcels_7Networks_order",
  refresh = TRUE,
  force = TRUE
)
```
