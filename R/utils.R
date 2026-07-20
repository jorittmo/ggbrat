shrink_polygons <- function(x, dist) {
  stopifnot(inherits(x, "sf"))

  x |>
    st_make_valid() |>
    st_buffer(dist = -abs(distance))
}


smooth_polygons <- function(x, method = "ksmooth", smoothness = 3) {
  require(smoothr)
  smooth(x, method = method, smoothness = smoothness)
}
