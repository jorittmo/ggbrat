# Medial temporal lobe atlas for T2-weighted anatomy Anika Wuestefeld

A two-dimensional medial temporal lobe atlas imported from a labelled
SVG drawing. The atlas represents medial temporal cortical regions and
hippocampal subfields.

## Usage

``` r
mtl_t2
```

## Format

An `sf` object with 9 rows and 2 columns:

- region:

  Character anatomical region label. Labels are `"ERC"` (entorhinal
  cortex), `"BA35"` and `"BA36"` (Brodmann areas 35 and 36), `"SUB"`
  (subiculum), `"CA1"`, `"CA2"`, and `"CA3"` (cornu ammonis subfields),
  `"PHC"` (parahippocampal cortex), and `"CA3-2"` (the second
  disconnected CA3 component in the drawing).

- geometry:

  Simple-feature polygon or multipolygon geometry in the coordinate
  system of the source SVG drawing. The atlas has no coordinate
  reference system.

## Source

SVG drawing by Anika Wuestefeld.

## Details

This is a schematic plotting atlas, not a spatially registered
neuroimaging atlas. It was created from a labelled SVG drawing with
[`build_atlas_svg()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_svg.md).

## Examples

``` r
data(mtl_t2)
plot(sf::st_geometry(mtl_t2))

```
