# Spatial Transcriptomics Analysis of Mouse Brain Tissue

**Single-cell spatial analysis of mouse brain tissue using Seurat and R**

## Overview

This project provides a comprehensive analysis pipeline for spatial transcriptomics data from mouse brain tissue. Using 10X Visium technology and the Seurat R package, the pipeline processes spatially-resolved gene expression data to identify cell types, spatial patterns, and tissue architecture features while preserving the native spatial context of the tissue.

## Problem & Approach

**Problem:**  
Traditional single-cell RNA sequencing loses critical spatial information about where cells are located within tissues. Understanding spatial gene expression patterns is essential for comprehending tissue organization, cell-cell interactions, and functional architecture in complex organs like the brain.

**Approach:**  
This pipeline analyzes 10X Visium spatial transcriptomics data through a comprehensive workflow:

1. **Data Loading & Quality Control** - Import spatial gene expression data and assess quality metrics
2. **Preprocessing & Normalization** - Apply SCTransform normalization to account for technical variation
3. **Dimensionality Reduction** - Use PCA and UMAP to identify major patterns in gene expression
4. **Spatial Clustering** - Identify spatially coherent regions with similar expression profiles
5. **Differential Expression Analysis** - Find genes that distinguish different spatial domains
6. **Cell Type Annotation** - Map expression patterns to known cell types using reference markers
7. **Spatial Pattern Analysis** - Identify spatially variable genes and visualize spatial organization
8. **Integration & Interpretation** - Combine multiple tissue sections for comprehensive analysis

## Tech Stack

- **R** (≥4.0)
- **Seurat** - Single-cell and spatial transcriptomics analysis
- **SpatialExperiment** - Spatial data structures
- **ggplot2** - Data visualization
- **patchwork** - Plot composition
- **dplyr** - Data manipulation
- **CellChat** - Cell-cell communication inference
- **SCDC** - Deconvolution analysis
- **renv** - Reproducible environment management

## Repository Structure

```
.
├── analysis.R              # Main analysis pipeline script
├── README.md              # This file
├── renv.lock              # R package dependencies (use renv::restore())
├── data/                  # Input datasets (not tracked in git)
│   ├── README.md          # Data acquisition instructions
│   └── .gitkeep
├── results/               # Analysis outputs (not tracked in git)
│   ├── README.md          # Output description
│   └── .gitkeep
└── .github/
    └── copilot-instructions.md
```

## Setup & Installation

### Prerequisites

- R version ≥4.0
- RStudio (recommended but optional)

### Installation Steps

1. **Clone this repository:**
   ```bash
   git clone https://github.com/Raminyazdani/spatial-transcriptomics-mouse-brain.git
   cd spatial-transcriptomics-mouse-brain
   ```

2. **Install dependencies using renv:**
   
   Open R/RStudio in the project directory and run:
   ```r
   # Install renv if not already installed
   install.packages("renv")
   
   # Restore the project environment from renv.lock
   renv::restore()
   ```

   This will install all required packages with the exact versions used in the original analysis.

   **Alternative (manual installation):**
   If you prefer not to use renv, install packages manually:
   ```r
   install.packages(c("dplyr", "readxl", "Seurat", "jsonlite", "ggplot2", "patchwork"))
   install.packages(c("CellChat", "cluster", "SeuratData", "SCDC"))
   ```

## Data / Inputs

The analysis requires two main datasets that will be automatically downloaded when running the script (or can be manually downloaded):

### 1. Spatial Transcriptomics Data

**Source:** 10X Genomics Visium mouse brain dataset  
**URL:** `https://icbb-share.s3.eu-central-1.amazonaws.com/single-cell-bioinformatics/scbi_p3.zip`

**Contents:**
- Mouse brain sagittal posterior sections (Section 1 and Section 2)
- Gene expression matrices (.h5 format)
- Spatial coordinates and tissue images

**Expected location after download:** `data/scbi_p3/project_3_dataset/`

### 2. Cell Marker Reference Database

**Source:** CellMarker database  
**URL:** `http://bio-bigdata.hrbmu.edu.cn/CellMarker/CellMarker_download_files/file/Cell_marker_All.xlsx`

**Purpose:** Reference markers for cell type annotation

**Expected location:** `data/scbi_p3/Cell_marker_All.xlsx`

### Download Options

**Option 1 - Automatic download (non-interactive):**
```bash
# Set environment variable before running
export AUTO_DOWNLOAD=yes
Rscript analysis.R
```

**Option 2 - Interactive download:**
```bash
# The script will prompt you to download when run
Rscript analysis.R
```

**Option 3 - Manual download:**
Download the files manually from the URLs above and place them in the expected locations as described in `data/README.md`.

## How to Run

### Basic Execution

From the project root directory:

```bash
# Run the complete analysis pipeline
Rscript analysis.R
```

**For Windows users:**
```cmd
Rscript analysis.R
```

### Advanced Options

**Specify custom project directory:**
```bash
export PROJECT_DIR=/path/to/your/project
Rscript analysis.R
```

**Run in R/RStudio interactively:**
```r
# From within R/RStudio, set working directory and source
setwd("/path/to/spatial-transcriptomics-mouse-brain")
source("analysis.R")
```

### Expected Runtime

- **Data download:** 5-10 minutes (depends on connection speed)
- **Complete analysis:** 30-60 minutes (depends on system resources)
- **Memory requirement:** ~10-20 GB RAM recommended

## Outputs

All outputs are saved to the `results/` directory:

### Plots & Visualizations
- `section1_pictures.jpg`, `section2_pictures.jpg` - Spatial feature plots
- `section1_preprocessing_plots.jpg` - Quality control visualizations
- `section1_vilin_plot.jpg` - Distribution plots
- `elbow_section_1.jpg` - PCA elbow plots for dimension selection
- `umap_section_1.jpg` - UMAP dimensionality reduction plots
- `spatial_clusters_section_1.jpg` - Spatial cluster maps
- `astrocytes_distribution_slice1.jpg` - Cell type spatial distributions
- `macrophages_distribution_slice1.jpg` - Cell type spatial distributions

### Data Tables
- Differential expression results (gene markers per cluster)
- Spatially variable gene lists
- Cell type assignments
- Quality control statistics

### R Objects
- Intermediate Seurat objects (can be saved/loaded for further analysis)

See `results/README.md` for detailed output descriptions.

## Reproducibility Notes

- **Environment Management:** This project uses `renv` to ensure reproducible package versions. The `renv.lock` file captures exact package versions.
  
- **Random Seeds:** The analysis uses R's default random number generator. For exact reproducibility, set a seed at the beginning of the script if needed.

- **Paths:** All paths are relative to the project directory and work across different operating systems (Windows, macOS, Linux).

- **Data Versioning:** The analysis uses specific versions of the 10X Visium mouse brain dataset. URLs and file hashes are documented in `data/README.md`.

## Troubleshooting

### Common Issues

**1. Package installation failures**
```
Error: package 'X' is not available
```
**Solution:** Ensure you're using R ≥4.0. Some packages may require Bioconductor:
```r
if (!require("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
BiocManager::install("SpatialExperiment")
```

**2. Memory errors**
```
Error: cannot allocate vector of size X GB
```
**Solution:** The analysis requires substantial memory (10-20 GB). Close other applications or run on a machine with more RAM.

**3. Download failures**
```
Error: timeout reached when downloading
```
**Solution:** Increase timeout setting or download manually:
```r
options(timeout = 600)  # 10 minutes
```

**4. File not found errors**
```
Error: cannot open file 'data/...'
```
**Solution:** Ensure you're running the script from the project root directory:
```bash
cd /path/to/spatial-transcriptomics-mouse-brain
Rscript analysis.R
```

**5. HDF5 file errors**
```
Error: cannot open H5 file
```
**Solution:** Install hdf5r package:
```r
install.packages("hdf5r")
```

### Getting Help

- Check `data/README.md` for data acquisition issues
- Check `results/README.md` for output interpretation
- Review R console messages for specific error locations
- Ensure all dependencies are installed with `renv::restore()`

## Citation

If you use this pipeline in your research, please cite:

- **Seurat:** Hao et al., "Integrated analysis of multimodal single-cell data," Cell (2021)
- **10X Visium:** 10X Genomics Visium Spatial Gene Expression Solution
- **CellMarker:** Zhang et al., "CellMarker: a manually curated resource of cell markers in human and mouse," Nucleic Acids Research (2019)

## License

This project is available for academic and research purposes. See individual package licenses for dependencies.

## Topics

`spatial-transcriptomics` `bioinformatics` `single-cell-analysis` `seurat` `r-programming` `mouse-brain` `gene-expression` `computational-biology` `tissue-architecture` `spatial-data-analysis` `10x-visium` `data-visualization`
