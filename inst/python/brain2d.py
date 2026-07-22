import os

import nibabel as nib
import numpy as np
import pandas as pd
import pyvista as pv
import vtk


UNLABELLED_NAME = "unlabelled"
UNLABELLED_COLOR = "#bdbdbd"


def blend_hemispheres(
    surf_dir,
    surface1,
    surface2,
    output_name="mixed",
    output_dir=None,
    ratio=0.5,
):
    """Blend paired FreeSurfer surfaces and write them to a temporary location."""
    if not 0.0 <= ratio <= 1.0:
        raise ValueError("ratio must be between 0 and 1")

    if output_dir is None:
        output_dir = surf_dir

    os.makedirs(output_dir, exist_ok=True)
    output_paths = []

    for hemi in ("lh", "rh"):
        path1 = os.path.join(surf_dir, f"{hemi}.{surface1}")
        path2 = os.path.join(surf_dir, f"{hemi}.{surface2}")
        output_path = os.path.join(output_dir, f"{hemi}.{output_name}")

        coords1, faces = nib.freesurfer.read_geometry(path1)
        coords2, _ = nib.freesurfer.read_geometry(path2)
        blended_coords = ratio * coords1 + (1.0 - ratio) * coords2

        nib.freesurfer.write_geometry(
            output_path,
            blended_coords.astype(np.float32),
            faces,
        )
        output_paths.append(output_path)

    return output_paths


def _decode_name(value):
    if isinstance(value, bytes):
        return value.decode()
    return str(value)


def _read_annot(annot_path):
    """Return region names and colors per vertex, preserving unlabeled vertices."""
    labels, ctab, names = nib.freesurfer.read_annot(annot_path)
    names = np.asarray([_decode_name(name) for name in names], dtype=object)
    hexcols = np.asarray(
        ["#{:02x}{:02x}{:02x}".format(*ctab[i, :3]) for i in range(len(ctab))],
        dtype=object,
    )

    vertex_names = np.full(labels.shape, UNLABELLED_NAME, dtype=object)
    vertex_colors = np.full(labels.shape, UNLABELLED_COLOR, dtype=object)
    valid = (labels >= 0) & (labels < len(names))

    vertex_names[valid] = names[labels[valid]]
    vertex_colors[valid] = hexcols[labels[valid]]
    return vertex_names, vertex_colors


def _read_gifti_surface(surface_path):
    """Read vertices and triangular faces from a GIFTI surface."""
    image = nib.load(surface_path)
    pointset_code = nib.nifti1.intent_codes["NIFTI_INTENT_POINTSET"]
    triangle_code = nib.nifti1.intent_codes["NIFTI_INTENT_TRIANGLE"]
    pointsets = image.get_arrays_from_intent(pointset_code)
    triangles = image.get_arrays_from_intent(triangle_code)
    if len(pointsets) != 1 or len(triangles) != 1:
        raise ValueError(
            f"{surface_path!r} must contain one GIFTI pointset and one triangle array."
        )
    coords = np.asarray(pointsets[0].data, dtype=np.float64)
    faces = np.asarray(triangles[0].data, dtype=np.int64)
    if coords.ndim != 2 or coords.shape[1] != 3:
        raise ValueError(f"GIFTI pointset has invalid shape {coords.shape}.")
    if faces.ndim != 2 or faces.shape[1] != 3:
        raise ValueError(f"GIFTI triangle array has invalid shape {faces.shape}.")
    return coords, faces


def _read_surface(surface_path):
    """Read a FreeSurfer or GIFTI triangular surface."""
    if str(surface_path).lower().endswith((".surf.gii", ".gii")):
        return _read_gifti_surface(surface_path)
    return nib.freesurfer.read_geometry(surface_path)


def _rgba_to_hex(label):
    values = np.clip(
        np.asarray([label.red, label.green, label.blue], dtype=float), 0.0, 1.0
    )
    rgb = np.rint(values * 255).astype(int)
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def _read_gifti_labels(label_path):
    """Return region names and colors per vertex from a GIFTI label file."""
    image = nib.load(label_path)
    label_code = nib.nifti1.intent_codes["NIFTI_INTENT_LABEL"]
    arrays = image.get_arrays_from_intent(label_code)
    if len(arrays) != 1:
        raise ValueError(f"{label_path!r} must contain one GIFTI label array.")
    values = np.asarray(arrays[0].data)
    if values.ndim != 1:
        raise ValueError(f"GIFTI labels must be one-dimensional; got {values.shape}.")
    if not np.all(np.isfinite(values)) or not np.allclose(values, np.rint(values)):
        raise ValueError("GIFTI label values must be finite integers.")
    values = np.rint(values).astype(np.int64)

    table = {int(label.key): label for label in image.labeltable.labels}
    vertex_names = np.empty(values.shape, dtype=object)
    vertex_colors = np.empty(values.shape, dtype=object)
    unlabelled = {"", "???", "unknown", "unlabeled", "unlabelled", "medial wall"}
    for key in np.unique(values):
        label = table.get(int(key))
        if label is None:
            name = UNLABELLED_NAME if key in (-1, 0) else f"label_{key}"
            color = UNLABELLED_COLOR
        else:
            name = "" if label.label is None else _decode_name(label.label).strip()
            if name.lower() in unlabelled:
                name = UNLABELLED_NAME
            color = UNLABELLED_COLOR if name == UNLABELLED_NAME else _rgba_to_hex(label)
        selected = values == key
        vertex_names[selected] = name
        vertex_colors[selected] = color
    return vertex_names, vertex_colors


def _read_vertex_labels(label_path):
    """Read a FreeSurfer annotation or GIFTI label file."""
    if str(label_path).lower().endswith(".gii"):
        return _read_gifti_labels(label_path)
    return _read_annot(label_path)


def read_surface_file(surface_path):
    """Public validation helper returning vertices and faces."""
    return _read_surface(surface_path)


def read_label_file(label_path):
    """Public validation helper returning per-vertex names and colors."""
    return _read_vertex_labels(label_path)


def blend_surface_files(surface_paths, output_path, ratio=0.5):
    """Blend two FreeSurfer or GIFTI surfaces with matching topology."""
    paths = list(surface_paths)
    if len(paths) != 2:
        raise ValueError("surface_paths must contain exactly two files")
    if not 0.0 <= ratio <= 1.0:
        raise ValueError("ratio must be between 0 and 1")
    coords1, faces1 = _read_surface(paths[0])
    coords2, faces2 = _read_surface(paths[1])
    if coords1.shape != coords2.shape:
        raise ValueError(
            f"Surfaces have different vertex shapes: {coords1.shape} and {coords2.shape}."
        )
    if faces1.shape != faces2.shape or not np.array_equal(faces1, faces2):
        raise ValueError("Surfaces must have identical triangle topology to be blended.")
    blended = ratio * coords1 + (1.0 - ratio) * coords2
    nib.freesurfer.write_geometry(
        output_path, blended.astype(np.float32), faces1.astype(np.int32)
    )
    return output_path


def _visible_ids(mesh, renderer):
    """Run vtkSelectVisiblePoints and return visible vertex indices."""
    selector = vtk.vtkSelectVisiblePoints()
    selector.SetInputData(mesh)
    selector.SetRenderer(renderer)
    selector.SelectInvisibleOff()
    renderer.GetRenderWindow().Render()
    selector.Update()
    return pv.wrap(selector.GetOutput())["pid"]


def _project_2d(mesh, renderer, win_size, keep_z=False):
    """Project mesh points to centered display coordinates in roughly -1..1."""
    width, height = win_size
    scale = max(width, height) / 2.0
    n_cols = 3 if keep_z else 2
    xyz = np.empty((mesh.n_points, n_cols))

    for i, point in enumerate(mesh.points):
        renderer.SetWorldPoint(*point, 1.0)
        renderer.WorldToDisplay()
        x, y, z = renderer.GetDisplayPoint()
        xyz[i, 0] = (x - width / 2.0) / scale
        xyz[i, 1] = (y - height / 2.0) / scale
        if keep_z:
            xyz[i, 2] = z

    return xyz


def _mirror_camera(camera_position):
    eye, focus, up = camera_position
    return [
        (-eye[0], eye[1], eye[2]),
        (-focus[0], focus[1], focus[2]),
        (-up[0], up[1], up[2]),
    ]


def _silhouette_segments(mesh, renderer, camera, win_size, decimate=0.0, occlude=True):
    """Return visible silhouette line segments in projected 2D space."""
    silhouette = vtk.vtkPolyDataSilhouette()
    silhouette.SetInputData(mesh)
    silhouette.SetCamera(camera)
    silhouette.Update()
    sil_poly = pv.wrap(silhouette.GetOutput())

    if occlude and sil_poly.n_points > 0:
        sil_poly.point_data["pid"] = np.arange(sil_poly.n_points)
        renderer.SetActiveCamera(camera)
        renderer.GetRenderWindow().Render()
        visible_ids = _visible_ids(sil_poly, renderer)
        mask = np.zeros(sil_poly.n_points, dtype=bool)
        mask[visible_ids] = True

        visible_points = sil_poly.extract_points(mask, adjacent_cells=True)
        geometry = vtk.vtkGeometryFilter()
        geometry.SetInputData(visible_points)
        geometry.Update()
        sil_poly = pv.wrap(geometry.GetOutput())

    stripper = vtk.vtkStripper()
    stripper.JoinContiguousSegmentsOn()
    stripper.SetInputData(sil_poly)
    stripper.Update()
    output_port = stripper.GetOutputPort()

    if 0.0 < decimate < 1.0:
        decimator = vtk.vtkDecimatePolylineFilter()
        decimator.SetInputConnection(output_port)
        decimator.SetTargetReduction(decimate)
        decimator.Update()
        output_port = decimator.GetOutputPort()

    sil_poly = pv.wrap(vtk.vtkPolyData.SafeDownCast(output_port.GetProducer().GetOutput()))

    ordered_stripper = vtk.vtkStripper()
    ordered_stripper.JoinContiguousSegmentsOn()
    ordered_stripper.SetInputData(sil_poly)
    ordered_stripper.Update()
    ordered = pv.wrap(ordered_stripper.GetOutput())

    xyz = _project_2d(ordered, renderer, win_size, keep_z=True)
    cells = ordered.lines
    segments = []
    cursor = 0

    while cursor < len(cells):
        n_points = cells[cursor]
        indices = cells[cursor + 1 : cursor + 1 + n_points]
        for start, end in zip(indices, indices[1:]):
            segments.append([*xyz[start], *xyz[end]])
        cursor += n_points + 1

    return pd.DataFrame(segments, columns=["x0", "y0", "z0", "x1", "y1", "z1"])


def _show_and_capture_camera(plotter):
    """Show a labelled confirmation control and return the selected camera."""
    selected = {"camera": None}

    def confirm_view(checked=True):
        if not checked:
            return
        selected["camera"] = plotter.camera_position
        if plotter.iren is not None:
            plotter.iren.terminate_app()

    plotter.add_checkbox_button_widget(
        confirm_view,
        value=False,
        position=(12, 12),
        size=42,
        border_size=3,
        color_on="#2ca25f",
        color_off="#74c476",
        background_color="white",
    )
    plotter.add_text(
        "Use this view",
        position=(64, 21),
        font_size=12,
        color="black",
        name="camera-confirmation-label",
    )
    plotter.add_text(
        "Rotate/zoom, then click the green button (or press U)",
        position="upper_left",
        font_size=10,
        color="black",
        name="camera-confirmation-help",
    )
    plotter.add_key_event("u", confirm_view)
    plotter.show()
    camera_position = selected["camera"] or plotter.camera_position
    plotter.close()
    return camera_position


def _finalize_camera(mirror_camera, hemisphere, plotter=None):
    if mirror_camera is None:
        if plotter is None:
            raise ValueError("plotter is required when mirror_camera is None")
        return _show_and_capture_camera(plotter)

    if hemisphere == "right":
        return _mirror_camera(mirror_camera)

    return mirror_camera


def extract_visible_2d(
    surf_path,
    annot_path,
    hemisphere="left",
    mirror_camera=None,
    window_size=(800, 600),
    return_silhouette=True,
    sil_decimate=0.0,
    sil_spline_subdiv=0,
    keep_z_coord=False,
):
    """Return visible vertices from a FreeSurfer surface projected to 2D."""
    del sil_spline_subdiv

    coords, faces = _read_surface(surf_path)
    faces_pv = np.hstack([np.full((faces.shape[0], 1), 3), faces]).astype(np.int64).ravel()
    mesh = pv.PolyData(coords, faces_pv)

    names, colors = _read_vertex_labels(annot_path)
    if len(names) != len(coords):
        raise ValueError(
            f"Surface has {len(coords)} vertices but labels contain {len(names)} values."
        )
    mesh["region"] = names
    mesh["color"] = colors
    mesh.point_data["pid"] = np.arange(mesh.n_points)

    plotter = None
    if mirror_camera is None:
        plotter = pv.Plotter(window_size=window_size)
        plotter.add_mesh(mesh, color="lightpink", silhouette={"color": "black", "line_width": 1.0})

    camera_position = _finalize_camera(mirror_camera, hemisphere, plotter=plotter)

    offscreen = pv.Plotter(off_screen=True, window_size=window_size)
    offscreen.add_mesh(mesh)
    offscreen.camera_position = camera_position
    offscreen.renderer.GetRenderWindow().Render()

    visible_ids = _visible_ids(mesh, offscreen.renderer)
    visible_mask = np.zeros(mesh.n_points, dtype=bool)
    visible_mask[visible_ids] = True
    projected = _project_2d(
        mesh, offscreen.renderer, window_size, keep_z=keep_z_coord
    )

    if return_silhouette:
        seg_df = _silhouette_segments(
            mesh,
            renderer=offscreen.renderer,
            camera=offscreen.renderer.GetActiveCamera(),
            win_size=window_size,
            decimate=sil_decimate,
        )
    else:
        seg_df = None

    vertex_data = dict(
            vertex=np.arange(mesh.n_points)[visible_mask],
            x=projected[visible_mask, 0],
            y=projected[visible_mask, 1],
            region=mesh["region"][visible_mask],
            color=mesh["color"][visible_mask],
            hemisphere=hemisphere,
    )
    if keep_z_coord:
        vertex_data["z"] = projected[visible_mask, 2]
    df = pd.DataFrame(vertex_data)

    offscreen.close()
    return df, camera_position, seg_df


def extract_visible_2d_surface(
    surf_path,
    hemisphere="left",
    mirror_camera=None,
    window_size=(800, 600),
    point_fraction=0.05,
    random_seed=1,
    return_silhouette=True,
    sil_decimate=0.0,
    keep_z_coord=False,
):
    """Project an unlabelled FreeSurfer surface as a contextual glass layer."""
    if not 0.0 < point_fraction <= 1.0:
        raise ValueError("point_fraction must be in the interval (0, 1]")

    coords, faces = _read_surface(surf_path)
    faces_pv = np.hstack([np.full((faces.shape[0], 1), 3), faces]).astype(np.int64).ravel()
    mesh = pv.PolyData(coords, faces_pv)
    mesh.point_data["pid"] = np.arange(mesh.n_points)

    plotter = None
    if mirror_camera is None:
        plotter = pv.Plotter(window_size=window_size)
        plotter.add_mesh(mesh, color="lightgray", opacity=0.2)

    camera_position = _finalize_camera(mirror_camera, hemisphere, plotter=plotter)
    offscreen = pv.Plotter(off_screen=True, window_size=window_size)
    offscreen.add_mesh(mesh)
    offscreen.camera_position = camera_position
    offscreen.renderer.GetRenderWindow().Render()

    visible_ids = np.asarray(_visible_ids(mesh, offscreen.renderer), dtype=np.int64)
    if point_fraction < 1.0 and visible_ids.size:
        keep_n = max(1, int(np.ceil(visible_ids.size * point_fraction)))
        rng = np.random.default_rng(random_seed)
        visible_ids = np.sort(rng.choice(visible_ids, size=keep_n, replace=False))

    projected = _project_2d(
        mesh, offscreen.renderer, window_size, keep_z=keep_z_coord
    )
    vertex_data = dict(
            vertex=visible_ids,
            x=projected[visible_ids, 0],
            y=projected[visible_ids, 1],
            region="cortex",
            color="#737373",
            hemisphere=hemisphere,
    )
    if keep_z_coord:
        vertex_data["z"] = projected[visible_ids, 2]
    df = pd.DataFrame(vertex_data)

    seg_df = (
        _silhouette_segments(
            mesh,
            renderer=offscreen.renderer,
            camera=offscreen.renderer.GetActiveCamera(),
            win_size=window_size,
            decimate=sil_decimate,
        )
        if return_silhouette
        else None
    )
    offscreen.close()
    return df, camera_position, seg_df


def _resolve_region_array(mesh, region_array):
    if region_array in mesh.point_data:
        return region_array
    if region_array == "region" and "parcel" in mesh.point_data:
        import warnings

        warnings.warn(
            "Using legacy point-data array 'parcel'; rename it to 'region'.",
            FutureWarning,
            stacklevel=2,
        )
        return "parcel"
    raise KeyError(
        f"{region_array!r} not found in point data. "
        f"Available arrays: {list(mesh.point_data.keys())}. "
        "Choose one with region_array."
    )


def _add_cortex_preview(plotter, surface_paths, opacity):
    """Add FreeSurfer surfaces used only while interactively choosing a camera."""
    if surface_paths is None:
        return
    if isinstance(surface_paths, (str, bytes)):
        surface_paths = [surface_paths]
    else:
        surface_paths = list(surface_paths)
    if not surface_paths:
        return
    if not 0.0 < opacity <= 1.0:
        raise ValueError("preview_opacity must be in the interval (0, 1]")
    for surface_path in surface_paths:
        coords, faces = _read_surface(surface_path)
        faces_pv = np.hstack(
            [np.full((faces.shape[0], 1), 3), faces]
        ).astype(np.int64).ravel()
        cortex = pv.PolyData(coords, faces_pv)
        plotter.add_mesh(
            cortex,
            color="lightgray",
            opacity=opacity,
            show_edges=False,
            pickable=False,
        )


def extract_visible_2d_vtk(
    surface_path,
    region_array="region",
    color_array="color",
    window_size=(800, 600),
    mirror_camera=None,
    return_silhouette=True,
    sil_decimate=0.0,
    hemisphere=None,
    preview_surface_paths=None,
    preview_opacity=0.1,
    keep_z_coord=False,
):
    """Visible-vertex extractor for generic VTK or VTP surface files."""
    mesh = pv.read(surface_path)

    if mesh.n_points == 0 or mesh.n_cells == 0:
        raise ValueError(f"{surface_path!r} does not look like a surface mesh.")

    region_array = _resolve_region_array(mesh, region_array)
    labels = mesh.point_data[region_array]
    if labels.ndim != 1:
        raise ValueError(
            f"region_array={region_array!r} must have one component per point; "
            f"its shape is {labels.shape}."
        )
    if np.issubdtype(labels.dtype, np.integer):
        labels = labels.astype(str)
    if labels.dtype.type is np.bytes_:
        labels = labels.astype(str)

    if color_array and color_array in mesh.point_data:
        colors = mesh.point_data[color_array]
        if colors.ndim == 2 and colors.shape[1] == 3:
            colors = np.asarray(
                ["#{:02x}{:02x}{:02x}".format(*color.astype(int)) for color in colors]
            )
    else:
        import matplotlib as mpl

        unique_labels = np.unique(labels)
        cmap = mpl.colormaps["tab20"].resampled(len(unique_labels))
        lookup = {
            label: mpl.colors.to_hex(cmap(i), keep_alpha=False)
            for i, label in enumerate(unique_labels)
        }
        colors = np.vectorize(lookup.__getitem__)(labels)

    mesh.point_data["region"] = labels
    mesh.point_data["color"] = colors
    mesh.point_data["pid"] = np.arange(mesh.n_points)

    plotter = None
    if mirror_camera is None:
        plotter = pv.Plotter(window_size=window_size)
        _add_cortex_preview(plotter, preview_surface_paths, preview_opacity)
        plotter.add_mesh(
            mesh,
            scalars=labels,
            show_edges=False,
            cmap="tab20",
            show_scalar_bar=False,
            silhouette={"color": "black"},
        )

    camera_position = _finalize_camera(mirror_camera, hemisphere, plotter=plotter)

    offscreen = pv.Plotter(off_screen=True, window_size=window_size)
    offscreen.add_mesh(mesh)
    offscreen.camera_position = camera_position
    offscreen.renderer.GetRenderWindow().Render()

    visible_ids = _visible_ids(mesh, offscreen.renderer)
    visible_mask = np.zeros(mesh.n_points, dtype=bool)
    visible_mask[visible_ids] = True
    projected = _project_2d(
        mesh, offscreen.renderer, window_size, keep_z=keep_z_coord
    )

    seg_df = (
        _silhouette_segments(
            mesh,
            renderer=offscreen.renderer,
            camera=offscreen.renderer.GetActiveCamera(),
            win_size=window_size,
            decimate=sil_decimate,
        )
        if return_silhouette
        else None
    )

    vertex_data = dict(
            vertex=np.arange(mesh.n_points)[visible_mask],
            x=projected[visible_mask, 0],
            y=projected[visible_mask, 1],
            region=labels[visible_mask],
            color=colors[visible_mask],
            hemisphere=hemisphere or "",
    )
    if keep_z_coord:
        vertex_data["z"] = projected[visible_mask, 2]
    df = pd.DataFrame(vertex_data)

    offscreen.close()
    return df, camera_position, seg_df


def extract_visible_2d_vtk_wo_lab(
    surface_path,
    region_array="region",
    color_array="color",
    window_size=(800, 600),
    mirror_camera=None,
    return_silhouette=True,
    sil_decimate=0.0,
    hemisphere=None,
    keep_z_coord=False,
):
    """Visible-vertex extractor for meshes that may not include labels."""
    mesh = pv.read(surface_path)

    if mesh.n_points == 0 or mesh.n_cells == 0:
        raise ValueError(f"{surface_path!r} does not look like a surface mesh.")

    if region_array and (region_array in mesh.point_data or
                         (region_array == "region" and "parcel" in mesh.point_data)):
        region_array = _resolve_region_array(mesh, region_array)
        labels = mesh.point_data[region_array]
        if labels.ndim != 1:
            raise ValueError(
                f"region_array={region_array!r} must have one component per point; "
                f"its shape is {labels.shape}."
            )
        if np.issubdtype(labels.dtype, np.integer):
            labels = labels.astype(str)
        if labels.dtype.type is np.bytes_:
            labels = labels.astype(str)
    else:
        labels = np.full(mesh.n_points, "mesh", dtype=str)

    if color_array and color_array in mesh.point_data:
        colors = mesh.point_data[color_array]
        if colors.ndim == 2 and colors.shape[1] == 3:
            colors = np.asarray(
                ["#{:02x}{:02x}{:02x}".format(*color.astype(int)) for color in colors]
            )
    else:
        unique_labels = np.unique(labels)
        if len(unique_labels) == 1:
            colors = np.full(mesh.n_points, "#bdbdbd", dtype=str)
        else:
            import matplotlib as mpl

            cmap = mpl.colormaps["tab20"].resampled(len(unique_labels))
            lookup = {
                label: mpl.colors.to_hex(cmap(i), keep_alpha=False)
                for i, label in enumerate(unique_labels)
            }
            colors = np.vectorize(lookup.__getitem__)(labels)

    mesh.point_data["region"] = labels
    mesh.point_data["color"] = colors
    mesh.point_data["pid"] = np.arange(mesh.n_points)

    plotter = None
    if mirror_camera is None:
        plotter = pv.Plotter(window_size=window_size)
        plotter.add_mesh(
            mesh,
            scalars=labels,
            show_edges=False,
            cmap="tab20",
            show_scalar_bar=False,
            silhouette={"color": "black"},
        )

    camera_position = _finalize_camera(mirror_camera, hemisphere, plotter=plotter)

    offscreen = pv.Plotter(off_screen=True, window_size=window_size)
    offscreen.add_mesh(mesh)
    offscreen.camera_position = camera_position
    offscreen.renderer.GetRenderWindow().Render()

    visible_ids = _visible_ids(mesh, offscreen.renderer)
    visible_mask = np.zeros(mesh.n_points, dtype=bool)
    visible_mask[visible_ids] = True
    projected = _project_2d(
        mesh, offscreen.renderer, window_size, keep_z=keep_z_coord
    )

    seg_df = (
        _silhouette_segments(
            mesh,
            renderer=offscreen.renderer,
            camera=offscreen.renderer.GetActiveCamera(),
            win_size=window_size,
            decimate=sil_decimate,
        )
        if return_silhouette
        else None
    )

    vertex_data = dict(
            vertex=np.arange(mesh.n_points)[visible_mask],
            x=projected[visible_mask, 0],
            y=projected[visible_mask, 1],
            region=labels[visible_mask],
            color=colors[visible_mask],
            hemisphere=hemisphere or "",
    )
    if keep_z_coord:
        vertex_data["z"] = projected[visible_mask, 2]
    df = pd.DataFrame(vertex_data)

    offscreen.close()
    return df, camera_position, seg_df
