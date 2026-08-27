ggbrat_python_notice_env <- new.env(parent = emptyenv())

ggbrat_python_inform <- function(message) {
  message(message)
}

ggbrat_declare_python_requirements <- function(packages) {
  reticulate::py_require(packages)
}

ggbrat_python_require <- function(packages, feature) {
  if (!exists(feature, envir = ggbrat_python_notice_env, inherits = FALSE)) {
    package_list <- paste0("`", packages, "`", collapse = ", ")
    ggbrat_python_inform(paste0(
      "Initializing Python support for ", feature, ".\n",
      "If the required packages are not already available, reticulate may ",
      "create or reuse an isolated managed environment and download ",
      package_list, ". First use may take several minutes."
    ))
    assign(feature, TRUE, envir = ggbrat_python_notice_env)
  }

  ggbrat_declare_python_requirements(packages)
  invisible(TRUE)
}
