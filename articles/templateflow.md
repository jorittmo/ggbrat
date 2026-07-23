# Using TemplateFlow

``` r

library(ggbrat)
```

ggbrat provides a thin R interface to the official TemplateFlow Python
client. TemplateFlow resolves and caches source files; these can then be
passed to
[`build_atlas_surf()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_surf.md)
just like local FreeSurfer or GIFTI files.

## Inspect TemplateFlow

``` r

templateflow_templates()
templateflow_metadata("fsaverage")
```

## Query files

[`templateflow_get()`](https://jorittmo.github.io/ggbrat/reference/templateflow.md)
accepts TemplateFlow’s BIDS-like entities:

``` r

left_pial <- templateflow_get(
  "fsaverage",
  hemi = "L",
  density = "164k",
  suffix = "pial",
  extension = ".surf.gii"
)

right_pial <- templateflow_get(
  "fsaverage",
  hemi = "R",
  density = "164k",
  suffix = "pial",
  extension = ".surf.gii"
)
```

Query the left and right label files separately in the same way, adding
`atlas`, `density`, `desc`, `suffix`, or `extension` as needed to
identify one file. A broad query may validly return several paths;
inspect those results and refine the filters instead of relying on their
order.

## Build with the returned paths

``` r

surfaces <- c(left = left_pial, right = right_pial)
labels <- c(left = left_labels, right = right_labels)

atlas <- build_atlas_surf(
  surface_path = surfaces,
  annot_path = labels,
  interactive = TRUE,
  n_views = 2,
  view_names = c("lateral", "medial")
)
```

To blend two available geometries, query each one separately and pass
two paths per hemisphere:

``` r

surface_pair <- list(
  left = c(left_surface_1, left_surface_2),
  right = c(right_surface_1, right_surface_2)
)

atlas <- build_atlas_surf(
  surface_path = surface_pair,
  annot_path = labels,
  surf_blend_ratio = 0.7,
  n_views = 2
)
```

TemplateFlow does not necessarily distribute every useful FreeSurfer
surface. For files that are not available there, use
[`download_surface()`](https://jorittmo.github.io/ggbrat/reference/download_surface.md)
or your own local paths;
[`build_atlas_surf()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_surf.md)
accepts them through the same interface.
