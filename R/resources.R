.ggbrat_resource_state <- new.env(parent = emptyenv())

resource_normalize_name <- function(x) {
  tolower(gsub("[^A-Za-z0-9]+", "", x))
}

resource_catalog_paths <- function() {
  candidates <- c(
    system.file("extdata", "resources.csv", package = "ggbrat"),
    file.path("inst", "extdata", "resources.csv")
  )
  resource_path <- candidates[file.exists(candidates)][1L]
  file_path <- sub("resources\\.csv$", "resource-files.csv", resource_path)
  if (is.na(resource_path) || !nzchar(resource_path) || !file.exists(file_path)) {
    stop("The bundled ggbrat resource catalog is unavailable.", call. = FALSE)
  }
  c(resources = resource_path, files = file_path)
}

resource_remote_urls <- function() {
  repository <- getOption("ggbrat.resource_repository", "jorittmo/ggbrat-resources")
  release <- getOption("ggbrat.resource_release", "prerelease")
  base <- getOption(
    "ggbrat.resource_base_url",
    paste0("https://github.com/", repository, "/releases/download/", release)
  )
  base <- sub("/+$", "", base)
  c(
    resources = paste0(base, "/resources.csv"),
    files = paste0(base, "/resource-files.csv")
  )
}

resource_read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Inspect the ggbrat resource catalog
#'
#' The package ships with a catalog snapshot. Set `refresh = TRUE` to read the
#' current catalog from the mutable resources prerelease.
#'
#' @param refresh Whether to download the current remote catalog.
#' @param quiet Whether to suppress download progress.
#'
#' @return A data frame containing one row per resource. The associated file
#'   table is stored in the `files` attribute.
#' @export
resource_catalog <- function(refresh = FALSE, quiet = FALSE) {
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) {
    stop("`refresh` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!refresh && exists("catalog", envir = .ggbrat_resource_state, inherits = FALSE)) {
    return(.ggbrat_resource_state$catalog)
  }

  if (refresh) {
    urls <- resource_remote_urls()
    temporary <- tempfile(c("ggbrat-resources-", "ggbrat-resource-files-"), fileext = ".csv")
    on.exit(unlink(temporary), add = TRUE)
    for (index in seq_along(urls)) {
      status <- tryCatch(
        utils::download.file(urls[[index]], temporary[[index]], mode = "wb", quiet = quiet),
        error = function(error) error
      )
      if (inherits(status, "error") || !identical(status, 0L)) {
        stop("Could not download the resource catalog from ", urls[[index]], ".", call. = FALSE)
      }
    }
    catalog <- resource_read_csv(temporary[[1L]])
    files <- resource_read_csv(temporary[[2L]])
  } else {
    paths <- resource_catalog_paths()
    catalog <- resource_read_csv(paths[["resources"]])
    files <- resource_read_csv(paths[["files"]])
  }

  required <- c("id", "name", "type", "release_tag", "asset", "url", "md5")
  if (!all(required %in% names(catalog)) ||
      !all(c("resource_id", "role", "path", "md5") %in% names(files))) {
    stop("The ggbrat resource catalog has an invalid schema.", call. = FALSE)
  }
  attr(catalog, "files") <- files
  .ggbrat_resource_state$catalog <- catalog
  catalog
}

#' List downloadable ggbrat resources
#'
#' @param type Optional resource category: `"atlas"`, `"surface"`,
#'   `"annotation"`, `"volume"`, or `"mesh"`.
#' @param installed Optionally restrict output to installed (`TRUE`) or missing
#'   (`FALSE`) resources.
#' @param refresh Whether to refresh the mutable remote catalog.
#' @param cache_dir Resource cache directory.
#'
#' @return A resource catalog data frame.
#' @export
list_resources <- function(type = NULL, installed = NULL, refresh = FALSE,
                           cache_dir = ggbrat_cache_dir()) {
  catalog <- resource_catalog(refresh = refresh, quiet = TRUE)
  if (!is.null(type)) {
    type <- match.arg(type, c("atlas", "surface", "annotation", "volume", "mesh"))
    catalog <- catalog[catalog$type == type, , drop = FALSE]
  }
  catalog$installed <- vapply(seq_len(nrow(catalog)), function(index) {
    resource_cache_valid(catalog[index, , drop = FALSE], attr(catalog, "files"), cache_dir)
  }, logical(1))
  if (!is.null(installed)) {
    if (!is.logical(installed) || length(installed) != 1L || is.na(installed)) {
      stop("`installed` must be NULL, TRUE, or FALSE.", call. = FALSE)
    }
    catalog <- catalog[catalog$installed == installed, , drop = FALSE]
  }
  catalog
}

#' Locate the ggbrat resource cache
#'
#' @param create Whether to create the directory if necessary.
#'
#' @return The normalized cache path.
#' @export
ggbrat_cache_dir <- function(create = TRUE) {
  path <- getOption("ggbrat.cache_dir", Sys.getenv("GGBRAT_CACHE_DIR", ""))
  if (!nzchar(path)) path <- tools::R_user_dir("ggbrat", "cache")
  path <- path.expand(path)
  if (create && !dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, mustWork = FALSE)
}

ggbrat_generated_dir <- function(type, create = TRUE) {
  path <- file.path(ggbrat_cache_dir(create = create), "generated", type)
  if (create && !dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, mustWork = FALSE)
}

resource_select <- function(name, type, catalog) {
  if (!is.character(name) || !length(name) || anyNA(name) || any(!nzchar(name))) {
    stop("`name` must contain one or more resource names, or `\"all\"`.", call. = FALSE)
  }
  if (!is.null(type)) {
    type <- match.arg(type, c("atlas", "surface", "annotation", "volume", "mesh"))
    catalog <- catalog[catalog$type == type, , drop = FALSE]
  }
  if (any(tolower(name) == "all")) {
    if (length(name) != 1L) stop("Use `\"all\"` by itself.", call. = FALSE)
    if (is.null(type)) stop("`type` is required when `name = \"all\"`.", call. = FALSE)
    return(catalog)
  }

  selected <- vector("list", length(name))
  for (index in seq_along(name)) {
    normalized <- resource_normalize_name(name[[index]])
    matches <- catalog$id == name[[index]] |
      resource_normalize_name(catalog$id) == normalized |
      resource_normalize_name(catalog$name) == normalized
    if (!any(matches)) {
      stop("Unknown ggbrat resource: ", name[[index]], call. = FALSE)
    }
    if (sum(matches) > 1L) {
      stop("Resource name is ambiguous: ", name[[index]], ". Supply `type` or its full id.", call. = FALSE)
    }
    selected[[index]] <- catalog[matches, , drop = FALSE]
  }
  do.call(rbind, selected)
}

#' Show metadata for a ggbrat resource
#'
#' @param name Resource name, id, vector of names, or `"all"`.
#' @param type Optional resource category.
#' @param refresh Whether to refresh the mutable remote catalog.
#'
#' @return Matching catalog rows.
#' @export
resource_info <- function(name, type = NULL, refresh = FALSE) {
  resource_select(name, type, resource_catalog(refresh = refresh, quiet = TRUE))
}

resource_files_for <- function(row, files) {
  files[files$resource_id == row$id[[1L]], , drop = FALSE]
}

resource_cache_path <- function(row, cache_dir) {
  file.path(cache_dir, row$release_tag[[1L]], row$id[[1L]])
}

resource_cache_valid <- function(row, files, cache_dir) {
  destination <- resource_cache_path(row, cache_dir)
  stamp <- file.path(destination, ".archive-md5")
  if (!file.exists(stamp) || !identical(trimws(readLines(stamp, warn = FALSE)[1L]), row$md5[[1L]])) {
    return(FALSE)
  }
  entries <- resource_files_for(row, files)
  paths <- file.path(destination, entries$path)
  if (!all(file.exists(paths))) return(FALSE)
  identical(unname(tools::md5sum(paths)), entries$md5)
}

resource_object <- function(row, files, cache_dir) {
  entries <- resource_files_for(row, files)
  paths <- file.path(resource_cache_path(row, cache_dir), entries$path)
  structure(
    list(
      id = row$id[[1L]], name = row$name[[1L]], type = row$type[[1L]],
      version = row$resource_version[[1L]], paths = stats::setNames(paths, entries$role),
      metadata = row
    ),
    class = "ggbrat_resource"
  )
}

resource_download_one <- function(row, files, cache_dir, force, quiet) {
  if (!force && resource_cache_valid(row, files, cache_dir)) {
    return(resource_object(row, files, cache_dir))
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  archive <- tempfile(paste0(row$id[[1L]], "-"), tmpdir = cache_dir, fileext = ".tar.gz")
  extraction <- tempfile(paste0(row$id[[1L]], "-extract-"), tmpdir = cache_dir)
  on.exit(unlink(c(archive, extraction), recursive = TRUE, force = TRUE), add = TRUE)

  base_override <- getOption("ggbrat.resource_base_url", "")
  url <- if (nzchar(base_override)) {
    paste0(sub("/+$", "", base_override), "/", row$asset[[1L]])
  } else {
    row$url[[1L]]
  }
  status <- tryCatch(
    utils::download.file(url, archive, mode = "wb", quiet = quiet),
    error = function(error) error
  )
  if (inherits(status, "error") || !identical(status, 0L)) {
    stop("Failed to download resource `", row$name[[1L]], "` from ", url, ".", call. = FALSE)
  }
  checksum <- unname(tools::md5sum(archive))
  if (!identical(checksum, row$md5[[1L]])) {
    stop(
      "Checksum mismatch for resource `", row$name[[1L]],
      "`. If the mutable prerelease was updated, retry with `refresh = TRUE`.",
      call. = FALSE
    )
  }

  members <- utils::untar(archive, list = TRUE)
  unsafe <- grepl("^(/|[A-Za-z]:)|(^|/)\\.\\.(/|$)", members)
  if (any(unsafe)) stop("Resource archive contains unsafe paths.", call. = FALSE)
  dir.create(extraction)
  utils::untar(archive, exdir = extraction)

  entries <- resource_files_for(row, files)
  extracted <- file.path(extraction, entries$path)
  if (!all(file.exists(extracted)) ||
      !identical(unname(tools::md5sum(extracted)), entries$md5)) {
    stop("Extracted files failed validation for resource `", row$name[[1L]], "`.", call. = FALSE)
  }
  writeLines(row$md5[[1L]], file.path(extraction, ".archive-md5"))

  destination <- resource_cache_path(row, cache_dir)
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(destination)) unlink(destination, recursive = TRUE, force = TRUE)
  if (!file.rename(extraction, destination)) {
    stop("Could not move resource into the ggbrat cache.", call. = FALSE)
  }
  resource_object(row, files, cache_dir)
}

#' Download one or more ggbrat resources
#'
#' @param name Resource name, id, vector of names, or `"all"`.
#' @param type Optional resource category. Required for `name = "all"`.
#' @param force Whether to replace valid cached copies.
#' @param refresh Whether to refresh the mutable remote catalog before resolving
#'   and downloading resources. Use this together with `force = TRUE` after
#'   prerelease assets have been replaced.
#' @param cache_dir Resource cache directory.
#' @param quiet Whether to suppress download progress.
#'
#' @return A `ggbrat_resource` object, or a named list for multiple resources.
#' @export
get_resource <- function(name, type = NULL, force = FALSE, refresh = FALSE,
                         cache_dir = ggbrat_cache_dir(), quiet = FALSE) {
  for (argument in c("force", "refresh", "quiet")) {
    value <- get(argument)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop("`", argument, "` must be TRUE or FALSE.", call. = FALSE)
    }
  }
  catalog <- resource_catalog(refresh = refresh, quiet = quiet)
  rows <- resource_select(name, type, catalog)
  files <- attr(catalog, "files")
  result <- lapply(seq_len(nrow(rows)), function(index) {
    resource_download_one(rows[index, , drop = FALSE], files, cache_dir, force, quiet)
  })
  names(result) <- rows$name
  if (length(result) == 1L) result[[1L]] else result
}

resource_simplify <- function(resources, type) {
  one <- function(resource) {
    paths <- resource$paths
    if (type == "atlas") return(unname(paths[names(paths) == "atlas"][[1L]]))
    if (type == "volume") {
      return(list(
        nifti = unname(paths[names(paths) == "nifti"]),
        lookup = unname(paths[names(paths) == "lookup"])
      ))
    }
    paths
  }
  if (inherits(resources, "ggbrat_resource")) return(one(resources))
  stats::setNames(lapply(resources, one), names(resources))
}

resource_download_type <- function(name, type, force, refresh, cache_dir, quiet) {
  resource_simplify(
    get_resource(name, type, force, refresh, cache_dir, quiet), type
  )
}

#' Download premade ggbrat atlases
#' @inheritParams get_resource
#' @return One cached RDS path, or a named vector of paths.
#' @export
download_atlas <- function(name, force = FALSE, refresh = FALSE,
                           cache_dir = ggbrat_cache_dir(), quiet = FALSE) {
  result <- resource_download_type(name, "atlas", force, refresh, cache_dir, quiet)
  if (is.list(result)) unlist(result, use.names = TRUE) else result
}

#' Download and load premade ggbrat atlases
#' @inheritParams get_resource
#' @return One atlas object, or a named list of atlas objects.
#' @export
load_atlas <- function(name, force = FALSE, refresh = FALSE,
                       cache_dir = ggbrat_cache_dir(), quiet = FALSE) {
  paths <- download_atlas(name, force, refresh, cache_dir, quiet)
  result <- lapply(paths, readRDS)
  names(result) <- names(paths)
  if (length(result) == 1L) result[[1L]] else result
}

#' Download cortical or subcortical surface resources
#' @inheritParams get_resource
#' @param type Surface category to resolve: `"auto"` searches both cortical
#'   surfaces and subcortical meshes, `"cortical"` searches FreeSurfer-style
#'   surfaces, and `"subcortical"` searches generated meshes.
#' @return Named surface paths, or a named list for multiple resources.
#' @export
download_surface <- function(name, type = c("auto", "cortical", "subcortical"),
                             force = FALSE, refresh = FALSE,
                             cache_dir = ggbrat_cache_dir(), quiet = FALSE) {
  type <- match.arg(type)
  catalog <- resource_catalog(refresh = refresh, quiet = quiet)
  catalog_types <- switch(
    type,
    auto = c("surface", "mesh"),
    cortical = "surface",
    subcortical = "mesh"
  )
  surface_catalog <- catalog[catalog$type %in% catalog_types, , drop = FALSE]
  attr(surface_catalog, "files") <- attr(catalog, "files")
  if (is.character(name) && length(name) == 1L && tolower(name) == "all") {
    rows <- surface_catalog
  } else {
    rows <- resource_select(name, type = NULL, catalog = surface_catalog)
  }
  resources <- get_resource(
    rows$id, type = NULL, force = force, refresh = FALSE,
    cache_dir = cache_dir, quiet = quiet
  )
  resource_simplify(resources, "surface")
}

#' Download cortical annotation resources
#' @inheritParams get_resource
#' @return Named left/right paths, or a named list for multiple resources.
#' @export
download_annotation <- function(name, force = FALSE, refresh = FALSE,
                                cache_dir = ggbrat_cache_dir(), quiet = FALSE) {
  resource_download_type(name, "annotation", force, refresh, cache_dir, quiet)
}

#' Download volumetric atlas resources
#' @inheritParams get_resource
#' @return A list containing `nifti` and `lookup` paths, or a named list of
#'   those lists for multiple resources.
#' @export
download_volume_atlas <- function(name, force = FALSE, refresh = FALSE,
                                  cache_dir = ggbrat_cache_dir(), quiet = FALSE) {
  resource_download_type(name, "volume", force, refresh, cache_dir, quiet)
}

#' Remove resources from the ggbrat cache
#' @param name Resource name, id, vector of names, or `"all"`.
#' @param type Optional category, required for `name = "all"`.
#' @param cache_dir Resource cache directory.
#' @return The removed paths, invisibly.
#' @export
remove_resource <- function(name, type = NULL, cache_dir = ggbrat_cache_dir()) {
  catalog <- resource_catalog()
  rows <- resource_select(name, type, catalog)
  paths <- vapply(seq_len(nrow(rows)), function(index) {
    resource_cache_path(rows[index, , drop = FALSE], cache_dir)
  }, character(1))
  for (path in paths[dir.exists(paths)]) unlink(path, recursive = TRUE, force = TRUE)
  invisible(paths)
}

#' Clear the ggbrat resource cache
#' @param cache_dir Resource cache directory.
#' @return The removed cache path, invisibly.
#' @export
clear_resource_cache <- function(cache_dir = ggbrat_cache_dir(create = FALSE)) {
  if (dir.exists(cache_dir)) unlink(cache_dir, recursive = TRUE, force = TRUE)
  invisible(cache_dir)
}
