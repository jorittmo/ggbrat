ggbrat_python_is_interactive <- function() {
  interactive()
}

ggbrat_python_ask_yes_no <- function(message) {
  utils::askYesNo(message, default = FALSE)
}

ggbrat_declare_python_requirements <- function(packages) {
  reticulate::py_require(packages)
}

ggbrat_python_require <- function(packages, feature) {
  consent <- getOption("ggbrat.python_install", NULL)

  if (!is.null(consent) &&
      (!is.logical(consent) || length(consent) != 1L || is.na(consent))) {
    stop(
      "Option `ggbrat.python_install` must be TRUE, FALSE, or unset.",
      call. = FALSE
    )
  }

  package_list <- paste0("`", packages, "`", collapse = ", ")
  if (is.null(consent)) {
    if (!ggbrat_python_is_interactive()) {
      stop(
        feature, " requires the Python packages ", package_list, ". ",
        "ggbrat will not install them automatically in a non-interactive ",
        "session. To allow reticulate to provision them, set ",
        "`options(ggbrat.python_install = TRUE)` before calling this function.",
        call. = FALSE
      )
    }

    consent <- ggbrat_python_ask_yes_no(paste0(
      feature, " requires the Python packages ", package_list, ".\n",
      "Allow reticulate to download and install them if needed?"
    ))
  }

  if (!isTRUE(consent)) {
    stop(
      "Python package installation was not authorized; ", feature,
      " cannot continue.",
      call. = FALSE
    )
  }

  ggbrat_declare_python_requirements(packages)
  invisible(TRUE)
}
