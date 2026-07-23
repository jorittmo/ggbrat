# Remove resources from the ggbrat cache

Remove resources from the ggbrat cache

## Usage

``` r
remove_resource(name, type = NULL, cache_dir = ggbrat_cache_dir())
```

## Arguments

- name:

  Resource name, id, vector of names, or `"all"`.

- type:

  Optional category, required for `name = "all"`.

- cache_dir:

  Resource cache directory.

## Value

The removed paths, invisibly.
