"""Create labelled surface meshes from discrete-label NIfTI images."""

import csv
import os
import warnings

import nibabel as nib
import numpy as np
from scipy.ndimage import (
    binary_closing,
    binary_fill_holes,
    distance_transform_edt,
    gaussian_filter,
    generate_binary_structure,
    label as connected_labels,
    zoom,
)
from scipy.spatial import ConvexHull
from skimage.measure import marching_cubes
from skimage.measure import euler_number
import vtk
from vtk.util.numpy_support import numpy_to_vtk, numpy_to_vtkIdTypeArray, vtk_to_numpy


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


def _surface_from_mask(mask, affine, voxel_smoothing_sigma, upsampling_factor=1):
    if voxel_smoothing_sigma > 0 or upsampling_factor > 1:
        # Padding prevents the distance field and Gaussian kernel from being
        # clipped when a labelled structure approaches an image boundary.
        pad = int(np.ceil(3 * voxel_smoothing_sigma)) + 1
        padded = np.pad(mask, pad, mode="constant", constant_values=False)
        signed_distance = (
            distance_transform_edt(padded)
            - distance_transform_edt(~padded)
        )
        field = signed_distance
        if voxel_smoothing_sigma > 0:
            field = gaussian_filter(
                field,
                sigma=voxel_smoothing_sigma,
                mode="nearest",
            )
        if upsampling_factor > 1:
            field = zoom(
                field,
                zoom=upsampling_factor,
                order=1,
                mode="nearest",
                grid_mode=True,
            )
        if field.min() > 0 or field.max() < 0:
            return None
        vertices, faces, _, _ = marching_cubes(
            field, level=0.0, allow_degenerate=False
        )
        if upsampling_factor > 1:
            vertices = (vertices + 0.5) / upsampling_factor - 0.5
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


def _crop_mask(mask, affine, margin=1):
    occupied = np.argwhere(mask)
    lower = np.maximum(occupied.min(axis=0) - margin, 0)
    upper = np.minimum(occupied.max(axis=0) + margin + 1, mask.shape)
    slices = tuple(slice(int(lo), int(hi)) for lo, hi in zip(lower, upper))
    cropped = mask[slices]
    cropped_affine = np.array(affine, dtype=float, copy=True)
    cropped_affine[:3, 3] = nib.affines.apply_affine(affine, lower)
    return cropped, cropped_affine


def _clean_display_mask(
    mask,
    minimum_component_voxels,
    closing_iterations,
    fill_holes,
):
    structure = generate_binary_structure(3, 1)
    components, count = connected_labels(mask, structure=structure)
    if minimum_component_voxels > 1 and count:
        sizes = np.bincount(components.ravel())
        keep = np.flatnonzero(sizes >= minimum_component_voxels)
        keep = keep[keep != 0]
        mask = np.isin(components, keep)
    if closing_iterations > 0 and np.any(mask):
        mask = binary_closing(
            mask,
            structure=structure,
            iterations=closing_iterations,
        )
    if fill_holes and np.any(mask):
        mask = binary_fill_holes(mask)
    return np.asarray(mask, dtype=bool)


def _spherical_structure(radius, affine):
    voxel_sizes = np.sqrt(np.sum(np.asarray(affine[:3, :3]) ** 2, axis=0))
    extents = np.maximum(np.ceil(radius / voxel_sizes).astype(int), 1)
    axes = [np.arange(-extent, extent + 1) for extent in extents]
    grid = np.meshgrid(*axes, indexing="ij")
    squared_distance = sum(
        (axis * spacing) ** 2 for axis, spacing in zip(grid, voxel_sizes)
    )
    return squared_distance <= radius**2 + np.finfo(float).eps


def _component_tunnels(component):
    filled = binary_fill_holes(component)
    return max(0, 1 - int(euler_number(filled, connectivity=3)))


def _correct_mask_topology(mask, affine, closing_radius, max_closing_radius):
    structure = generate_binary_structure(3, 1)
    components, count = connected_labels(mask, structure=structure)
    corrected = np.zeros_like(mask, dtype=bool)
    tunnels_before = 0
    tunnels_after = 0
    corrected_components = 0

    for component_id in range(1, count + 1):
        component = components == component_id
        component = binary_fill_holes(component)
        initial_tunnels = _component_tunnels(component)
        tunnels_before += initial_tunnels
        candidate = component

        if initial_tunnels > 0:
            radius = closing_radius
            while radius <= max_closing_radius + 1e-9:
                trial = binary_closing(
                    component,
                    structure=_spherical_structure(radius, affine),
                )
                trial = binary_fill_holes(trial)
                if np.any(trial):
                    candidate = trial
                if _component_tunnels(candidate) == 0:
                    corrected_components += 1
                    break
                radius += closing_radius

        tunnels_after += _component_tunnels(candidate)
        corrected |= candidate

    return corrected, {
        "tunnels_before": tunnels_before,
        "tunnels_after": tunnels_after,
        "topology_corrected_components": corrected_components,
    }


def _ellipsoid_from_mask(mask, affine, target_volume):
    indices = np.argwhere(mask)
    coordinates = nib.affines.apply_affine(affine, indices)
    center = coordinates.mean(axis=0)
    if len(coordinates) > 1:
        covariance = np.cov(coordinates, rowvar=False)
        eigenvalues, eigenvectors = np.linalg.eigh(covariance)
        radii = np.sqrt(np.maximum(5 * eigenvalues, 0))
    else:
        eigenvectors = np.eye(3)
        radii = np.zeros(3)

    voxel_sizes = np.linalg.svd(affine[:3, :3], compute_uv=False)
    radii = np.maximum(radii, min(voxel_sizes) / 2)
    ellipsoid_volume = (4 / 3) * np.pi * np.prod(radii)
    if ellipsoid_volume > 0 and target_volume > 0:
        radii *= (target_volume / ellipsoid_volume) ** (1 / 3)

    sphere = vtk.vtkSphereSource()
    sphere.SetRadius(1.0)
    sphere.SetThetaResolution(32)
    sphere.SetPhiResolution(16)
    sphere.Update()

    matrix = vtk.vtkMatrix4x4()
    linear = eigenvectors @ np.diag(radii)
    for row in range(3):
        for column in range(3):
            matrix.SetElement(row, column, linear[row, column])
        matrix.SetElement(row, 3, center[row])
    transform = vtk.vtkTransform()
    transform.SetMatrix(matrix)
    transformed = vtk.vtkTransformPolyDataFilter()
    transformed.SetInputConnection(sphere.GetOutputPort())
    transformed.SetTransform(transform)
    transformed.Update()
    mesh = vtk.vtkPolyData()
    mesh.DeepCopy(transformed.GetOutput())
    return mesh


def _rescale_mesh_volume(mesh, target_volume):
    current_volume = _component_volume(mesh)
    if current_volume <= 0 or target_volume <= 0:
        return mesh
    factor = (target_volume / current_volume) ** (1 / 3)
    center = np.asarray(mesh.GetCenter())
    transform = vtk.vtkTransform()
    transform.Translate(*center)
    transform.Scale(factor, factor, factor)
    transform.Translate(*(-center))
    transformed = vtk.vtkTransformPolyDataFilter()
    transformed.SetInputData(mesh)
    transformed.SetTransform(transform)
    transformed.Update()
    output = vtk.vtkPolyData()
    output.DeepCopy(transformed.GetOutput())
    return output


def _connected_mesh_genus(mesh):
    cells = vtk_to_numpy(mesh.GetPolys().GetData()).reshape(-1, 4)[:, 1:]
    edges = np.vstack((cells[:, [0, 1]], cells[:, [1, 2]], cells[:, [2, 0]]))
    edges.sort(axis=1)
    edge_count = len(np.unique(edges, axis=0))
    characteristic = mesh.GetNumberOfPoints() - edge_count + mesh.GetNumberOfPolys()
    return max(0, int(round((2 - characteristic) / 2)))


def _enforce_mesh_genus_zero(mesh):
    connectivity = vtk.vtkPolyDataConnectivityFilter()
    connectivity.SetInputData(mesh)
    connectivity.SetExtractionModeToAllRegions()
    connectivity.Update()
    append = vtk.vtkAppendPolyData()
    corrected = 0

    for region_id in range(connectivity.GetNumberOfExtractedRegions()):
        extract = vtk.vtkPolyDataConnectivityFilter()
        extract.SetInputData(mesh)
        extract.SetExtractionModeToSpecifiedRegions()
        extract.AddSpecifiedRegion(region_id)
        extract.Update()
        clean = vtk.vtkCleanPolyData()
        clean.SetInputConnection(extract.GetOutputPort())
        clean.Update()
        component = vtk.vtkPolyData()
        component.DeepCopy(clean.GetOutput())

        if _connected_mesh_genus(component) > 0:
            points = vtk_to_numpy(component.GetPoints().GetData())
            hull = ConvexHull(points)
            component = _polydata(points, hull.simplices)
            corrected += 1
        append.AddInputData(component)

    append.Update()
    output = vtk.vtkPolyData()
    output.DeepCopy(append.GetOutput())
    return output, corrected


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

    regions = vtk.vtkStringArray()
    regions.SetName("region")
    regions.SetNumberOfValues(n_points)
    for index in range(n_points):
        regions.SetValue(index, name)

    n_cells = mesh.GetNumberOfCells()
    cell_labels = vtk.vtkIntArray()
    cell_labels.SetName("label")
    cell_labels.SetNumberOfValues(n_cells)
    cell_labels.Fill(label)

    cell_regions = vtk.vtkStringArray()
    cell_regions.SetName("region")
    cell_regions.SetNumberOfValues(n_cells)
    for index in range(n_cells):
        cell_regions.SetValue(index, name)

    mesh.GetPointData().AddArray(point_labels)
    mesh.GetPointData().AddArray(regions)
    mesh.GetCellData().AddArray(cell_labels)
    mesh.GetCellData().AddArray(cell_regions)


def _write_combined_mesh(append, output_file):
    append.Update()
    combined = vtk.vtkPolyData()
    combined.DeepCopy(append.GetOutput())

    writer = vtk.vtkXMLPolyDataWriter()
    writer.SetFileName(output_file)
    writer.SetInputData(combined)
    writer.SetDataModeToBinary()
    if writer.Write() != 1:
        raise OSError(f"Failed to write surface mesh: {output_file}")
    return combined


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
        # Some distributed label maps have been intensity-rescaled while being
        # resampled, leaving one non-integer value per original integer label.
        # Recover those labels only when every non-background value maps
        # one-to-one onto the supplied lookup. This deliberately excludes
        # genuinely continuous or probabilistic images.
        names = _read_lookup(lookup_path)
        observed = np.unique(finite[finite != 0])
        rounded = np.rint(observed).astype(np.int64)
        recoverable = (
            bool(names)
            and observed.size == np.unique(rounded).size
            and all(int(label) in names for label in rounded)
            and np.all(np.abs(observed - rounded) < 0.5)
        )
        if not recoverable:
            raise ValueError("NIfTI image must contain discrete integer labels")
        warnings.warn(
            "Recovering intensity-rescaled discrete labels using the lookup table.",
            stacklevel=2,
        )
    # Use the validated integer representation below as exact equality against
    # a float label can otherwise miss values such as 10.999999.
    data = np.rint(data)

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
                f"No {hemisphere} hemisphere labels could be inferred from region names"
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
                "region": region_name,
                "vertices": mesh.GetNumberOfPoints(),
                "faces": mesh.GetNumberOfPolys(),
                "removed_components": removed_components,
            }
        )

    if not summary:
        raise ValueError("No surfaces passed the component size thresholds")

    combined = _write_combined_mesh(append, output_file)

    return {
        "output_file": output_file,
        "regions": summary,
        "vertices": combined.GetNumberOfPoints(),
        "faces": combined.GetNumberOfPolys(),
    }


def nifti_files_to_surface(
    nifti_paths,
    output_file,
    lookup_path=None,
    labels=None,
    mask_threshold=0.5,
    reduction=0.0,
    subdivision=0,
    voxel_smoothing_sigma=0.0,
    smoothing_method="windowed_sinc",
    smoothing_iterations=0,
    smoothing_factor=0.1,
    minimum_vertices=4,
    minimum_volume=0.01,
    surface_style="faithful",
    minimum_component_voxels=2,
    closing_iterations=1,
    fill_voxel_holes=True,
    distance_upsampling=2,
    preserve_volume=True,
    small_region_method="ellipsoid",
    small_region_threshold=20,
    topology_correction="none",
    closing_radius=1.0,
    max_closing_radius=2.0,
    overwrite=False,
):
    """Combine standalone binary/probabilistic NIfTI region masks into VTP."""
    paths = [os.path.abspath(os.fspath(path)) for path in nifti_paths]
    if not paths:
        raise ValueError("No NIfTI files were supplied")
    missing = [path for path in paths if not os.path.isfile(path)]
    if missing:
        raise FileNotFoundError(f"NIfTI file not found: {missing[0]}")
    output_file = os.path.abspath(os.fspath(output_file))
    if not output_file.lower().endswith(".vtp"):
        raise ValueError("output_file must have a .vtp extension")
    if os.path.exists(output_file) and not overwrite:
        raise FileExistsError(
            f"Output already exists: {output_file}. Set overwrite=True to replace it."
        )
    if not np.isfinite(mask_threshold):
        raise ValueError("mask_threshold must be finite")
    if not 0 <= reduction < 1:
        raise ValueError("reduction must be in the interval [0, 1)")
    subdivision = int(subdivision)
    smoothing_iterations = int(smoothing_iterations)
    minimum_vertices = int(minimum_vertices)
    smoothing_method = str(smoothing_method).lower()
    if subdivision < 0 or subdivision > 3:
        raise ValueError("subdivision must be an integer between 0 and 3")
    if reduction > 0 and subdivision > 0:
        raise ValueError("Use either reduction or subdivision, not both")
    if voxel_smoothing_sigma < 0:
        raise ValueError("voxel_smoothing_sigma must be non-negative")
    if smoothing_method not in ("windowed_sinc", "laplacian"):
        raise ValueError("smoothing_method must be 'windowed_sinc' or 'laplacian'")
    if smoothing_iterations < 0:
        raise ValueError("smoothing_iterations must be non-negative")
    if not 0 < smoothing_factor <= 1:
        raise ValueError("smoothing_factor must be in the interval (0, 1]")
    if minimum_vertices < 4:
        raise ValueError("minimum_vertices must be at least 4")
    if minimum_volume < 0:
        raise ValueError("minimum_volume must be non-negative")
    surface_style = str(surface_style).lower()
    if surface_style not in ("faithful", "display"):
        raise ValueError("surface_style must be 'faithful' or 'display'")
    minimum_component_voxels = int(minimum_component_voxels)
    closing_iterations = int(closing_iterations)
    distance_upsampling = int(distance_upsampling)
    small_region_method = str(small_region_method).lower()
    small_region_threshold = int(small_region_threshold)
    if minimum_component_voxels < 1:
        raise ValueError("minimum_component_voxels must be positive")
    if closing_iterations < 0:
        raise ValueError("closing_iterations must be non-negative")
    if distance_upsampling < 1 or distance_upsampling > 4:
        raise ValueError("distance_upsampling must be between 1 and 4")
    if small_region_method not in ("mesh", "ellipsoid"):
        raise ValueError("small_region_method must be 'mesh' or 'ellipsoid'")
    if small_region_threshold < 1:
        raise ValueError("small_region_threshold must be positive")
    topology_correction = str(topology_correction).lower()
    if topology_correction not in ("none", "genus0"):
        raise ValueError("topology_correction must be 'none' or 'genus0'")
    if closing_radius <= 0:
        raise ValueError("closing_radius must be positive")
    if max_closing_radius < closing_radius:
        raise ValueError("max_closing_radius must be at least closing_radius")

    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    lookup = _read_lookup(lookup_path)
    name_to_label = {name.lower(): label for label, name in lookup.items()}
    selected = None if labels is None else set(np.asarray(labels, dtype=np.int64).ravel())
    append = vtk.vtkAppendPolyData()
    summary = []

    for fallback_label, path in enumerate(paths, start=1):
        region_name = _atlas_name(path)
        label = name_to_label.get(region_name.lower(), fallback_label)
        if selected is not None and label not in selected:
            continue

        image = nib.load(path)
        data = np.asanyarray(image.dataobj)
        mask = np.isfinite(data) & (data >= mask_threshold)
        if not np.any(mask):
            warnings.warn(
                f"Dropping {region_name!r}: no voxels met mask_threshold={mask_threshold}.",
                stacklevel=2,
            )
            continue
        if surface_style == "display":
            mask = _clean_display_mask(
                mask,
                minimum_component_voxels,
                closing_iterations,
                bool(fill_voxel_holes),
            )
            if not np.any(mask):
                warnings.warn(
                    f"Dropping {region_name!r}: voxel cleanup removed all voxels.",
                    stacklevel=2,
                )
                continue

        voxel_volume = abs(np.linalg.det(image.affine[:3, :3]))
        target_volume = float(mask.sum()) * voxel_volume
        mask, mask_affine = _crop_mask(
            mask,
            image.affine,
            margin=(
                int(np.ceil(max(3 * voxel_smoothing_sigma, max_closing_radius))) + 1
            ),
        )
        topology_stats = {
            "tunnels_before": 0,
            "tunnels_after": 0,
            "topology_corrected_components": 0,
        }
        if surface_style == "display" and topology_correction == "genus0":
            mask, topology_stats = _correct_mask_topology(
                mask,
                mask_affine,
                closing_radius,
                max_closing_radius,
            )
            if topology_stats["tunnels_after"]:
                warnings.warn(
                    f"{region_name!r} retains {topology_stats['tunnels_after']} "
                    f"tunnel(s) after topology correction.",
                    stacklevel=2,
                )
        use_ellipsoid = (
            surface_style == "display"
            and small_region_method == "ellipsoid"
            and int(mask.sum()) < small_region_threshold
        )
        if use_ellipsoid:
            mesh = _ellipsoid_from_mask(mask, mask_affine, target_volume)
            removed_components = 0
        else:
            surface = _surface_from_mask(
                mask,
                mask_affine,
                voxel_smoothing_sigma,
                upsampling_factor=(distance_upsampling if surface_style == "display" else 1),
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
        mesh_topology_corrected = 0
        if surface_style == "display" and topology_correction == "genus0":
            mesh, mesh_topology_corrected = _enforce_mesh_genus_zero(mesh)
        mesh = _process_mesh(
            mesh,
            reduction,
            subdivision,
            smoothing_method,
            smoothing_iterations,
            smoothing_factor,
        )
        if surface_style == "display" and preserve_volume:
            mesh = _rescale_mesh_volume(mesh, target_volume)
        _add_region_data(mesh, int(label), region_name)
        append.AddInputData(mesh)
        summary.append(
            {
                "label": int(label),
                "region": region_name,
                "source_file": path,
                "voxel_count": int(mask.sum()),
                "geometry_method": "ellipsoid" if use_ellipsoid else "mesh",
                **topology_stats,
                "mesh_topology_corrected_components": mesh_topology_corrected,
                "vertices": mesh.GetNumberOfPoints(),
                "faces": mesh.GetNumberOfPolys(),
                "removed_components": removed_components,
            }
        )

    if not summary:
        raise ValueError("No standalone NIfTI masks produced a surface")
    combined = _write_combined_mesh(append, output_file)
    return {
        "output_file": output_file,
        "regions": summary,
        "vertices": combined.GetNumberOfPoints(),
        "faces": combined.GetNumberOfPolys(),
    }
