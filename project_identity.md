# Project Identity: Spatial Transcriptomics Mouse Brain Analysis

## Professional Project Identity

**Display Title:** Spatial Transcriptomics Analysis of Mouse Brain Tissue

**Suggested Repo Slug:** `spatial-transcriptomics-mouse-brain`

**Tagline:** Single-cell spatial analysis of mouse brain tissue using Seurat and R

**GitHub Description:** Analysis pipeline for spatial transcriptomics data from mouse brain tissue, featuring quality control, normalization, spatial pattern detection, cell type identification, and visualization using Seurat/R.

---

## Technical Details

**Primary Stack:**
- R (≥4.0)
- Seurat (spatial transcriptomics analysis)
- SpatialExperiment
- ggplot2 (visualization)

**Topics/Keywords:**
- spatial-transcriptomics
- bioinformatics
- single-cell-analysis
- seurat
- r-programming
- mouse-brain
- gene-expression
- computational-biology
- tissue-architecture
- spatial-data-analysis

---

## Problem & Approach

**Problem Solved:**
This project addresses the challenge of understanding spatial gene expression patterns in mouse brain tissue. Traditional single-cell RNA sequencing loses spatial context, while this approach preserves the relationship between gene expression and tissue architecture.

**Approach:**
The pipeline processes 10X Visium spatial transcriptomics data through multiple stages:
1. Data loading and quality control
2. Normalization using SCTransform
3. Dimensionality reduction (PCA, UMAP)
4. Spatial clustering and pattern identification
5. Differential expression analysis
6. Cell type annotation using reference markers
7. Spatial visualization and interpretation

---

## Inputs & Outputs

**Inputs:**
- 10X Visium spatial transcriptomics dataset (mouse brain sections)
- Cell marker reference database (CellMarker)
- Spatial image files and coordinate data

**Outputs:**
- Quality control plots
- Spatial gene expression visualizations
- Cell type annotation maps
- Differential expression results
- Spatially variable gene lists
- Cluster-specific marker genes
- Statistical analysis reports

---

## Current State Assessment

**What works well:**
- Comprehensive analysis pipeline covering all major spatial transcriptomics workflows
- Uses industry-standard Seurat package
- Includes both basic and advanced spatial analysis techniques
- renv.lock provides reproducible environment

**What needs portfolio-ready transformation:**
- Script filename contains author names (assignment artifact)
- Hardcoded absolute Windows path (D:/scb3)
- Assignment metadata in header (course, instructors, matriculation numbers, deadline)
- Interactive user prompts (not suitable for automated/reproducible runs)
- Missing .gitignore file
- README references wrong directory name
- No clear separation of configuration from code

---

## Naming Alignment Plan

**Files to rename:**
- `Ramin_Atiya_project_script.R` → `analysis.R` (or `spatial_analysis.R`)

**Paths to fix:**
- Line 61: `project_dir = "D:/scb3"` → relative path with configurable option
- Line 47 in README: `cd SCB` → `cd .` or proper directory name

**Content to refactor:**
- Remove assignment metadata (lines 1-34)
- Remove interactive prompts or make them optional
- Add configuration section at top for easy customization
- Extract path handling into reusable function

**Structure to add:**
- .gitignore (R-specific)
- data/ directory (with .gitkeep and README)
- results/ directory (with .gitkeep and README)
- Possibly: scripts/ directory if we break up the monolithic script (optional, evaluate later)

---

## Constraints & Principles

**Must preserve:**
- All analytical logic and methodology
- Scientific accuracy and reproducibility
- Output quality and interpretability
- renv environment specification

**Must NOT add:**
- New analytical features
- Different analysis methods
- Additional dependencies beyond what's needed for path handling

**Must improve:**
- Portability (paths work on any OS)
- Reproducibility (no interactive prompts)
- Professional presentation (no assignment traces)
- Documentation clarity
