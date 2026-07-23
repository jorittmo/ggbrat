# Five cortical connectivity gradients for the Schaefer 1000 atlas

Parcel-level values for the first five cortical connectivity gradients
from Margulies et al. (2016), represented for the 1,000 parcels of the
Schaefer 2018 atlas using its seven-network region names. Each row
corresponds to one Schaefer parcel.

## Usage

``` r
grads
```

## Format

A tibble with 1,000 rows and 6 columns:

- gradient1:

  Numeric score on the first connectivity gradient.

- gradient2:

  Numeric score on the second connectivity gradient.

- gradient3:

  Numeric score on the third connectivity gradient.

- gradient4:

  Numeric score on the fourth connectivity gradient.

- gradient5:

  Numeric score on the fifth connectivity gradient.

- region:

  Character Schaefer-1000 parcel name using the seven-network naming
  scheme.

## Source

Margulies, D. S., Ghosh, S. S., Goulas, A., et al. (2016). Situating the
default-mode network along a principal gradient of macroscale cortical
organization. *Proceedings of the National Academy of Sciences*,
113(44), 12574-12579.
[doi:10.1073/pnas.1608282113](https://doi.org/10.1073/pnas.1608282113)

## Details

The data are stored in `data/gradients.rda`; the R object loaded by
[`data()`](https://rdrr.io/r/utils/data.html) is named `grads`. Gradient
direction is sign-indeterminate in the underlying decomposition, so
interpretation should focus on relative positions along a gradient
unless orientation has been explicitly checked against the source
representation.

## Examples

``` r
data(grads)
#> Warning: data set ‘grads’ not found
head(grads)
#> # A tibble: 6 × 6
#>   gradient1 gradient2 gradient3 gradient4 gradient5 region            
#>       <dbl>     <dbl>     <dbl>     <dbl>     <dbl> <chr>             
#> 1    -0.392      1.24    -0.433   -0.311     0.262  7Networks_LH_Vis_1
#> 2    -1.73       2.44    -0.573   -0.162     0.0110 7Networks_LH_Vis_2
#> 3    -0.848      2.06    -0.476   -0.194     0.0583 7Networks_LH_Vis_3
#> 4    -1.91       2.51    -0.502    0.0512   -0.221  7Networks_LH_Vis_4
#> 5    -0.187      1.25    -0.291   -0.173     0.145  7Networks_LH_Vis_5
#> 6    -1.85       2.46    -0.543    0.0296   -0.174  7Networks_LH_Vis_6
```
