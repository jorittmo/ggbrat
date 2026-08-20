#' Five cortical connectivity gradients for the Schaefer 1000 atlas
#'
#' Parcel-level values for the first five cortical connectivity gradients from
#' Margulies et al. (2016), represented for the 1,000 parcels of the Schaefer
#' 2018 atlas using its seven-network region names. Each row corresponds to one
#' Schaefer parcel.
#'
#' @format A tibble with 1,000 rows and 6 columns:
#' \describe{
#'   \item{gradient1}{Numeric score on the first connectivity gradient.}
#'   \item{gradient2}{Numeric score on the second connectivity gradient.}
#'   \item{gradient3}{Numeric score on the third connectivity gradient.}
#'   \item{gradient4}{Numeric score on the fourth connectivity gradient.}
#'   \item{gradient5}{Numeric score on the fifth connectivity gradient.}
#'   \item{region}{Character Schaefer-1000 parcel name using the seven-network
#'     naming scheme.}
#' }
#'
#' @details The data are stored in `data/gradients.rda`; the R object loaded by
#'   [data()] is named `grads`. Gradient direction is sign-indeterminate in the
#'   underlying decomposition, so interpretation should focus on relative
#'   positions along a gradient unless orientation has been explicitly checked
#'   against the source representation.
#'
#' @source Margulies, D. S., Ghosh, S. S., Goulas, A., et al. (2016).
#'   Situating the default-mode network along a principal gradient of macroscale
#'   cortical organization. *Proceedings of the National Academy of Sciences*,
#'   113(44), 12574-12579. \doi{10.1073/pnas.1608282113}
#'
#' @examples
#' data(grads)
#' head(grads)
#'
#' @keywords datasets
"grads"

#' Medial temporal lobe atlas for T1-weighted anatomy drawn by Anika Wuestefeld
#'
#' A two-dimensional medial temporal lobe atlas imported from a labelled SVG
#' drawing. The atlas represents entorhinal and perirhinal cortical regions,
#' the parahippocampal cortex, and anterior and posterior divisions of the
#' hippocampus.
#'
#' @format An `sf` object with 6 rows and 2 columns:
#' \describe{
#'   \item{region}{Character anatomical region label. Labels are `"ERC"`
#'     (entorhinal cortex), `"BA35"` and `"BA36"` (Brodmann areas 35 and 36),
#'     `"anteriorHC"` and `"posteriorHC"` (anterior and posterior
#'     hippocampus), and `"PHC"` (parahippocampal cortex).}
#'   \item{geometry}{Simple-feature polygon geometry in the coordinate system
#'     of the source SVG drawing. The atlas has no coordinate reference
#'     system.}
#' }
#'
#' @details This is a schematic plotting atlas, not a spatially registered
#'   neuroimaging atlas. It was created from a labelled SVG drawing with
#'   [build_atlas_svg()].
#'
#' @source SVG drawing by Anika Wuestefeld.
#'
#' @examples
#' data(mtl_t1)
#' plot(mtl_t1["region"])
#'
#' @keywords datasets
"mtl_t1"

#' Medial temporal lobe atlas for T2-weighted anatomy Anika Wuestefeld
#'
#' A two-dimensional medial temporal lobe atlas imported from a labelled SVG
#' drawing. The atlas represents medial temporal cortical regions and
#' hippocampal subfields.
#'
#' @format An `sf` object with 9 rows and 2 columns:
#' \describe{
#'   \item{region}{Character anatomical region label. Labels are `"ERC"`
#'     (entorhinal cortex), `"BA35"` and `"BA36"` (Brodmann areas 35 and 36),
#'     `"SUB"` (subiculum), `"CA1"`, `"CA2"`, and `"CA3"` (cornu ammonis
#'     subfields), `"PHC"` (parahippocampal cortex), and `"CA3-2"` (the
#'     second disconnected CA3 component in the drawing).}
#'   \item{geometry}{Simple-feature polygon or multipolygon geometry in the
#'     coordinate system of the source SVG drawing. The atlas has no
#'     coordinate reference system.}
#' }
#'
#' @details This is a schematic plotting atlas, not a spatially registered
#'   neuroimaging atlas. It was created from a labelled SVG drawing with
#'   [build_atlas_svg()].
#'
#' @source SVG drawing by Anika Wuestefeld.
#'
#' @examples
#' data(mtl_t2)
#' plot(mtl_t2["region"])
#'
#' @keywords datasets
"mtl_t2"
