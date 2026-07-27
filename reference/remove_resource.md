# Remove resources from the ggbrat cache

Remove resources from the ggbrat cache

## Usage

``` r
remove_resource(name, type = NULL, cache_dir = ggbrat_cache_dir())
```

## Arguments

- name:

  Resource name, id, alias, partial name, vector of names, or `"all"`.
  Exact normalized names and ids take priority, followed by exact
  aliases. A unique partial match is selected automatically; multiple
  matches open a selection menu in interactive R and produce an
  informative error otherwise.

- type:

  Optional category, required for `name = "all"`.

- cache_dir:

  Resource cache directory.

## Value

The removed paths, invisibly.
