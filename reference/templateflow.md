# Query resources from TemplateFlow

Thin R wrappers around the official TemplateFlow Python client.
Resources are downloaded lazily into TemplateFlow's cache and returned
as local paths. These functions require Python only when called.

## Usage

``` r
templateflow_templates(...)

templateflow_get(template, ...)

templateflow_metadata(template)

templateflow_citations(template, bibtex = FALSE)
```

## Arguments

- ...:

  BIDS-like TemplateFlow query entities such as `atlas`, `hemi`,
  `density`, `resolution`, `desc`, `suffix`, and `extension`.

- template:

  TemplateFlow template identifier, without the `tpl-` prefix.

- bibtex:

  Whether citations should be returned in BibTeX form.

## Value

`templateflow_templates()` returns template identifiers;
`templateflow_get()` returns local file paths; metadata and citation
functions return values supplied by TemplateFlow.
