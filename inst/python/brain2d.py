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
    """Return parcel names and colors per vertex, preserving unlabeled vertices."""
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


def _finalize_camera(mirror_camera, hemisphere, plotter=None):
    if mirror_camera is None:
        if plotter is None:
            raise ValueError("plotter is required when mirror_camera is None")
        plotter.show()
        camera_position = plotter.camera_position
        plotter.close()
        return camera_position

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
):
    """Return visible vertices from a FreeSurfer surface projected to 2D."""
    del sil_spline_subdiv

    coords, faces = nib.freesurfer.read_geometry(surf_path)
    faces_pv = np.hstack([np.full((faces.shape[0], 1), 3), faces]).astype(np.int64).ravel()
    mesh = pv.PolyData(coords, faces_pv)

    names, colors = _read_annot(annot_path)
    mesh["parcel"] = names
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
    xy = _project_2d(mesh, offscreen.renderer, window_size)

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

    df = pd.DataFrame(
        dict(
            vertex=np.arange(mesh.n_points)[visible_mask],
            x=xy[visible_mask, 0],
            y=xy[visible_mask, 1],
            parcel=mesh["parcel"][visible_mask],
            color=mesh["color"][visible_mask],
            hemisphere=hemisphere,
        )
    )

    offscreen.close()
    return df, camera_position, seg_df


def extract_visible_2d_vtk(
    surface_path,
    label_array="parcel",
    color_array="color",
    window_size=(800, 600),
    mirror_camera=None,
    return_silhouette=True,
    sil_decimate=0.0,
    hemisphere=None,
):
    """Visible-vertex extractor for generic VTK or VTP surface files."""
    mesh = pv.read(surface_path)

    if mesh.n_points == 0 or mesh.n_cells == 0:
        raise ValueError(f"{surface_path!r} does not look like a surface mesh.")

    if label_array not in mesh.point_data:
        raise KeyError(
            f"{label_array!r} not found in point data. Available arrays: {list(mesh.point_data.keys())}"
        )

    labels = mesh.point_data[label_array]
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

    mesh.point_data["parcel"] = labels
    mesh.point_data["color"] = colors
    mesh.point_data["pid"] = np.arange(mesh.n_points)

    plotter = None
    if mirror_camera is None:
        plotter = pv.Plotter(window_size=window_size)
        plotter.add_mesh(mesh, scalars=labels, show_edges=False, cmap="tab20", silhouette={"color": "black"})

    camera_position = _finalize_camera(mirror_camera, hemisphere, plotter=plotter)

    offscreen = pv.Plotter(off_screen=True, window_size=window_size)
    offscreen.add_mesh(mesh)
    offscreen.camera_position = camera_position
    offscreen.renderer.GetRenderWindow().Render()

    visible_ids = _visible_ids(mesh, offscreen.renderer)
    visible_mask = np.zeros(mesh.n_points, dtype=bool)
    visible_mask[visible_ids] = True
    xy = _project_2d(mesh, offscreen.renderer, window_size)

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

    df = pd.DataFrame(
        dict(
            vertex=np.arange(mesh.n_points)[visible_mask],
            x=xy[visible_mask, 0],
            y=xy[visible_mask, 1],
            parcel=labels[visible_mask],
            color=colors[visible_mask],
            hemisphere=hemisphere or "",
        )
    )

    offscreen.close()
    return df, camera_position, seg_df


def extract_visible_2d_vtk_wo_lab(
    surface_path,
    label_array="parcel",
    color_array="color",
    window_size=(800, 600),
    mirror_camera=None,
    return_silhouette=True,
    sil_decimate=0.0,
    hemisphere=None,
):
    """Visible-vertex extractor for meshes that may not include labels."""
    mesh = pv.read(surface_path)

    if mesh.n_points == 0 or mesh.n_cells == 0:
        raise ValueError(f"{surface_path!r} does not look like a surface mesh.")

    if label_array and label_array in mesh.point_data:
        labels = mesh.point_data[label_array]
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

    mesh.point_data["parcel"] = labels
    mesh.point_data["color"] = colors
    mesh.point_data["pid"] = np.arange(mesh.n_points)

    plotter = None
    if mirror_camera is None:
        plotter = pv.Plotter(window_size=window_size)
        plotter.add_mesh(mesh, scalars=labels, show_edges=False, cmap="tab20", silhouette={"color": "black"})

    camera_position = _finalize_camera(mirror_camera, hemisphere, plotter=plotter)

    offscreen = pv.Plotter(off_screen=True, window_size=window_size)
    offscreen.add_mesh(mesh)
    offscreen.camera_position = camera_position
    offscreen.renderer.GetRenderWindow().Render()

    visible_ids = _visible_ids(mesh, offscreen.renderer)
    visible_mask = np.zeros(mesh.n_points, dtype=bool)
    visible_mask[visible_ids] = True
    xy = _project_2d(mesh, offscreen.renderer, window_size)

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

    df = pd.DataFrame(
        dict(
            vertex=np.arange(mesh.n_points)[visible_mask],
            x=xy[visible_mask, 0],
            y=xy[visible_mask, 1],
            parcel=labels[visible_mask],
            color=colors[visible_mask],
            hemisphere=hemisphere or "",
        )
    )

    offscreen.close()
    return df, camera_position, seg_df
