templateflow_python_env <- new.env(parent = baseenv())

templateflow_python_path <- function() {
  candidates <- c(
    system.file("python", "templateflow_client.py", package = "ggbrat"),
    file.path("inst", "python", "templateflow_client.py")
  )
  path <- candidates[file.exists(candidates)][1]
  if (is.na(path) || !nzchar(path)) {
    stop("Could not locate `templateflow_client.py`.", call. = FALSE)
  }
  path
}

templateflow_load_python <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("TemplateFlow support requires the R package `reticulate`.", call. = FALSE)
  }
  if (!exists("tf_get", envir = templateflow_python_env, inherits = FALSE)) {
    if (utils::packageVersion("reticulate") >= "1.41.0") {
      reticulate::py_require("templateflow")
    }
    tryCatch(
      reticulate::source_python(
        templateflow_python_path(), envir = templateflow_python_env
      ),
      error = function(error) {
        stop(
          "Could not initialize the optional TemplateFlow Python client. ",
          "With reticulate >= 1.41 it is provisioned automatically; otherwise ",
          "install it with `python -m pip install templateflow`.\n",
          conditionMessage(error),
          call. = FALSE
        )
      }
    )
  }
  invisible(TRUE)
}

templateflow_filters <- function(...) {
  filters <- list(...)
  filters[!vapply(filters, is.null, logical(1))]
}

#' Query resources from TemplateFlow
#'
#' Thin R wrappers around the official TemplateFlow Python client. Resources
#' are downloaded lazily into TemplateFlow's cache and returned as local paths.
#' These functions require Python only when called.
#'
#' @param template TemplateFlow template identifier, without the `tpl-` prefix.
#' @param ... BIDS-like TemplateFlow query entities such as `atlas`, `hemi`,
#'   `density`, `resolution`, `desc`, `suffix`, and `extension`.
#' @param bibtex Whether citations should be returned in BibTeX form.
#'
#' @return `templateflow_templates()` returns template identifiers;
#'   `templateflow_get()` returns local file paths; metadata and citation
#'   functions return values supplied by TemplateFlow.
#' @name templateflow
NULL

#' @rdname templateflow
#' @export
templateflow_templates <- function(...) {
  templateflow_load_python()
  as.character(do.call(
    templateflow_python_env$tf_templates,
    templateflow_filters(...)
  ))
}

#' @rdname templateflow
#' @export
templateflow_get <- function(template, ...) {
  if (!is.character(template) || length(template) != 1L || is.na(template) ||
      !nzchar(template)) {
    stop("`template` must be one non-empty TemplateFlow identifier.", call. = FALSE)
  }
  templateflow_load_python()
  paths <- do.call(
    templateflow_python_env$tf_get,
    c(list(template), templateflow_filters(...))
  )
  as.character(paths)
}

#' @rdname templateflow
#' @export
templateflow_metadata <- function(template) {
  templateflow_load_python()
  templateflow_python_env$tf_metadata(template)
}

#' @rdname templateflow
#' @export
templateflow_citations <- function(template, bibtex = FALSE) {
  if (!is.logical(bibtex) || length(bibtex) != 1L || is.na(bibtex)) {
    stop("`bibtex` must be TRUE or FALSE.", call. = FALSE)
  }
  templateflow_load_python()
  templateflow_python_env$tf_citations(template, bibtex = bibtex)
}
