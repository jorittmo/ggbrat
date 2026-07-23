# Package index

## Build atlases

- [`build_atlas_surf()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_surf.md)
  : Build a shifted polygon atlas with shading support
- [`build_atlas_vol()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_vol.md)
  : Build orthogonal 2D atlases from volumetric NIfTI images
- [`build_atlas_svg()`](https://jorittmo.github.io/ggbrat/reference/build_atlas_svg.md)
  : Build an sf atlas from labelled SVG layers
- [`nifti_to_surface()`](https://jorittmo.github.io/ggbrat/reference/nifti_to_surface.md)
  : Create a labelled surface mesh from a NIfTI atlas

## Surface processing

- [`brain_views()`](https://jorittmo.github.io/ggbrat/reference/brain_views.md)
  : Build 2D atlas views from cortical or labelled surface meshes
- [`capture_brain_view_presets()`](https://jorittmo.github.io/ggbrat/reference/capture_brain_view_presets.md)
  : Capture camera presets for later atlas builds
- [`shift_brain_views()`](https://jorittmo.github.io/ggbrat/reference/shift_brain_views.md)
  : Shift atlas views into a plotting grid
- [`compact_subcortical_layout()`](https://jorittmo.github.io/ggbrat/reference/compact_subcortical_layout.md)
  : Compact a subcortical atlas layout
- [`shrink_polygons()`](https://jorittmo.github.io/ggbrat/reference/shrink_polygons.md)
  : Shrink polygon geometries
- [`smooth_polygons()`](https://jorittmo.github.io/ggbrat/reference/smooth_polygons.md)
  : Smooth polygon boundaries

## Resources

- [`resource_catalog()`](https://jorittmo.github.io/ggbrat/reference/resource_catalog.md)
  : Inspect the ggbrat resource catalog
- [`list_resources()`](https://jorittmo.github.io/ggbrat/reference/list_resources.md)
  : List downloadable ggbrat resources
- [`resource_info()`](https://jorittmo.github.io/ggbrat/reference/resource_info.md)
  : Show metadata for a ggbrat resource
- [`get_resource()`](https://jorittmo.github.io/ggbrat/reference/get_resource.md)
  : Download one or more ggbrat resources
- [`download_atlas()`](https://jorittmo.github.io/ggbrat/reference/download_atlas.md)
  : Download premade ggbrat atlases
- [`load_atlas()`](https://jorittmo.github.io/ggbrat/reference/load_atlas.md)
  : Download and load premade ggbrat atlases
- [`download_annotation()`](https://jorittmo.github.io/ggbrat/reference/download_annotation.md)
  : Download cortical annotation resources
- [`download_surface()`](https://jorittmo.github.io/ggbrat/reference/download_surface.md)
  : Download cortical or subcortical surface resources
- [`download_volume_atlas()`](https://jorittmo.github.io/ggbrat/reference/download_volume_atlas.md)
  : Download volumetric atlas resources
- [`ggbrat_cache_dir()`](https://jorittmo.github.io/ggbrat/reference/ggbrat_cache_dir.md)
  : Locate the ggbrat resource cache
- [`remove_resource()`](https://jorittmo.github.io/ggbrat/reference/remove_resource.md)
  : Remove resources from the ggbrat cache
- [`clear_resource_cache()`](https://jorittmo.github.io/ggbrat/reference/clear_resource_cache.md)
  : Clear the ggbrat resource cache

## TemplateFlow

- [`templateflow_templates()`](https://jorittmo.github.io/ggbrat/reference/templateflow.md)
  [`templateflow_get()`](https://jorittmo.github.io/ggbrat/reference/templateflow.md)
  [`templateflow_metadata()`](https://jorittmo.github.io/ggbrat/reference/templateflow.md)
  [`templateflow_citations()`](https://jorittmo.github.io/ggbrat/reference/templateflow.md)
  : Query resources from TemplateFlow

## Lower-level helpers

- [`ashape_polygon_sf()`](https://jorittmo.github.io/ggbrat/reference/ashape_polygon_sf.md)
  : Convert a point cloud to polygonal geometry using an alpha hull
- [`auto_alpha()`](https://jorittmo.github.io/ggbrat/reference/auto_alpha.md)
  : Estimate alpha radius for an alpha hull
- [`knn_density_filter()`](https://jorittmo.github.io/ggbrat/reference/knn_density_filter.md)
  : Filter points by local kNN density
- [`silhouette_sf()`](https://jorittmo.github.io/ggbrat/reference/silhouette_sf.md)
  [`silhoutte_sf()`](https://jorittmo.github.io/ggbrat/reference/silhouette_sf.md)
  : Convert silhouette segments into merged sf lines

## Data

- [`grads`](https://jorittmo.github.io/ggbrat/reference/grads.md) : Five
  cortical connectivity gradients for the Schaefer 1000 atlas
