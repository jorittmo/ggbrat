make_mock_resource_release <- function(root) {
  dir.create(root, recursive = TRUE)
  specs <- list(
    list(id = "atlas-one", name = "one", type = "atlas", roles = "atlas", values = list(list(value = 1))),
    list(id = "atlas-two", name = "two", type = "atlas", roles = "atlas", values = list(list(value = 2))),
    list(id = "surface-test", name = "test_surface", type = "surface", roles = c("left", "right"), values = list("left", "right")),
    list(id = "annotation-test", name = "test_annotation", type = "annotation", roles = c("left", "right"), values = list("left", "right")),
    list(id = "volume-test", name = "test_volume", type = "volume", roles = c("nifti", "lookup"), values = list("nifti", "lookup")),
    list(id = "mesh-test", name = "test_mesh", type = "mesh", roles = c("left", "right"), values = list("left", "right"))
  )
  catalog <- list()
  file_catalog <- list()

  for (spec in specs) {
    bundle <- tempfile("ggbrat-mock-bundle-")
    dir.create(file.path(bundle, "files"), recursive = TRUE)
    extensions <- if (spec$type == "atlas") ".rds" else ".dat"
    filenames <- paste0(make.unique(spec$roles), extensions)
    paths <- file.path(bundle, "files", filenames)
    for (index in seq_along(paths)) {
      if (spec$type == "atlas") saveRDS(spec$values[[index]], paths[[index]]) else writeLines(spec$values[[index]], paths[[index]])
    }
    entries <- data.frame(
      resource_id = spec$id, role = spec$roles,
      path = file.path("files", filenames), md5 = unname(tools::md5sum(paths)),
      stringsAsFactors = FALSE
    )
    write.csv(entries, file.path(bundle, "resource-files.csv"), row.names = FALSE)
    asset <- paste0(spec$id, ".tar.gz")
    old <- setwd(bundle)
    utils::tar(file.path(root, asset), c("resource-files.csv", "files"), compression = "gzip", tar = "internal")
    setwd(old)
    unlink(bundle, recursive = TRUE)

    asset_path <- file.path(root, asset)
    catalog[[length(catalog) + 1L]] <- data.frame(
      id = spec$id, name = spec$name, type = spec$type,
      resource_version = "dev", release_tag = "prerelease", asset = asset,
      url = paste0("file://", asset_path), md5 = unname(tools::md5sum(asset_path)),
      size = file.info(asset_path)$size, license = "test", source_url = "",
      description = "mock resource", stringsAsFactors = FALSE
    )
    file_catalog[[length(file_catalog) + 1L]] <- entries
  }
  write.csv(do.call(rbind, catalog), file.path(root, "resources.csv"), row.names = FALSE)
  write.csv(do.call(rbind, file_catalog), file.path(root, "resource-files.csv"), row.names = FALSE)
}

with_mock_resources <- function(code) {
  release <- tempfile("ggbrat-mock-release-")
  cache <- tempfile("ggbrat-mock-cache-")
  make_mock_resource_release(release)
  old_options <- options(
    ggbrat.resource_base_url = paste0("file://", release),
    ggbrat.cache_dir = cache
  )
  on.exit({
    options(old_options)
    unlink(c(release, cache), recursive = TRUE)
    if (exists("catalog", envir = .ggbrat_resource_state, inherits = FALSE)) {
      rm("catalog", envir = .ggbrat_resource_state)
    }
  })
  force(code)
}

test_that("resource catalog resolves ids, aliases, and all categories", {
  with_mock_resources({
    catalog <- resource_catalog(refresh = TRUE, quiet = TRUE)
    expect_equal(nrow(catalog), 6L)
    expect_equal(resource_info("test-surface", type = "surface")$id, "surface-test")
    expect_error(resource_info("all"), "type.*required")
    for (type in c("atlas", "surface", "annotation", "volume", "mesh")) {
      expect_true(nrow(resource_info("all", type = type)) >= 1L)
    }
  })
})

test_that("resource catalog resolves unique partial names", {
  with_mock_resources({
    catalog <- resource_catalog(refresh = TRUE, quiet = TRUE)
    expect_equal(
      resource_select("surfa", type = "surface", catalog = catalog)$id,
      "surface-test"
    )
    expect_equal(
      resource_select("annot", type = "annotation", catalog = catalog)$id,
      "annotation-test"
    )
  })
})

test_that("ambiguous partial names list candidates non-interactively", {
  with_mock_resources({
    catalog <- resource_catalog(refresh = TRUE, quiet = TRUE)
    error <- tryCatch(
      resource_select("atlas", type = "atlas", catalog = catalog),
      error = identity
    )
    message <- conditionMessage(error)
    expect_match(message, "Multiple ggbrat resources match")
    expect_match(message, "one [atlas; atlas-one]", fixed = TRUE)
    expect_match(message, "two [atlas; atlas-two]", fixed = TRUE)
    expect_match(message, "more specific")
  })
})

test_that("exact resource matches take priority over partial matches", {
  catalog <- data.frame(
    id = c("atlas-yeo", "atlas-yeo-expanded"),
    name = c("yeo", "yeo_expanded"),
    type = c("atlas", "atlas"),
    stringsAsFactors = FALSE
  )
  expect_equal(resource_select("yeo", "atlas", catalog)$id, "atlas-yeo")
})

test_that("resource aliases resolve common atlas names", {
  catalog <- data.frame(
    id = paste0("atlas-", c("aparc", "aparc-a2009s", "hcp-mmp1")),
    name = c("aparc", "aparc.a2009s", "HCP-MMP1"),
    type = "atlas",
    aliases = resource_aliases(c("aparc", "aparc.a2009s", "HCP-MMP1")),
    stringsAsFactors = FALSE
  )

  expect_equal(resource_select("dk", "atlas", catalog)$name, "aparc")
  expect_equal(
    resource_select("destrieux", "atlas", catalog)$name,
    "aparc.a2009s"
  )
  expect_equal(resource_select("glasser", "atlas", catalog)$name, "HCP-MMP1")
})

test_that("short aliases require an exact match", {
  catalog <- data.frame(
    id = "atlas-aparc",
    name = "aparc",
    type = "atlas",
    aliases = resource_aliases("aparc"),
    stringsAsFactors = FALSE
  )

  expect_equal(resource_select("dk", "atlas", catalog)$name, "aparc")
  expect_error(resource_select("d", "atlas", catalog), "Unknown ggbrat resource")
})

test_that("bundled resources have source citations and aliases", {
  if (exists("catalog", envir = .ggbrat_resource_state, inherits = FALSE)) {
    rm("catalog", envir = .ggbrat_resource_state)
  }
  catalog <- resource_catalog()
  expect_true("citation" %in% names(catalog))
  expect_true("aliases" %in% names(catalog))
  expect_false(anyNA(catalog$citation))
  expect_true(all(nzchar(catalog$citation)))
  expect_match(
    catalog$aliases[catalog$name == "HCP-MMP1"][1L],
    "glasser"
  )
  expect_match(
    catalog$citation[catalog$name == "Yeo2011_7Networks_N1000"][1L],
    "Yeo BTT"
  )
})

test_that("typed resource functions download and reuse validated cache files", {
  with_mock_resources({
    resource_catalog(refresh = TRUE, quiet = TRUE)
    atlas_path <- download_atlas("one", quiet = TRUE)
    expect_true(file.exists(atlas_path))
    expect_equal(load_atlas("one", quiet = TRUE)$value, 1)
    expect_equal(length(download_atlas("all", quiet = TRUE)), 2L)

    surface <- download_surface("all", type = "cortical", quiet = TRUE)
    all_surfaces <- download_surface("all", quiet = TRUE)
    annotation <- download_annotation("all", quiet = TRUE)
    volume <- download_volume_atlas("all", quiet = TRUE)
    mesh <- download_surface("all", type = "subcortical", quiet = TRUE)
    expect_named(surface, c("left", "right"))
    expect_named(all_surfaces, c("test_surface", "test_mesh"))
    expect_named(annotation, c("left", "right"))
    expect_named(volume, c("nifti", "lookup"))
    expect_named(mesh, c("left", "right"))
    expect_true(all(file.exists(c(surface, annotation, unlist(volume), mesh))))

    expect_true(all(list_resources(installed = TRUE)$installed))
    remove_resource("one", type = "atlas")
    expect_false(file.exists(atlas_path))
  })
})

test_that("resource downloads reject stale checksums", {
  with_mock_resources({
    catalog <- resource_catalog(refresh = TRUE, quiet = TRUE)
    catalog$md5[catalog$id == "atlas-one"] <- paste(rep("0", 32), collapse = "")
    attr(catalog, "files") <- attr(.ggbrat_resource_state$catalog, "files")
    .ggbrat_resource_state$catalog <- catalog
    expect_error(download_atlas("one", quiet = TRUE), "Checksum mismatch")
  })
})

test_that("generated outputs use the user-specific cache", {
  cache <- tempfile("ggbrat-generated-cache-")
  old_options <- options(ggbrat.cache_dir = cache)
  on.exit(options(old_options), add = TRUE)

  generated <- ggbrat_generated_dir("surfaces")
  expect_true(startsWith(generated, normalizePath(cache, mustWork = FALSE)))
  expect_true(dir.exists(generated))
})
