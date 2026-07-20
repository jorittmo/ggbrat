"""Create labelled surface meshes from discrete-label NIfTI images."""

import csv
import os
import warnings

import nibabel as nib
import numpy as np
from scipy.ndimage import distance_transform_edt, gaussian_filter
from skimage.measure import marching_cubes
import vtk
from vtk.util.numpy_support import numpy_to_vtk, numpy_to_vtkIdTypeArray


def _atlas_name(path):
    name = os.path.basename(os.fspath(path))
    if name.lower().endswith(".nii.gz"):
        return name[:-7]
    return os.path.splitext(name)[0]


def _read_lookup(path):
    if path is None:
        return {}

    with open(path, encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.reader(stream))

    lookup = {}
    for row in rows:
        if len(row) < 2:
            continue
        try:
            label = int(float(row[0].strip()))
        except ValueError:  # Permit a header row.
            continue
        name = row[1].strip()
        if name:
            lookup[label] = name
    return lookup


def _name_hemisphere(name):
    normalized = str(name).strip().lower().replace("-", "_")
    parts = [part for part in normalized.split("_") if part]
    if not parts:
        return None
    if parts[0] in ("left", "lh") or parts[-1] in ("left", "l", "lh"):
        return "left"
    if parts[0] in ("right", "rh") or parts[-1] in ("right", "r", "rh"):
        return "right"
    return None


def _polydata(vertices, faces):
    points = vtk.vtkPoints()
    points.SetData(numpy_to_vtk(vertices.astype(np.float64), deep=True))

    cells = np.column_stack(
        [np.full(len(faces), 3, dtype=np.int64), faces.astype(np.int64)]
    ).ravel()
    polys = vtk.vtkCellArray()
    polys.SetCells(len(faces), numpy_to_vtkIdTypeArray(cells, deep=True))

    mesh = vtk.vtkPolyData()
    mesh.SetPoints(points)
    mesh.SetPolys(polys)
    return mesh


def _surface_from_mask(mask, affine, voxel_smoothing_sigma):
    if voxel_smoothing_sigma > 0:
        # Padding prevents the distance field and Gaussian kernel from being
        # clipped when a labelled structure approaches an image boundary.
        pad = int(np.ceil(3 * voxel_smoothing_sigma)) + 1
        padded = np.pad(mask, pad, mode="constant", constant_values=False)
        signed_distance = (
            distance_transform_edt(padded)
            - distance_transform_edt(~padded)
        )
        field = gaussian_filter(
            signed_distance,
            sigma=voxel_smoothing_sigma,
            mode="nearest",
        )
        if field.min() > 0 or field.max() < 0:
            return None
        vertices, faces, _, _ = marching_cubes(
            field, level=0.0, allow_degenerate=False
        )
        vertices -= pad
    else:
        padded = np.pad(mask, 1, mode="constant", constant_values=False)
        vertices, faces, _, _ = marching_cubes(
            padded.astype(np.uint8), level=0.5, allow_degenerate=False
        )
        vertices -= 1.0

    vertices = nib.affines.apply_affine(affine, vertices)
    if np.linalg.det(affine[:3, :3]) < 0:
        faces = faces[:, ::-1]
    return vertices, faces


def _component_volume(mesh):
    triangles = vtk.vtkTriangleFilter()
    triangles.SetInputData(mesh)
    triangles.Update()
    mass = vtk.vtkMassProperties()
    mass.SetInputConnection(triangles.GetOutputPort())
    mass.Update()
    return abs(mass.GetVolume())


def _filter_small_components(mesh, minimum_vertices, minimum_volume, region_name):
    connectivity = vtk.vtkPolyDataConnectivityFilter()
    connectivity.SetInputData(mesh)
    connectivity.SetExtractionModeToAllRegions()
    connectivity.Update()

    kept = vtk.vtkAppendPolyData()
    kept_count = 0
    removed_count = 0
    for region_id in range(connectivity.GetNumberOfExtractedRegions()):
        component_filter = vtk.vtkPolyDataConnectivityFilter()
        component_filter.SetInputData(mesh)
        component_filter.SetExtractionModeToSpecifiedRegions()
        component_filter.AddSpecifiedRegion(region_id)
        component_filter.Update()

        component = vtk.vtkPolyData()
        component.DeepCopy(component_filter.GetOutput())
        volume = _component_volume(component)
        if (
            component.GetNumberOfPoints() < minimum_vertices
            or volume < minimum_volume
        ):
            removed_count += 1
            warnings.warn(
                f"Dropping small component from {region_name!r}: "
                f"{component.GetNumberOfPoints()} vertices, {volume:.4f} mm^3.",
                stacklevel=2,
            )
            continue
        kept.AddInputData(component)
        kept_count += 1

    if kept_count == 0:
        return None, removed_count
    kept.Update()
    output = vtk.vtkPolyData()
    output.DeepCopy(kept.GetOutput())
    return output, removed_count


def _process_mesh(
    mesh,
    reduction,
    subdivision,
    smoothing_method,
    smoothing_iterations,
    smoothing_factor,
):
    if reduction > 0:
        decimator = vtk.vtkQuadricDecimation()
        decimator.SetInputData(mesh)
        decimator.SetTargetReduction(reduction)
        decimator.Update()
        mesh = decimator.GetOutput()

    if subdivision > 0:
        subdivider = vtk.vtkLinearSubdivisionFilter()
        subdivider.SetInputData(mesh)
        subdivider.SetNumberOfSubdivisions(subdivision)
        subdivider.Update()
        mesh = subdivider.GetOutput()

    if smoothing_iterations > 0:
        if smoothing_method == "laplacian":
            smoother = vtk.vtkSmoothPolyDataFilter()
            smoother.SetInputData(mesh)
            smoother.SetNumberOfIterations(smoothing_iterations)
            smoother.SetRelaxationFactor(smoothing_factor)
            smoother.BoundarySmoothingOff()
            smoother.FeatureEdgeSmoothingOff()
        else:
            smoother = vtk.vtkWindowedSincPolyDataFilter()
            smoother.SetInputData(mesh)
            smoother.SetNumberOfIterations(smoothing_iterations)
            smoother.SetPassBand(smoothing_factor)
            smoother.BoundarySmoothingOff()
            smoother.FeatureEdgeSmoothingOff()
            smoother.NonManifoldSmoothingOn()
            smoother.NormalizeCoordinatesOn()
        smoother.Update()
        mesh = smoother.GetOutput()

    clean = vtk.vtkCleanPolyData()
    clean.SetInputData(mesh)
    clean.Update()
    normals = vtk.vtkPolyDataNormals()
    normals.SetInputConnection(clean.GetOutputPort())
    normals.ComputePointNormalsOn()
    normals.ComputeCellNormalsOn()
    normals.ConsistencyOn()
    normals.AutoOrientNormalsOn()
    normals.SplittingOff()
    normals.Update()

    output = vtk.vtkPolyData()
    output.DeepCopy(normals.GetOutput())
    return output


def _add_region_data(mesh, label, name):
    n_points = mesh.GetNumberOfPoints()
    point_labels = vtk.vtkIntArray()
    point_labels.SetName("label")
    point_labels.SetNumberOfValues(n_points)
    point_labels.Fill(label)

    parcels = vtk.vtkStringArray()
    parcels.SetName("parcel")
    parcels.SetNumberOfValues(n_points)
    for index in range(n_points):
        parcels.SetValue(index, name)

    n_cells = mesh.GetNumberOfCells()
    cell_labels = vtk.vtkIntArray()
    cell_labels.SetName("label")
    cell_labels.SetNumberOfValues(n_cells)
    cell_labels.Fill(label)

    cell_parcels = vtk.vtkStringArray()
    cell_parcels.SetName("parcel")
    cell_parcels.SetNumberOfValues(n_cells)
    for index in range(n_cells):
        cell_parcels.SetValue(index, name)

    mesh.GetPointData().AddArray(point_labels)
    mesh.GetPointData().AddArray(parcels)
    mesh.GetCellData().AddArray(cell_labels)
    mesh.GetCellData().AddArray(cell_parcels)


def nifti_to_surface(
    nifti_path,
    output_file=None,
    lookup_path=None,
    labels=None,
    hemisphere=None,
    reduction=0.0,
    subdivision=0,
    voxel_smoothing_sigma=0.0,
    smoothing_method="windowed_sinc",
    smoothing_iterations=0,
    smoothing_factor=0.1,
    minimum_vertices=4,
    minimum_volume=0.01,
    overwrite=False,
):
    """Convert a discrete-label NIfTI atlas to one labelled VTP mesh.

    Each label is surfaced independently. Components are appended without
    merging their points, so both point and cell metadata remain unambiguous.
    One subdivision level creates four times as many triangles; two levels
    create sixteen times as many.
    """
    nifti_path = os.path.abspath(os.fspath(nifti_path))
    if not os.path.isfile(nifti_path):
        raise FileNotFoundError(f"NIfTI file not found: {nifti_path}")
    if not 0 <= reduction < 1:
        raise ValueError("reduction must be in the interval [0, 1)")
    subdivision = int(subdivision)
    smoothing_iterations = int(smoothing_iterations)
    smoothing_method = str(smoothing_method).lower()
    if subdivision < 0 or subdivision > 3:
        raise ValueError("subdivision must be an integer between 0 and 3")
    if smoothing_iterations < 0:
        raise ValueError("smoothing_iterations must be non-negative")
    if smoothing_method not in ("windowed_sinc", "laplacian"):
        raise ValueError("smoothing_method must be 'windowed_sinc' or 'laplacian'")
    if not 0 < smoothing_factor <= 1:
        raise ValueError("smoothing_factor must be in the interval (0, 1]")
    minimum_vertices = int(minimum_vertices)
    if minimum_vertices < 4:
        raise ValueError("minimum_vertices must be at least 4")
    if minimum_volume < 0:
        raise ValueError("minimum_volume must be non-negative")
    if reduction > 0 and subdivision > 0:
        raise ValueError("Use either reduction or subdivision, not both")
    if voxel_smoothing_sigma < 0:
        raise ValueError("voxel_smoothing_sigma must be non-negative")

    if output_file is None:
        output_file = os.path.join(
            "data", "subcortical", "surfaces", f"{_atlas_name(nifti_path)}.vtp"
        )
    output_file = os.path.abspath(os.fspath(output_file))
    if not output_file.lower().endswith(".vtp"):
        raise ValueError("output_file must have a .vtp extension")
    if os.path.exists(output_file) and not overwrite:
        raise FileExistsError(
            f"Output already exists: {output_file}. Set overwrite=True to replace it."
        )
    os.makedirs(os.path.dirname(output_file), exist_ok=True)

    image = nib.load(nifti_path)
    data = np.asanyarray(image.dataobj)
    finite = data[np.isfinite(data)]
    if finite.size == 0:
        raise ValueError("NIfTI image contains no finite values")
    if not np.allclose(finite, np.rint(finite)):
        raise ValueError("NIfTI image must contain discrete integer labels")

    available = np.unique(np.rint(finite).astype(np.int64))
    available = available[available != 0]
    if labels is None:
        selected = available
    else:
        selected = np.asarray(labels, dtype=np.int64).ravel()
        missing = np.setdiff1d(selected, available)
        if missing.size:
            raise ValueError(f"Labels not present in image: {missing.tolist()}")
    if selected.size == 0:
        raise ValueError("No non-background labels were selected")

    names = _read_lookup(lookup_path)
    if hemisphere is not None:
        hemisphere = str(hemisphere).lower()
        if hemisphere not in ("left", "right"):
            raise ValueError("hemisphere must be None, 'left', or 'right'")
        if not names:
            raise ValueError("lookup_path is required when selecting a hemisphere")
        selected = np.asarray(
            [
                label for label in selected
                if _name_hemisphere(names.get(int(label), "")) == hemisphere
            ],
            dtype=np.int64,
        )
        if selected.size == 0:
            raise ValueError(
                f"No {hemisphere} hemisphere labels could be inferred from parcel names"
            )
    append = vtk.vtkAppendPolyData()
    summary = []

    for label in selected:
        region_name = names.get(int(label), f"label_{int(label)}")
        surface = _surface_from_mask(
            data == label, image.affine, voxel_smoothing_sigma
        )
        if surface is None:
            warnings.warn(
                f"Dropping {region_name!r}: volume smoothing removed its boundary.",
                stacklevel=2,
            )
            continue
        vertices, faces = surface
        mesh = _polydata(vertices, faces)
        mesh, removed_components = _filter_small_components(
            mesh, minimum_vertices, minimum_volume, region_name
        )
        if mesh is None:
            warnings.warn(
                f"Dropping {region_name!r}: no components passed the size thresholds.",
                stacklevel=2,
            )
            continue
        mesh = _process_mesh(
            mesh,
            reduction,
            subdivision,
            smoothing_method,
            smoothing_iterations,
            smoothing_factor,
        )
        _add_region_data(mesh, int(label), region_name)
        append.AddInputData(mesh)
        summary.append(
            {
                "label": int(label),
                "parcel": region_name,
                "vertices": mesh.GetNumberOfPoints(),
                "faces": mesh.GetNumberOfPolys(),
                "removed_components": removed_components,
            }
        )

    if not summary:
        raise ValueError("No surfaces passed the component size thresholds")

    append.Update()
    combined = vtk.vtkPolyData()
    combined.DeepCopy(append.GetOutput())

    writer = vtk.vtkXMLPolyDataWriter()
    writer.SetFileName(output_file)
    writer.SetInputData(combined)
    writer.SetDataModeToBinary()
    if writer.Write() != 1:
        raise OSError(f"Failed to write surface mesh: {output_file}")

    return {
        "output_file": output_file,
        "regions": summary,
        "vertices": combined.GetNumberOfPoints(),
        "faces": combined.GetNumberOfPolys(),
    }
