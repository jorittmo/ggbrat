# Show metadata for a ggbrat resource

Show metadata for a ggbrat resource

## Usage

``` r
resource_info(name, type = NULL, refresh = FALSE)
```

## Arguments

- name:

  Resource name, id, alias, partial name, vector of names, or `"all"`.
  Exact normalized names and ids take priority, followed by exact
  aliases. A unique partial match is selected automatically; multiple
  matches open a selection menu in interactive R and produce an
  informative error otherwise.

- type:

  Optional resource category.

- refresh:

  Whether to refresh the mutable remote catalog.

## Value

Matching catalog rows.
