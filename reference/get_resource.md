# Download one or more ggbrat resources

Download one or more ggbrat resources

## Usage

``` r
get_resource(
  name,
  type = NULL,
  force = FALSE,
  refresh = FALSE,
  cache_dir = ggbrat_cache_dir(),
  quiet = FALSE
)
```

## Arguments

- name:

  Resource name, id, alias, partial name, vector of names, or `"all"`.
  Exact normalized names and ids take priority, followed by exact
  aliases. A unique partial match is selected automatically; multiple
  matches open a selection menu in interactive R and produce an
  informative error otherwise.

- type:

  Optional resource category. Required for `name = "all"`.

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

A `ggbrat_resource` object, or a named list for multiple resources.
