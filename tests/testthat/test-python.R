test_that("Python requirements are declared without prompting", {
  declared <- NULL
  notices <- character()
  local_mocked_bindings(
    ggbrat_python_notice_env = new.env(parent = emptyenv()),
    ggbrat_python_inform = function(message) {
      notices <<- c(notices, message)
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
  expect_length(notices, 1L)
  expect_match(notices, "isolated managed environment")
  expect_match(notices, "`numpy`, `scikit-image`")
})

test_that("Python initialization notice is shown once per subsystem", {
  notices <- character()
  local_mocked_bindings(
    ggbrat_python_notice_env = new.env(parent = emptyenv()),
    ggbrat_python_inform = function(message) {
      notices <<- c(notices, message)
    },
    ggbrat_declare_python_requirements = function(packages) invisible(),
    .package = "ggbrat"
  )

  ggbrat:::ggbrat_python_require("numpy", "Surface support")
  ggbrat:::ggbrat_python_require("numpy", "Surface support")
  ggbrat:::ggbrat_python_require("templateflow", "TemplateFlow support")

  expect_length(notices, 2L)
  expect_match(notices[[1L]], "Surface support")
  expect_match(notices[[2L]], "TemplateFlow support")
})
