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

resource_citations <- function(name) {
  citations <- rep(NA_character_, length(name))

  set_citation <- function(pattern, value) {
    matches <- is.na(citations) & grepl(pattern, name, ignore.case = TRUE)
    citations[matches] <<- value
  }

  # More specific names must be matched before their parent atlas families.
  set_citation(
    "^aparc\\.a2005s$",
    paste0(
      "Fischl B, van der Kouwe A, Destrieux C, et al. (2004). ",
      "Automatically parcellating the human cerebral cortex. Cerebral Cortex ",
      "14:11-22. doi:10.1093/cercor/bhg087."
    )
  )
  set_citation(
    "^aparc\\.a2009s$",
    paste0(
      "Destrieux C, Fischl B, Dale A, Halgren E (2010). Automatic ",
      "parcellation of human cortical gyri and sulci using standard anatomical ",
      "nomenclature. NeuroImage 53:1-15. ",
      "doi:10.1016/j.neuroimage.2010.06.010."
    )
  )
  set_citation(
    "^aparc$",
    paste0(
      "Desikan RS, Segonne F, Fischl B, et al. (2006). An automated labeling ",
      "system for subdividing the human cerebral cortex on MRI scans into ",
      "gyral based regions of interest. NeuroImage 31:968-980. ",
      "doi:10.1016/j.neuroimage.2006.01.021."
    )
  )
  set_citation(
    "^aseg_subcortex$",
    paste0(
      "Fischl B, Salat DH, Busa E, et al. (2002). Whole brain segmentation: ",
      "automated labeling of neuroanatomical structures in the human brain. ",
      "Neuron 33:341-355. doi:10.1016/S0896-6273(02)00569-X."
    )
  )
  set_citation(
    "^HCP-MMP1$",
    paste0(
      "Glasser MF, Coalson TS, Robinson EC, et al. (2016). A multi-modal ",
      "parcellation of human cerebral cortex. Nature 536:171-178. ",
      "doi:10.1038/nature18933."
    )
  )
  set_citation(
    "^HO_FSSpace$",
    paste0(
      "Harvard-Oxford Cortical Structural Atlas, Harvard Center for ",
      "Morphometric Analysis and FMRIB Software Library. RRID:SCR_001476."
    )
  )
  set_citation(
    "^PALS_B12_",
    paste0(
      "Van Essen DC (2005). A Population-Average, Landmark- and ",
      "Surface-based (PALS) atlas of human cerebral cortex. NeuroImage ",
      "28:635-662. doi:10.1016/j.neuroimage.2005.06.058."
    )
  )
  set_citation(
    "^Schaefer2018_.*Kong2022",
    paste0(
      "Schaefer A, Kong R, Gordon EM, et al. (2018). Local-global ",
      "parcellation of the human cerebral cortex from intrinsic functional ",
      "connectivity MRI. Cerebral Cortex 28:3095-3114. ",
      "doi:10.1093/cercor/bhx179; Kong R, et al. (2021). ",
      "Individual-specific areal-level parcellations improve functional ",
      "connectivity prediction of behavior. Cerebral Cortex 31:4477-4500. ",
      "doi:10.1093/cercor/bhab101."
    )
  )
  set_citation(
    "^Schaefer2018_",
    paste0(
      "Schaefer A, Kong R, Gordon EM, et al. (2018). Local-global ",
      "parcellation of the human cerebral cortex from intrinsic functional ",
      "connectivity MRI. Cerebral Cortex 28:3095-3114. ",
      "doi:10.1093/cercor/bhx179."
    )
  )
  set_citation(
    "^Yeo2011_",
    paste0(
      "Yeo BTT, Krienen FM, Sepulcre J, et al. (2011). The organization of ",
      "the human cerebral cortex estimated by intrinsic functional ",
      "connectivity. Journal of Neurophysiology 106:1125-1165. ",
      "doi:10.1152/jn.00338.2011."
    )
  )
  set_citation(
    "^AICHA_subcortex$",
    paste0(
      "Joliot M, Jobard G, Naveau M, et al. (2015). AICHA: An atlas of ",
      "intrinsic connectivity of homotopic areas. Journal of Neuroscience ",
      "Methods 254:46-59. doi:10.1016/j.jneumeth.2015.07.013."
    )
  )
  set_citation(
    "^Brainnetome_subcortex$",
    paste0(
      "Fan L, Li H, Zhuo J, et al. (2016). The Human Brainnetome Atlas: ",
      "A new brain atlas based on connectional architecture. Cerebral Cortex ",
      "26:3508-3526. doi:10.1093/cercor/bhw157."
    )
  )
  set_citation(
    "^Brainstem_Navigator",
    paste0(
      "Bianciardi M and the Brainstem Imaging Laboratory (2024). Brainstem ",
      "Navigator v1.0: an in-vivo MRI atlas of human brainstem nuclei. ",
      "doi:10.25790/bml0cm.96."
    )
  )
  set_citation(
    "^CIT168_subcortex$",
    paste0(
      "Pauli WM, Nili AN, Tyszka JM (2018). A high-resolution probabilistic ",
      "in vivo atlas of human subcortical brain nuclei. Scientific Data ",
      "5:180063. doi:10.1038/sdata.2018.63."
    )
  )
  set_citation(
    "^Melbourne_S[1-4]$",
    paste0(
      "Tian Y, Margulies DS, Breakspear M, Zalesky A (2020). Topographic ",
      "organization of the human subcortex unveiled with functional ",
      "connectivity gradients. Nature Neuroscience 23:1421-1432. ",
      "doi:10.1038/s41593-020-00711-6."
    )
  )
  set_citation(
    "^SUIT_cerebellar_lobule$",
    paste0(
      "Diedrichsen J, Balsters JH, Flavell J, Cussans E, Ramnani N (2009). ",
      "A probabilistic MR atlas of the human cerebellum. NeuroImage 46:39-46. ",
      "doi:10.1016/j.neuroimage.2009.01.045."
    )
  )
  set_citation(
    "^Thalamus_HCP$",
    paste0(
      "Najdenovska E, Aleman-Gomez Y, Battistella G, et al. (2018). In-vivo ",
      "probabilistic atlas of human thalamic nuclei based on diffusion-weighted ",
      "magnetic resonance imaging. Scientific Data 5:180270. ",
      "doi:10.1038/sdata.2018.270."
    )
  )
  set_citation(
    "^Thalamus_THOMAS$",
    paste0(
      "Su JH, Thomas FT, Kasoff WS, et al. (2019). Thalamus Optimized Multi ",
      "Atlas Segmentation (THOMAS): fast, fully automated segmentation of ",
      "thalamic nuclei from structural MRI. NeuroImage 194:272-282. ",
      "doi:10.1016/j.neuroimage.2019.03.021."
    )
  )
  set_citation(
    "^fsaverage_",
    paste0(
      "Fischl B, Sereno MI, Dale AM (1999). Cortical surface-based analysis. ",
      "II: Inflation, flattening, and a surface-based coordinate system. ",
      "NeuroImage 9:195-207. doi:10.1006/nimg.1998.0396."
    )
  )
  set_citation(
    "^tpl-MNI152NLin2009cAsym_",
    paste0(
      "Fonov V, Evans AC, Botteron K, Almli CR, McKinstry RC, Collins DL ",
      "(2011). Unbiased average age-appropriate atlases for pediatric studies. ",
      "NeuroImage 54:313-327. doi:10.1016/j.neuroimage.2010.07.033."
    )
  )
  set_citation(
    "^data_StateMTL_241118_0$",
    paste0(
      "No definitive source citation could be identified from the mesh ",
      "filename alone; verify the citation with the provider before reuse."
    )
  )

  citations
}

resource_add_citations <- function(catalog) {
  inferred <- resource_citations(catalog$name)
  if (!"citation" %in% names(catalog)) {
    catalog$citation <- inferred
  } else {
    missing <- is.na(catalog$citation) | !nzchar(trimws(catalog$citation))
    catalog$citation[missing] <- inferred[missing]
  }
  catalog
}

resource_aliases <- function(name) {
  aliases <- rep("", length(name))

  set_aliases <- function(pattern, value) {
    matches <- !nzchar(aliases) & grepl(pattern, name, ignore.case = TRUE)
    aliases[matches] <<- value
  }

  set_aliases("^aparc$", "desikan-killiany;desikan killiany;desikan;dk")
  set_aliases("^aparc\\.a2005s$", "destrieux2005;destrieux 2005")
  set_aliases(
    "^aparc\\.a2009s$",
    "destrieux;destrieux2009;destrieux 2009"
  )
  set_aliases("^HCP-MMP1$", "glasser;glasser360;glasser 360;mmp1;hcp mmp")
  set_aliases(
    "^HO_FSSpace$",
    "harvard-oxford;harvard oxford;harvard oxford cortical;ho cortical"
  )
  set_aliases("^PALS_B12_Brodmann$", "pals brodmann;pals-b12 brodmann")
  set_aliases("^PALS_B12_Lobes$", "pals lobes;pals-b12 lobes")
  set_aliases(
    "^Yeo2011_7Networks_N1000$",
    "yeo7;yeo 7;yeo-7;yeo 7 networks"
  )
  set_aliases(
    "^Yeo2011_17Networks_N1000$",
    "yeo17;yeo 17;yeo-17;yeo 17 networks"
  )
  set_aliases("^AICHA_subcortex$", "aicha")
  set_aliases("^aseg_subcortex$", "aseg;freesurfer aseg")
  set_aliases("^Brainstem_Navigator", "brainstem navigator;brainstemnavig")
  set_aliases("^CIT168_subcortex$", "cit168;pauli atlas;pauli")
  set_aliases("^Melbourne_S1$", "melbourne scale 1;tian s1;tian scale 1")
  set_aliases("^Melbourne_S2$", "melbourne scale 2;tian s2;tian scale 2")
  set_aliases("^Melbourne_S3$", "melbourne scale 3;tian s3;tian scale 3")
  set_aliases("^Melbourne_S4$", "melbourne scale 4;tian s4;tian scale 4")
  set_aliases("^SUIT_cerebellar_lobule$", "suit;suit lobules;cerebellar lobules")
  set_aliases("^Thalamus_HCP$", "hcp thalamus;hcp thalamic nuclei")
  set_aliases("^Thalamus_THOMAS$", "thomas;thomas thalamus")
  set_aliases("^fsaverage_inflated$", "inflated;fsaverage inflated")
  set_aliases("^fsaverage_pial$", "pial;fsaverage pial")
  set_aliases("^fsaverage_white$", "white;fsaverage white")
  set_aliases("^fsaverage_orig$", "orig;fsaverage orig")
  set_aliases("^fsaverage_sulc$", "sulc;fsaverage sulc")
  set_aliases("^fsaverage_curv$", "curv;fsaverage curv")
  set_aliases(
    "^tpl-MNI152NLin2009cAsym_res-01_label-GM_probseg$",
    "mni gray matter;mni gm;gray matter probability map;gm probability map"
  )

  aliases
}

resource_add_aliases <- function(catalog) {
  inferred <- resource_aliases(catalog$name)
  if (!"aliases" %in% names(catalog)) {
    catalog$aliases <- inferred
  } else {
    missing <- is.na(catalog$aliases) | !nzchar(trimws(catalog$aliases))
    catalog$aliases[missing] <- inferred[missing]
  }
  catalog$aliases[is.na(catalog$aliases)] <- ""
  catalog
}

resource_alias_list <- function(x) {
  lapply(x, function(value) {
    if (is.na(value) || !nzchar(trimws(value))) return(character())
    aliases <- trimws(strsplit(value, ";", fixed = TRUE)[[1L]])
    unique(aliases[nzchar(aliases)])
  })
}

#' Inspect the ggbrat resource catalog
#'
#' The package ships with a catalog snapshot. Set `refresh = TRUE` to read the
#' current catalog from the mutable resources prerelease.
#'
#' @param refresh Whether to download the current remote catalog.
#' @param quiet Whether to suppress download progress.
#'
#' @return A data frame containing one row per resource, including its
#'   recommended source `citation` and semicolon-separated `aliases`. The
#'   associated file table is stored in the `files` attribute.
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

  catalog <- resource_add_citations(catalog)
  catalog <- resource_add_aliases(catalog)
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
#' @return A resource catalog data frame. The `citation` column gives the
#'   recommended source citation and `aliases` gives semicolon-separated
#'   alternative names for each resource.
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

resource_resolve_ambiguous <- function(candidates, query) {
  choices <- paste0(
    candidates$name, " [", candidates$type, "; ", candidates$id, "]"
  )
  if (!interactive()) {
    stop(
      "Multiple ggbrat resources match `", query, "`:\n- ",
      paste(choices, collapse = "\n- "),
      "\nPlease provide a more specific name.",
      call. = FALSE
    )
  }

  selection <- utils::menu(
    choices,
    title = paste0("Multiple resources match `", query, "`. Select one:")
  )
  if (!length(selection) || selection == 0L) {
    stop("Resource selection cancelled.", call. = FALSE)
  }
  candidates[selection, , drop = FALSE]
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
    if (!nzchar(normalized)) {
      stop(
        "Resource names must contain at least one letter or number.",
        call. = FALSE
      )
    }
    alias_column <- if ("aliases" %in% names(catalog)) {
      catalog$aliases
    } else {
      rep("", nrow(catalog))
    }
    alias_values <- resource_alias_list(alias_column)
    normalized_aliases <- lapply(alias_values, resource_normalize_name)
    exact_name_matches <- catalog$id == name[[index]] |
      resource_normalize_name(catalog$id) == normalized |
      resource_normalize_name(catalog$name) == normalized
    exact_alias_matches <- vapply(
      normalized_aliases,
      function(aliases) normalized %in% aliases,
      logical(1)
    )
    if (any(exact_name_matches)) {
      candidates <- catalog[exact_name_matches, , drop = FALSE]
    } else if (any(exact_alias_matches)) {
      candidates <- catalog[exact_alias_matches, , drop = FALSE]
    } else {
      normalized_ids <- resource_normalize_name(catalog$id)
      normalized_names <- resource_normalize_name(catalog$name)
      partial_matches <- grepl(normalized, normalized_ids, fixed = TRUE) |
        grepl(normalized, normalized_names, fixed = TRUE)
      if (nchar(normalized) >= 3L) {
        partial_alias_matches <- vapply(
          normalized_aliases,
          function(aliases) {
            any(vapply(
              aliases,
              function(alias) grepl(normalized, alias, fixed = TRUE),
              logical(1)
            ))
          },
          logical(1)
        )
        partial_matches <- partial_matches | partial_alias_matches
      }
      candidates <- catalog[partial_matches, , drop = FALSE]
    }
    if (!nrow(candidates)) {
      stop("Unknown ggbrat resource: ", name[[index]], call. = FALSE)
    }
    if (nrow(candidates) > 1L) {
      candidates <- resource_resolve_ambiguous(candidates, name[[index]])
    }
    selected[[index]] <- candidates
  }
  do.call(rbind, selected)
}

#' Show metadata for a ggbrat resource
#'
#' @param name Resource name, id, alias, partial name, vector of names, or
#'   `"all"`. Exact normalized names and ids take priority, followed by exact
#'   aliases. A unique partial match is selected automatically; multiple
#'   matches open a selection menu in interactive R and produce an informative
#'   error otherwise.
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
#' @param name Resource name, id, alias, partial name, vector of names, or
#'   `"all"`. Exact normalized names and ids take priority, followed by exact
#'   aliases. A unique partial match is selected automatically; multiple
#'   matches open a selection menu in interactive R and produce an informative
#'   error otherwise.
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
#' @param name Resource name, id, alias, partial name, vector of names, or
#'   `"all"`. Exact normalized names and ids take priority, followed by exact
#'   aliases. A unique partial match is selected automatically; multiple
#'   matches open a selection menu in interactive R and produce an informative
#'   error otherwise.
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
