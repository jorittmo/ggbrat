# Build an sf atlas from labelled SVG layers

`build_atlas_svg()` reads SVG groups containing paths, samples their
line and Bezier geometry, and creates one polygon per labelled region.
Exact closed paths are preserved; hull reconstruction remains available
for legacy SVGs whose paths represent converted strokes rather than
regions.

## Usage

``` r
build_atlas_svg(
  svg_path,
  curve_steps = 20L,
  geometry_method = c("auto", "path", "concaveman"),
  concavity = 0,
  length_threshold = 2.5,
  flip_y = TRUE,
  combine_regions = TRUE
)
```

## Arguments

- svg_path:

  Path to an SVG file.

- curve_steps:

  Number of straight segments used to approximate each Bezier curve.

- geometry_method:

  Geometry construction method. `"path"` preserves the authored
  boundary, `"concaveman"` reconstructs a boundary from sampled points,
  and `"auto"` uses exact paths for labelled region drawings and
  concaveman for legacy ID-only drawings.

- concavity:

  Concaveman concavity parameter. Smaller values produce a more detailed
  boundary; `Inf` produces a convex hull.

- length_threshold:

  Concaveman segment-length threshold. Segments shorter than this value
  are not refined further.

- flip_y:

  Whether to convert SVG's downward-positive Y coordinates to
  conventional Cartesian coordinates.

- combine_regions:

  Whether groups with the same region name should be combined into a
  single (possibly multipart) feature.

## Value

An `sf` object with `region` and `geometry` columns.

## Authoring SVG atlas templates

New templates should encode the anatomical boundaries directly instead
of relying on hull reconstruction:

1.  Create one SVG group/layer for each anatomical region.

2.  Draw the region as a **closed, filled path**. Either the Bezier tool
    or a freehand tool is suitable, provided the final object is an
    ordinary closed path. The fill represents the region; a stroke is
    optional styling around its boundary.

3.  Give the region a stable, unique name. Names are resolved from
    `data-name`, a meaningful Inkscape layer label, a path `<title>`,
    and finally the group `id`. Generic labels such as `Layer 2` are
    ignored when a path title is available.

4.  Keep each path as a direct child of its region layer. A layer may
    contain multiple closed paths for a disconnected region.
    Alternatively, repeated layers can use the same region name;
    `combine_regions = TRUE` combines them into one multipart feature.

5.  Do not convert strokes to paths. That creates a thin compound
    outline rather than an anatomical polygon and requires
    reconstruction.

6.  Convert live path effects and shape objects to ordinary paths before
    the final export. Avoid clipping masks, clones, text, embedded
    raster images, and nested decorative groups in atlas layers.

7.  Save as plain or standard SVG. Line, cubic and quadratic Bezier path
    commands are supported. Convert elliptical arcs to Bezier curves.
    The importer supports `translate`, `scale`, `rotate`, and matrix
    transforms.

Import new templates with `geometry_method = "path"`. The `"auto"`
method treats a path `<title>` as an exact-region marker; ID-only legacy
drawings are reconstructed with concaveman. Since concaveman is an
optional suggested dependency, install it only when legacy
reconstruction is needed with `install.packages("concaveman")`.

SVG coordinates have a downward-positive Y axis. `flip_y = TRUE`
converts them to the conventional Cartesian orientation used by `sf` and
ggplot2.

## Examples

``` r
if (FALSE) { # \dontrun{
# Select an SVG whose labelled groups contain the atlas regions.
atlas <- build_atlas_svg(
  svg_path = file.choose(),
  geometry_method = "path"
)

# Only for legacy drawings whose paths are converted stroke outlines:
legacy_atlas <- build_atlas_svg(
  svg_path = file.choose(),
  geometry_method = "concaveman",
  concavity = 0,
  length_threshold = 2.5
)
} # }
```
