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
