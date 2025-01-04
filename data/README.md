# Data Directory

This directory contains input datasets for the spatial transcriptomics analysis.

## Required Data

The analysis requires the following datasets:

### 1. Spatial Transcriptomics Data (scbi_p3.zip)

**Source:** `https://icbb-share.s3.eu-central-1.amazonaws.com/single-cell-bioinformatics/scbi_p3.zip`

**Contents:**
- `project_3_dataset/Section_1/` - Mouse brain section 1
  - `V1_Mouse_Brain_Sagittal_Posterior_filtered_feature_bc_matrix.h5`
  - `spatial/` directory with images and coordinates
- `project_3_dataset/Section_2/` - Mouse brain section 2
  - `V1_Mouse_Brain_Sagittal_Posterior_Section_2_filtered_feature_bc_matrix.h5`
  - `spatial/` directory with images and coordinates

**How to obtain:**
- Option 1: Run the analysis script and it will prompt you to download
- Option 2: Manually download and extract to `data/scbi_p3/`
- Option 3: Set environment variable `AUTO_DOWNLOAD=yes` before running

**Expected structure after extraction:**
```
data/
└── scbi_p3/
    └── project_3_dataset/
        ├── Section_1/
        │   ├── V1_Mouse_Brain_Sagittal_Posterior_filtered_feature_bc_matrix.h5
        │   └── spatial/
        └── Section_2/
            ├── V1_Mouse_Brain_Sagittal_Posterior_Section_2_filtered_feature_bc_matrix.h5
            └── spatial/
```

### 2. Cell Marker Database (Cell_marker_All.xlsx)

**Source:** `http://bio-bigdata.hrbmu.edu.cn/CellMarker/CellMarker_download_files/file/Cell_marker_All.xlsx`

**Purpose:** Reference database for cell type annotation

**How to obtain:**
- Option 1: Run the analysis script and it will prompt you to download
- Option 2: Manually download to `data/scbi_p3/Cell_marker_All.xlsx`
- Option 3: Set environment variable `AUTO_DOWNLOAD=yes` before running

**Expected location:**
```
data/scbi_p3/Cell_marker_All.xlsx
```

## Notes

- Data files are large and not included in the repository
- The `.gitignore` file excludes data files from version control
- Downloaded files will be cached locally to avoid re-downloading
