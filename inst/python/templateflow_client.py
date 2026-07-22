"""Small conversion layer around TemplateFlow's official Python client."""

from pathlib import Path

import templateflow
from templateflow import api


def _paths(value):
    if value is None:
        return []
    if isinstance(value, (str, Path)):
        return [str(value)]
    return [str(path) for path in value]


def tf_templates(**filters):
    return list(api.templates(**filters))


def tf_get(template, **entities):
    return _paths(api.get(template, **entities))


def tf_metadata(template):
    return api.get_metadata(template)


def tf_citations(template, bibtex=False):
    return api.get_citations(template, bibtex=bibtex)


def tf_version():
    return templateflow.__version__
