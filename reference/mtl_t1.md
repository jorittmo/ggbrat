# Medial temporal lobe atlas for T1-weighted anatomy drawn by Anika Wuestefeld

A two-dimensional medial temporal lobe atlas imported from a labelled
SVG drawing. The atlas represents entorhinal and perirhinal cortical
regions, the parahippocampal cortex, and anterior and posterior
divisions of the hippocampus.

## Usage

``` r
mtl_t1
```

## Format

An `sf` object with 6 rows and 2 columns:

- region:

  Character anatomical region label. Labels are `"ERC"` (entorhinal
  cortex), `"BA35"` and `"BA36"` (Brodmann areas 35 and 36),
  `"anteriorHC"` and `"posteriorHC"` (anterior and posterior
  hippocampus), and `"PHC"` (parahippocampal cortex).

- geometry:

  Simple-feature polygon geometry in the coordinate system of the source
  SVG drawing. The atlas has no coordinate reference system.

## Source

SVG drawing by Anika Wuestefeld.

## Details

This is a schematic plotting atlas, not a spatially registered
neuroimaging atlas. It was created from a labelled SVG drawing with
[`build_atlas_svg()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_svg.md).

## Examples

``` r
data(mtl_t1)
plot(sf::st_geometry(mtl_t1))

```
