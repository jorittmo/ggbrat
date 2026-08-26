test_that("Python requirements need explicit consent in non-interactive sessions", {
  old_options <- options(ggbrat.python_install = NULL)
  on.exit(options(old_options), add = TRUE)
  local_mocked_bindings(
    ggbrat_python_is_interactive = function() FALSE,
    ggbrat_declare_python_requirements = function(packages) {
      fail("Python requirements should not be declared without consent")
    },
    .package = "ggbrat"
  )

  expect_error(
    ggbrat:::ggbrat_python_require(c("numpy", "vtk"), "Test feature"),
    "will not install them automatically in a non-interactive session"
  )
})

test_that("interactive consent controls Python requirement declaration", {
  declared <- NULL
  prompt <- NULL
  old_options <- options(ggbrat.python_install = NULL)
  on.exit(options(old_options), add = TRUE)
  local_mocked_bindings(
    ggbrat_python_is_interactive = function() TRUE,
    ggbrat_python_ask_yes_no = function(message) {
      prompt <<- message
      TRUE
    },
    ggbrat_declare_python_requirements = function(packages) {
      declared <<- packages
    },
    .package = "ggbrat"
  )

  expect_true(ggbrat:::ggbrat_python_require(
    c("numpy", "scikit-image"), "Test feature"
  ))
  expect_equal(declared, c("numpy", "scikit-image"))
  expect_match(prompt, "Allow reticulate to download and install them if needed")
  expect_match(prompt, "`numpy`, `scikit-image`")
})

test_that("declining interactive Python installation stops the feature", {
  old_options <- options(ggbrat.python_install = NULL)
  on.exit(options(old_options), add = TRUE)
  local_mocked_bindings(
    ggbrat_python_is_interactive = function() TRUE,
    ggbrat_python_ask_yes_no = function(message) FALSE,
    ggbrat_declare_python_requirements = function(packages) {
      fail("Python requirements should not be declared after refusal")
    },
    .package = "ggbrat"
  )

  expect_error(
    ggbrat:::ggbrat_python_require("numpy", "Test feature"),
    "installation was not authorized"
  )
})

test_that("the Python install option supports explicit automation", {
  declared <- NULL
  old_options <- options(ggbrat.python_install = TRUE)
  on.exit(options(old_options), add = TRUE)
  local_mocked_bindings(
    ggbrat_python_is_interactive = function() {
      fail("Explicit consent should bypass interactive detection")
    },
    ggbrat_declare_python_requirements = function(packages) {
      declared <<- packages
    },
    .package = "ggbrat"
  )

  expect_true(ggbrat:::ggbrat_python_require("numpy", "Test feature"))
  expect_equal(declared, "numpy")

  options(ggbrat.python_install = FALSE)
  expect_error(
    ggbrat:::ggbrat_python_require("numpy", "Test feature"),
    "installation was not authorized"
  )
})

test_that("the Python install option is validated", {
  old_options <- options(ggbrat.python_install = "yes")
  on.exit(options(old_options), add = TRUE)
  expect_error(
    ggbrat:::ggbrat_python_require("numpy", "Test feature"),
    "must be TRUE, FALSE, or unset"
  )
})
