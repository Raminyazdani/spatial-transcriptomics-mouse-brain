# ==========================================
# Spatial Transcriptomics Analysis: Mouse Brain
# ==========================================
#
# Analysis of 10X Visium spatial transcriptomics data from mouse brain tissue.
# This pipeline processes spatial gene expression data to identify cell types,
# spatial patterns, and tissue architecture features.
#
# Date: January 2025
# ==========================================

# ==========================================
# Configuration
# ==========================================

# Environment variables for non-interactive execution:
# - AUTO_DOWNLOAD: Set to "yes" to automatically download required datasets
# - PROJECT_DIR: Override default project directory (defaults to script location)

# Determine project directory (use env var or script location)
if (Sys.getenv("PROJECT_DIR") != "") {
  project_dir <- Sys.getenv("PROJECT_DIR")
} else {
  # Try to get script location, fall back to current working directory
  project_dir <- tryCatch({
    # When sourced, this will get the script directory
    dirname(sys.frame(1)$ofile)
  }, error = function(e) {
    # When run interactively or via Rscript, use current directory
    getwd()
  })
}

message("Project directory: ", project_dir)

# Set up directory structure
data_dir <- file.path(project_dir, "data")
if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
  message("Created data directory: ", data_dir)
}

result_dir <- file.path(project_dir, "results")
if (!dir.exists(result_dir)) {
  dir.create(result_dir, recursive = TRUE)
  message("Created results directory: ", result_dir)
}

# ==========================================
# Package Loading
# ==========================================

# Load required packages
# Note: Use renv::restore() to install all dependencies from renv.lock
suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
  library(Seurat)
  library(jsonlite)
  library(CellChat)
  library(cluster)
  library(SeuratData)
  library(ggplot2)
  library(patchwork)
  library(SCDC)
})

# Increase memory limit for large spatial datasets
options(future.globals.maxSize = 20000 * 1024^2)

# ==========================================
# Data Download and Preparation
# ==========================================

# Check if AUTO_DOWNLOAD environment variable is set
auto_download <- tolower(Sys.getenv("AUTO_DOWNLOAD", "no"))
interactive_mode <- interactive() && auto_download != "yes"

# Function to handle file downloads with user interaction or auto mode
download_with_prompt <- function(url, destfile, description = "file") {
  if (file.exists(destfile)) {
    message(description, " already exists at: ", destfile)
    return(TRUE)
  }
  
  if (auto_download == "yes") {
    message("AUTO_DOWNLOAD=yes: Downloading ", description, "...")
    tryCatch({
      options(timeout = 600)
      download.file(url = url, destfile = destfile, mode = "wb")
      message(description, " downloaded successfully: ", destfile)
      return(TRUE)
    }, error = function(e) {
      message("Error downloading ", description, ": ", e$message)
      message("Please manually download from: ", url)
      message("And place at: ", destfile)
      return(FALSE)
    })
  } else if (interactive_mode) {
    # Interactive prompt
    message(description, " not found at: ", destfile)
    user_input <- readline(prompt = paste0("Download ", description, " automatically? (yes/no/quit): "))
    user_input <- tolower(trimws(user_input))
    
    if (user_input == "quit") {
      stop("User chose to quit.")
    } else if (user_input == "yes") {
      tryCatch({
        options(timeout = 600)
        download.file(url = url, destfile = destfile, mode = "wb")
        message(description, " downloaded successfully: ", destfile)
        return(TRUE)
      }, error = function(e) {
        message("Error downloading ", description, ": ", e$message)
        message("Please manually download and place at: ", destfile)
        return(FALSE)
      })
    } else {
      message("Please manually download ", description, " from:")
      message(url)
      message("And place at: ", destfile)
      return(FALSE)
    }
  } else {
    # Non-interactive mode without AUTO_DOWNLOAD
    message("ERROR: ", description, " not found at: ", destfile)
    message("Please download from: ", url)
    message("Or set AUTO_DOWNLOAD=yes environment variable")
    stop("Required data file missing: ", destfile)
  }
}

# Download main spatial transcriptomics dataset
url_download <- "https://icbb-share.s3.eu-central-1.amazonaws.com/single-cell-bioinformatics/scbi_p3.zip"
downloaded_file <- file.path(project_dir, "scbi_p3.zip")

download_with_prompt(url_download, downloaded_file, "Spatial transcriptomics dataset")

# Unzip the downloaded file into the data folder
unzip_dir <- file.path(data_dir, "scbi_p3")
if (!dir.exists(unzip_dir)) {
  if (file.exists(downloaded_file)) {
    unzip(zipfile = downloaded_file, exdir = unzip_dir)
    message("Data unzipped successfully to: ", unzip_dir)
  } else {
    stop("Cannot unzip: file not found at ", downloaded_file)
  }
} else {
  message("Data already unzipped at: ", unzip_dir)
}

# Download cell marker reference database
destfile <- file.path(unzip_dir, "Cell_marker_All.xlsx")
url <- "http://bio-bigdata.hrbmu.edu.cn/CellMarker/CellMarker_download_files/file/Cell_marker_All.xlsx"

if (file.exists(destfile)) {
  message("Cell marker database already exists. Loading cached version.")
  cell_marker_data <- read_excel(destfile)
} else {
  success <- download_with_prompt(url, destfile, "Cell marker database")
  if (success && file.exists(destfile)) {
    cell_marker_data <- read_excel(destfile)
    message("Cell marker dataset loaded successfully.")
  } else {
    warning("Cell marker dataset is unavailable. Some analyses may be limited.")
    cell_marker_data <- NULL
  }
}

# Verify cell marker data
if (!is.null(cell_marker_data) && nrow(cell_marker_data) > 0) {
  message("Cell marker dataset loaded successfully: ", nrow(cell_marker_data), " entries")
} else {
  warning("Cell marker dataset unavailable or empty. Cell type annotation may be limited.")
}

# ==========================================
# Analysis Section 1: Spatial Transcriptomics Data Exploration
# ==========================================

# Helper function to save plots
save_plot <- function(plot, filename, width = 6, height = 6, dpi = 300) {
  file_name <- file.path(result_dir, filename)
  ggsave(
    filename = file_name,
    plot = plot,
    width = width,
    height = height,
    dpi = dpi
  )
  message("Plot saved as: ", file_name)
}

# 1.1 Properties of the Slides
get_slide_properties <- function(section_path) {
  # Load scalefactors
  scalefactors_path <- file.path(section_path, "spatial", "scalefactors_json.json")
  scalefactors <- fromJSON(scalefactors_path)
  
  # Spot size in microns
  spot_diameter_pixels <- scalefactors$spot_diameter_fullres
  tissue_hires_scalef <- scalefactors$tissue_hires_scalef
  spot_diameter_microns <- spot_diameter_pixels * tissue_hires_scalef
  
  # Load tissue positions
  positions_path <- file.path(section_path, "spatial", "tissue_positions_list.csv")
  tissue_positions <- read.csv(positions_path, header = TRUE)
  colnames(tissue_positions) <- c(
    "barcode", "in_tissue", "array_row", "array_col",
    "pxl_row_in_fullres", "pxl_col_in_fullres"
  )
  
  # Filter out rows with NA coordinates
  tissue_positions_filtered <- tissue_positions %>%
    filter(!is.na(pxl_row_in_fullres) & !is.na(pxl_col_in_fullres))
  
  # Calculate average distance between spots
  coordinates <- tissue_positions_filtered[, c("pxl_row_in_fullres", "pxl_col_in_fullres")]
  if (nrow(coordinates) > 1) {
    distances <- dist(coordinates)  # Euclidean distances
    avg_distance_pixels <- mean(as.numeric(distances))
    avg_distance_microns <- avg_distance_pixels * tissue_hires_scalef
  } else {
    avg_distance_microns <- NA
  }
  
  # Total number of spots
  total_spots <- nrow(tissue_positions_filtered)
  
  # Return a summary as a data frame
  return(data.frame(
    Spot_Size_Microns = spot_diameter_microns,
    Avg_Distance_Microns = ifelse(is.na(avg_distance_microns), "NA", avg_distance_microns),
    Total_Spots = total_spots,
    Section = basename(section_path)
  ))
}

# Apply the function to both sections
mouse_section_1 <- file.path(unzip_dir, "project_3_dataset", "Section_1")
mouse_section_2 <- file.path(unzip_dir, "project_3_dataset", "Section_2")

message("\n=== Slide Properties ===")
results <- bind_rows(
  get_slide_properties(mouse_section_1),
  get_slide_properties(mouse_section_2)
)
print(results)

# 1.2 Resolution Discussion
# The resolution of 10X Genomics Visium technology is approximately 55 microns (spot diameter),
# which is larger than typical eukaryotic cells (10-30 microns). This means each spot captures
# RNA from multiple cells, resulting in averaged expression profiles. While not single-cell
# resolution, this is well-suited for capturing spatial patterns, tissue organization, and
# expression gradients across tissue architecture.

# 1.3 Load Spatial Transcriptomics Data
message("\n=== Loading Spatial Transcriptomics Data ===")

brain_section_1 <- Load10X_Spatial(
  data.dir = mouse_section_1,
  filename = "V1_Mouse_Brain_Sagittal_Posterior_filtered_feature_bc_matrix.h5"
)

brain_section_2 <- Load10X_Spatial(
  data.dir = mouse_section_2,
  filename = "V1_Mouse_Brain_Sagittal_Posterior_Section_2_filtered_feature_bc_matrix.h5"
)

# Section 1 visualization and metadata
message("\n=== Section 1 Overview ===")
spatial_image_1 <- SpatialPlot(brain_section_1)
print(spatial_image_1)

spot_metadata_1 <- head(brain_section_1@meta.data)
print("Spot Metadata for Section 1:")
print(spot_metadata_1)

# Extract and view spatial coordinates for Section 1
coordinates_1 <- GetTissueCoordinates(brain_section_1)
message("Spatial Coordinates for Section 1:")
print(head(coordinates_1))

# Section 2 visualization and metadata
message("\n=== Section 2 Overview ===")
spatial_image_2 <- SpatialPlot(brain_section_2)
print(spatial_image_2)

spot_metadata_2 <- head(brain_section_2@meta.data)
print("Spot Metadata for Section 2:")
print(spot_metadata_2)

# Extract and view spatial coordinates for Section 2
coordinates_2 <- GetTissueCoordinates(brain_section_2)
message("Spatial Coordinates for Section 2:")
print(head(coordinates_2))

# Extract the gene expression matrix for Section 1
gene_expression_matrix_1 <- as.matrix(GetAssayData(brain_section_1, slot = "counts"))
message("Gene Expression Matrix for Section 1 dimensions:")
print(dim(gene_expression_matrix_1))

# Subset the gene expression matrix: first 5 genes and first 5 barcodes
subset_gene_expression_1 <- gene_expression_matrix_1[1:5, 1:5]
print(subset_gene_expression_1)

# Extract the gene expression matrix for Section 2
gene_expression_matrix_2 <- as.matrix(GetAssayData(brain_section_2, slot = "counts"))
message("Gene Expression Matrix for Section 2 dimensions:")
print(dim(gene_expression_matrix_2))

# Subset the gene expression matrix
subset_gene_expression_2 <- gene_expression_matrix_2[1:5, 1:5]
print(subset_gene_expression_2)

# ==========================================
# Analysis Section 2: Seurat Object Inspection
# ==========================================

message("\n=== Inspecting Seurat Objects ===")

# Inspect Section 1
message("### Section 1 ###")
print(brain_section_1)  # Summary of the Seurat object

# Identify where the gene expression data is stored
gene_expression_1 <- GetAssayData(brain_section_1, slot = "counts")
message("Gene expression data dimensions for Section 1:")
print(dim(gene_expression_1))

# Identify where the tissue image data is stored
tissue_image_1 <- brain_section_1@images$slice1
message("Tissue image metadata for Section 1:")
print(tissue_image_1)

# Inspect Section 2
message("### Section 2 ###")
print(brain_section_2)  # Summary of the Seurat object

# Identify where the gene expression data is stored
gene_expression_2 <- GetAssayData(brain_section_2, slot = "counts")
message("Gene expression data dimensions for Section 2:")
print(dim(gene_expression_2))

# Identify where the tissue image data is stored
tissue_image_2 <- brain_section_2@images$slice1
message("Tissue image metadata for Section 2:")
print(tissue_image_2)

# ==========================================
# Analysis Section 3: Feature Visualization
# ==========================================

# Function to randomly select and visualize genes
visualize_random_genes <- function(seurat_object, section_name) {
  # Randomly select two genes from the gene expression matrix
  gene_list <- rownames(seurat_object@assays$Spatial$counts)
  random_genes <- sample(gene_list, 2)
  
  message(paste("Randomly selected genes for", section_name, ":", random_genes[1], "and", random_genes[2]))
  
  # Plot the expression of the first gene
  p1 <- SpatialFeaturePlot(seurat_object, features = random_genes[1], slot = "counts") +
    ggtitle(paste(section_name, "-", random_genes[1]))
  
  # Plot the expression of the second gene
  p2 <- SpatialFeaturePlot(seurat_object, features = random_genes[2], slot = "counts") +
    ggtitle(paste(section_name, "-", random_genes[2]))
  
  # Plot the nFeature_Spatial
  p3 <- SpatialFeaturePlot(seurat_object, features = "nFeature_Spatial") +
    ggtitle(paste(section_name, "-", "nFeature_Spatial"))
  
  # Plot the nCount_Spatial
  p4 <- SpatialFeaturePlot(seurat_object, features = "nCount_Spatial") +
    ggtitle(paste(section_name, "-", "nCount_Spatial"))
  
  # Display the plots
  w_p <- wrap_plots(p1, p2, p3, p4)
  return(w_p)
}

# Visualize random genes for both sections
message("\n=== Visualizing Random Genes ===")
s1_plots <- visualize_random_genes(brain_section_1, "Section 1")
s2_plots <- visualize_random_genes(brain_section_2, "Section 2")

save_plot(s1_plots, "section1_pictures.jpg")
save_plot(s2_plots, "section2_pictures.jpg")

print("Spot Metadata for Section 1:")
print(spot_metadata_1)

# 3. Extract and view spatial coordinates for Section 1
coordinates_1 <- GetTissueCoordinates(brain_section_1)
print("Spatial Coordinates for Section 1:")
print(coordinates_1)

# Section 2
print("### Section 2 ###")

# 1. Display the spatial image for Section 2
spatial_image_2 <- SpatialPlot(brain_section_2)
print(spatial_image_2)

# 2. Extract and view metadata for Section 2 (including spatial coordinates)
spot_metadata_2 <- head(brain_section_2@meta.data)
print("Spot Metadata for Section 2:")
print(spot_metadata_2)

# 3. Extract and view spatial coordinates for Section 2
coordinates_2 <- GetTissueCoordinates(brain_section_2)
print("Spatial Coordinates for Section 2:")
print(coordinates_2)

# 4. Extract the gene expression matrix for Section 1
gene_expression_matrix_1 <- as.matrix(GetAssayData(brain_section_1, slot = "counts"))
print("Gene Expression Matrix for Section 1:")

# Subset the gene expression matrix: all rows (genes) and first 5 columns (barcodes)
subset_gene_expression_1 <- gene_expression_matrix_1[, 1:5]

# Print the subset matrix
print(subset_gene_expression_1)

# 4. Extract the gene expression matrix for Section 1
gene_expression_matrix_2 <- as.matrix(GetAssayData(brain_section_2, slot = "counts"))
print("Gene Expression Matrix for Section 1:")

# Subset the gene expression matrix: all rows (genes) and first 5 columns (barcodes)
subset_gene_expression_2 <- gene_expression_matrix_2[, 1:5]

# Print the subset matrix
print(subset_gene_expression_2)


# ###########################################



################### 2.1 Loading the data ####################################################################
mouse_section_1 <- file.path(unzip_dir, "project_3_dataset", "Section_1")
mouse_section_2 <- file.path(unzip_dir, "project_3_dataset", "Section_2")


# Load spatial transcriptomics data for Section 1
brain_section_1 <- Load10X_Spatial(
  data.dir = mouse_section_1,  # Replace with the actual path to Section_1
  filename = "V1_Mouse_Brain_Sagittal_Posterior_filtered_feature_bc_matrix.h5"
)

# Load spatial transcriptomics data for Section 2
brain_section_2 <- Load10X_Spatial(
  data.dir = mouse_section_2,  # Replace with the actual path to Section_2
  filename = "V1_Mouse_Brain_Sagittal_Posterior_Section_2_filtered_feature_bc_matrix.h5"
)



################### 2.2 Inspecting the Seurat-object ########################################################
# Inspect Section 1
print("### Inspecting Section 1 ###")
print(brain_section_1)  # Summary of the Seurat object

# Identify where the gene expression data is stored
gene_expression_1 <- GetAssayData(brain_section_1, slot = "counts")  # Raw gene expression data
print("Gene expression data for Section 1:")
print(dim(gene_expression_1))  # Dimensions of the expression matrix

# Identify where the tissue image data is stored
tissue_image_1 <- brain_section_1@images$slice1  # Tissue image slot
print("Tissue image metadata for Section 1:")
print(tissue_image_1)  # Summary of the tissue image metadata

# Inspect Section 2
print("### Inspecting Section 2 ###")
print(brain_section_2)  # Summary of the Seurat object

# Identify where the gene expression data is stored
gene_expression_2 <- GetAssayData(brain_section_2, slot = "counts")  # Raw gene expression data
print("Gene expression data for Section 2:")
print(dim(gene_expression_2))  # Dimensions of the expression matrix

# Identify where the tissue image data is stored
tissue_image_2 <- brain_section_2@images$slice1  # Tissue image slot
print("Tissue image metadata for Section 2:")
print(tissue_image_2)  # Summary of the tissue image metadata


################### 2.3 Visualization of a feature ##########################################################
# Define a function to randomly select and visualize two genes
visualize_random_genes <- function(seurat_object, section_name) {
  # Randomly select two genes from the gene expression matrix
  gene_list <- rownames(seurat_object@assays$Spatial$counts)
  random_genes <- sample(gene_list, 2)
  
  # Print the selected genes
  print(paste("Randomly selected genes for", section_name, ":", random_genes[1], "and", random_genes[2]))
  
  # Plot the expression of the first gene
  p1 <- SpatialFeaturePlot(seurat_object, features = random_genes[1],slot="counts") +
    ggtitle(paste(section_name, "-", random_genes[1]))
  
  # Plot the expression of the second gene
  p2 <- SpatialFeaturePlot(seurat_object, features = random_genes[2],slot="counts") +
    ggtitle(paste(section_name, "-", random_genes[2]))
  
  # Plot the nFeature_Spatial
  p3 <- SpatialFeaturePlot(seurat_object, features = "nFeature_Spatial") +
    ggtitle(paste(section_name, "-", "nFeature_Spatial"))
  
  # Plot the nCount_Spatial
  p4 <- SpatialFeaturePlot(seurat_object, features = "nCount_Spatial") +
    ggtitle(paste(section_name, "-", "nCount_Spatial"))
  
  
  # Display the plots
  w_p <- wrap_plots(p1,p2,p3,p4)
  return(w_p)
}

# Visualize random genes for Section 1
s1_plots <- visualize_random_genes(brain_section_1, "Section 1")
# Visualize random genes for Section 2
s2_plots <- visualize_random_genes(brain_section_2, "Section 2")

save_plot(s1_plots,"section1_pictures.jpg")
save_plot(s2_plots,"section2_pictures.jpg")

# ###############################################################


################### 3.1 Filtering ###########################################################################

# Function to calculate mitochondrial percentage and add it to the dataset
calculate_mitochondrial_percentage <- function(data) {
  data[["percent.mt"]] <- PercentageFeatureSet(data, pattern = "^mt-")
  return(data)
}

# Function to plot distributions (gene count, mitochondrial content, etc.)
plot_distributions <- function(data) {
  return (VlnPlot(data, features = c("nFeature_Spatial", "nCount_Spatial", "percent.mt"), ncol = 3))
}

# Function to create scatter plots of feature relationships
plot_feature_relationships <- function(data) {
  p1 <- FeatureScatter(data, feature1 = "nCount_Spatial", feature2 = "nFeature_Spatial")
  p2 <- FeatureScatter(data, feature1 = "nCount_Spatial", feature2 = "percent.mt")
  p3 <- FeatureScatter(data, feature1 = "nFeature_Spatial", feature2 = "percent.mt")
  return(list(p1, p2, p3))
}

# Function to create spatial feature plots
plot_spatial_features <- function(data) {
  p4 <- SpatialFeaturePlot(data, features = "nFeature_Spatial")
  p5 <- SpatialFeaturePlot(data, features = "percent.mt")
  p6 <- SpatialFeaturePlot(data, features = "nCount_Spatial")
  return(list(p4, p5, p6))
}

# Function to combine and display all plots
combine_and_display_plots <- function(plots) {
  return (plots[[1]] + plots[[2]] + plots[[3]] + plots[[4]] + plots[[5]] + plots[[6]])
}


# Now using the functions for section 1

# Step 1: Calculate mitochondrial percentage
brain_section_1 <- calculate_mitochondrial_percentage(brain_section_1)

# Step 2: Visualize distributions
vilin_plot_section_1 <- plot_distributions(brain_section_1)

# Step 3: Plot feature relationships
scatter_plots_1 <- plot_feature_relationships(brain_section_1)

# Step 4: Plot spatial features
spatial_plots_1 <- plot_spatial_features(brain_section_1)

# Step 5: Combine all plots into one display
all_plots_1 <- c(scatter_plots_1, spatial_plots_1)
all_plots_1 <- combine_and_display_plots(all_plots_1)
# add header to plot " section 1" 
all_plots_1 <- all_plots_1 + plot_annotation(title = "Section 1 preprocessing plots")


# Now using the functions for section 2

# Step 1: Calculate mitochondrial percentage
brain_section_2 <- calculate_mitochondrial_percentage(brain_section_2)

# Step 2: Visualize distributions
vilin_plot_section_2 <- plot_distributions(brain_section_2)

# Step 3: Plot feature relationships
scatter_plots_2 <- plot_feature_relationships(brain_section_2)

# Step 4: Plot spatial features
spatial_plots_2 <- plot_spatial_features(brain_section_2)

# Step 5: Combine all plots into one display
all_plots_2 <- c(scatter_plots_1, spatial_plots_2)
all_plots_2 <- combine_and_display_plots(all_plots_2)
# add header to plot " section 2" 
all_plots_2 <- all_plots_1 + plot_annotation(title = "Section 2 preprocessing plots")

# Save the combined plots
save_plot(all_plots_1, "section1_preprocessing_plots.jpg",width = 15, height = 12)
save_plot(all_plots_2, "section2_preprocessing_plots.jpg",width = 15, height = 12)
save_plot(vilin_plot_section_1, "section1_vilin_plot.jpg")
save_plot(vilin_plot_section_2, "section2_vilin_plot.jpg")

# Get the number of features (genes)
number_of_features_section_2_before <- nrow(brain_section_2)
# Get the number of samples (cells)
number_of_samples_section_2_before <- ncol(brain_section_2)


# Get the number of features (genes)
number_of_features_section_1_before <- nrow(brain_section_1)
# Get the number of samples (cells)
number_of_samples_section_1_before <- ncol(brain_section_1)


# Filter Section 1
brain_section_1 <- subset(brain_section_1, 
                    nFeature_Spatial > 200 & 
                      nFeature_Spatial < 7500 & 
                      nCount_Spatial > 500 & 
                      nCount_Spatial < 40000 & 
                      percent.mt < 20)

# Filter Section 2
brain_section_2 <- subset(brain_section_2, 
                    nFeature_Spatial > 200 & 
                      nFeature_Spatial < 7500 & 
                      nCount_Spatial > 500 & 
                      nCount_Spatial < 40000 & 
                      percent.mt < 20)

# Get the number of features (genes)
number_of_features_section_1_after <- nrow(brain_section_1)
# Get the number of samples (cells)
number_of_samples_section_1_after <- ncol(brain_section_1)

# Get the number of features (genes)
number_of_features_section_2_after <- nrow(brain_section_2)
# Get the number of samples (cells)
number_of_samples_section_2_after <- ncol(brain_section_2)

# table before/after/subtract for both section in one table
table_data <- data.frame(
  Section = c("Section 1", "Section 2"),
  Features_Before = c(number_of_features_section_1_before, number_of_features_section_2_before),
  Samples_Before = c(number_of_samples_section_1_before, number_of_samples_section_2_before),
  Features_After = c(number_of_features_section_1_after, number_of_features_section_2_after),
  Samples_After = c(number_of_samples_section_1_after, number_of_samples_section_2_after),
  Features_Subtract = c(number_of_features_section_1_before - number_of_features_section_1_after,
                        number_of_features_section_2_before - number_of_features_section_2_after),
  Samples_Subtract = c(number_of_samples_section_1_before - number_of_samples_section_1_after,
                       number_of_samples_section_2_before - number_of_samples_section_2_after)
)

################### 3.2 Apply SCTransform ###################################################################
# 3.2 SCTransform
# Section 1
brain_section_1 <- SCTransform(brain_section_1, assay = "Spatial", verbose = FALSE)

# Section 2
brain_section_2 <- SCTransform(brain_section_2, assay = "Spatial", verbose = FALSE)


# ##########################



################### 4.1 Dimensionality reduction ############################################################
# Section 1: Apply PCA
brain_section_1 <- RunPCA(brain_section_1, assay = "SCT", verbose = FALSE,npcs = 50)

# Elbow plot for PCA dimensions to choose the number of dimensions
elbow_section_1 <- ElbowPlot(brain_section_1, ndims = 50)

elbow_section_1

# save
save_plot(elbow_section_1,"elbow_section_1.jpg")

pca_sd <- brain_section_1[["pca"]]@stdev

# Calculate the variance explained by each principal component (squared standard deviation)
pca_var <- pca_sd^2

# Calculate the proportion of variance explained by each component
prop_var <- pca_var / sum(pca_var)

# Calculate the cumulative variance explained
cumulative_var <- cumsum(prop_var)

# Choose the threshold for cumulative variance (e.g., 90% of the variance)
threshold <- 0.90

# Find the number of PCs that explain at least the threshold percentage of variance
n_dims <- which(cumulative_var >= threshold)[1]

# Print the optimal number of dimensions (PCs)
print(paste("Optimal number of PCs:", n_dims))


# Choose the number of dimensions based on the elbow plot
n_dims_section_1 <- n_dims  # Adjust based on the elbow plot

# Run UMAP on the chosen number of PCA dimensions
brain_section_1 <- RunUMAP(brain_section_1, dims = 1:n_dims_section_1, verbose = FALSE,reduction = "pca")


# Section 2: Apply PCA
brain_section_2 <- RunPCA(brain_section_2, assay = "SCT", verbose = FALSE,npcs = 50)

# Elbow plot for PCA dimensions to choose the number of dimensions
elbow_section_2 <- ElbowPlot(brain_section_2, ndims = 50)

elbow_section_2

# save
save_plot(elbow_section_2,"elbow_section_2.jpg")

pca_sd <- brain_section_2[["pca"]]@stdev

# Calculate the variance explained by each principal component (squared standard deviation)
pca_var <- pca_sd^2

# Calculate the proportion of variance explained by each component
prop_var <- pca_var / sum(pca_var)

# Calculate the cumulative variance explained
cumulative_var <- cumsum(prop_var)

# Choose the threshold for cumulative variance (e.g., 90% of the variance)
threshold <- 0.90

# Find the number of PCs that explain at least the threshold percentage of variance
n_dims <- which(cumulative_var >= threshold)[1]

# Print the optimal number of dimensions (PCs)
print(paste("Optimal number of PCs:", n_dims))


# Choose the number of dimensions based on the elbow plot
n_dims_section_2 <- n_dims  # Adjust based on the elbow plot

# Run UMAP on the chosen number of PCA dimensions
brain_section_2 <- RunUMAP(brain_section_2, dims = 1:n_dims_section_2, verbose = FALSE,reduction = "pca")

# plot umap in 2d space
umap_plot_section_1 <- DimPlot(brain_section_1, reduction = "umap", label = TRUE)
umap_plot_section_2 <- DimPlot(brain_section_2, reduction = "umap", label = TRUE)

# plot pca in 2d space
pca_plot_section_1 <- DimPlot(brain_section_1, reduction = "pca", label = TRUE)
pca_plot_section_2 <- DimPlot(brain_section_2, reduction = "pca", label = TRUE)

# save plots
save_plot(umap_plot_section_1,"umap_plot_section_1.jpg")
save_plot(umap_plot_section_2,"umap_plot_section_2.jpg")
save_plot(pca_plot_section_1,"pca_plot_section_1.jpg")
save_plot(pca_plot_section_2,"pca_plot_section_2.jpg")


################### 4.2 Clustering ##########################################################################

# Section 1: Find neighbors and clusters based on PCA results
brain_section_1 <- FindNeighbors(brain_section_1, reduction = "pca", dims = 1:n_dims_section_1, verbose = FALSE)
brain_section_1 <- FindClusters(brain_section_1, verbose = FALSE)

# Visualization: UMAP of clusters
p1_section_1 <- DimPlot(brain_section_1, reduction = "umap", label = TRUE)

# Visualization: Spatial plot of clusters on the tissue slide
p2_section_1 <- SpatialDimPlot(brain_section_1, label = TRUE, label.size = 3)

# Combine both UMAP and spatial plots
p1_section_1 + p2_section_1


# Section 2: Find neighbors and clusters based on PCA results
brain_section_2 <- FindNeighbors(brain_section_2, reduction = "pca", dims = 1:n_dims_section_2, verbose = FALSE)
brain_section_2 <- FindClusters(brain_section_2, verbose = FALSE)

# Visualization: UMAP of clusters
p3_section_2 <- DimPlot(brain_section_2, reduction = "umap", label = TRUE)

# Visualization: Spatial plot of clusters on the tissue slide
p4_section_2 <- SpatialDimPlot(brain_section_2, label = TRUE, label.size = 3)

# Combine both UMAP and spatial plots
p3_section_2 + p4_section_2

# save plots
save_plot(p1_section_1,"cluster_umap_section_1.jpg")
save_plot(p2_section_1,"cluster_spatial_section_1.jpg")
save_plot(p3_section_2,"cluster_umap_section_2.jpg")
save_plot(p4_section_2,"cluster_spatial_section_2.jpg")


###############################################################################



# #################################################
################### 5.1 DEG (Differentially Expressed Genes) analysis based on clustering ###################
# Find markers for each cluster
markers <- FindAllMarkers(brain_section_1, 
                          only.pos = TRUE,
                          min.pct = 0.25,
                          logfc.threshold = 0.25)

# Sort and view top markers
significant_markers <- markers %>%
  group_by(cluster) %>%
  slice_max(n = 5, order_by = avg_log2FC)

# Save markers for future use
write.csv(markers, "cluster_markers.csv")

# Visualize top genes
top_genes <- significant_markers %>%
  group_by(cluster) %>%
  slice_max(n = 3, order_by = avg_log2FC) %>%
  pull(gene)

heatmap_section1_top_genes <- DoHeatmap(brain_section_1, features=top_genes)
#save
save_plot(heatmap_section1_top_genes,"heatmap_section1_top_genes_section_1.jpg",width = 16,height = 10)

################### 5.2 DEG analysis based on spatial patterning ########################################
# Identify top 3 spatially variable features for Section 1
spatial_genes <- FindSpatiallyVariableFeatures(
  brain_section_1,
  assay = "SCT",
  selection.method = "moransi",
  features = VariableFeatures(brain_section_1),
  nfeatures = 3,
  verbose =  TRUE 
)

# View the identified spatially variable features
print(spatial_genes)

# Extract names of the top spatially variable genes
top_spatial_genes <- head(VariableFeatures(brain_section_1), 3)

# Plot spatial expression of these genes
spatial_feature_genes_plot <- SpatialFeaturePlot(brain_section_1, features = top_spatial_genes)
spatial_feature_genes_plot
#save
save_plot(spatial_feature_genes_plot,"spatial_feature_genes_plot_section_1.jpg")


# Check if these genes are also differentially expressed between clusters
cluster_markers <- significant_markers %>%
  filter(gene %in% top_spatial_genes)

print(cluster_markers)



# #################################################################

# ###############################################
# Merge datasets

merged_data <- merge(brain_section_1, brain_section_2)

# Process merged data
merged_data <- SCTransform(merged_data, assay = "Spatial") %>%
  RunPCA() %>%
  RunUMAP(dims = 1:19) %>%
  FindNeighbors(dims = 1:19) %>%
  FindClusters(resolution = 0.8)

# Visualization
p1 <- DimPlot(merged_data, reduction = "umap", group.by = "orig.ident", label = TRUE)
p2 <- DimPlot(merged_data, reduction = "umap", group.by = "seurat_clusters", label = TRUE)
merged_umap_plot <-p1 + p2

# Spatial visualization
spatiatl_merged_no_batch_dim_tissue_slice_1 <- SpatialDimPlot(merged_data, images = "slice1", label = TRUE)
spatiatl_merged_no_batch_dim_tissue_slice_2 <-SpatialDimPlot(merged_data, images = "slice1.2", label = TRUE)


#save
save_plot(merged_umap_plot,"merged_umap_plot_not_integrate.jpg")
save_plot(spatiatl_merged_no_batch_dim_tissue_slice_1,"spatiatl_merged_no_batch_dim_tissue_slice_1.jpg")
save_plot(spatiatl_merged_no_batch_dim_tissue_slice_2,"spatiatl_merged_no_batch_dim_tissue_slice_2.jpg")



# ##################################################

# Create object list
object.list <- list(section1 = brain_section_1, section2 = brain_section_2)

# Find integration features
features <- SelectIntegrationFeatures(object.list = object.list)
object.list <- PrepSCTIntegration(object.list = object.list, 
                                  anchor.features = features)

object.list$section1@assays$SCT$counts <- object.list$section1@assays$SCT$counts
object.list$section2@assays$SCT$counts <- object.list$section2@assays$SCT$counts

# Find anchors and integrate
anchors <- FindIntegrationAnchors(object.list = object.list,assay = c("SCT","SCT") ,
                                  normalization.method = "SCT",
                                  dims=1:19,anchor.features = features)

integrated_data <- IntegrateData(anchorset = anchors, 
                                 normalization.method = "SCT",dims=1:19)
integrated_data@assays$integrated$counts <- integrated_data@assays$SCT$counts

# Process integrated data
integrated_data <- RunPCA(integrated_data) %>%
  RunUMAP(dims = 1:19) %>%
  FindNeighbors(dims = 1:19) %>%
  FindClusters(resolution = 0.8)

# Visualization
p3 <- DimPlot(integrated_data, reduction = "umap", 
              group.by = "orig.ident", label = TRUE)
p4 <- DimPlot(integrated_data, reduction = "umap", 
              group.by = "seurat_clusters", label = TRUE)
merged_umap_plot_integrate <-p3 + p4

# save
save_plot(merged_umap_plot_integrate,"merged_umap_plot_integrate.jpg")

# #####################################################

################### 6.3 Detection of Batch-effects ##########################
# Compare mixing of samples
p5 <- DimPlot(merged_data, group.by = "seurat_clusters",,label=T) + 
  ggtitle("Without Integration")
p6 <- DimPlot(integrated_data, group.by = "seurat_clusters" ,label=T) + 
  ggtitle("With Integration")
integration_compaer <- p5 + p6

# save 
save_plot(integration_compaer,"integration_compaer.jpg")

################### Week 3: (17 Points) #####################################################################



# #########################################################



# ####################################
# Download and prepare reference dataset
reference <- readRDS(file.path(unzip_dir,"project_3_dataset", "allen_cortex.rds"))
reference <- UpdateSeuratObject(reference)
reference <- UpdateSCTAssays(reference)
# Process reference data
reference <- SCTransform(reference) %>%
  RunPCA() %>%
  RunUMAP(dims = 1:19)



# Find anchors between reference and spatial data
transfer.anchors <- FindTransferAnchors(
  reference = reference,
  query = integrated_data,
  normalization.method = "SCT",
)

DefaultAssay(integrated_data)

# Transfer labels
predictions <- TransferData(
  anchorset = transfer.anchors,
  refdata = reference$subclass,
  weight.reduction = "pcaproject"
)

# Add predictions to spatial data
integrated_data$predicted.id <- predictions$predicted.id


# Visualization
p1 <- DimPlot(integrated_data, 
              reduction = "umap",
              group.by = "predicted.id",
              label = TRUE) +
  ggtitle("Predicted Cell Types")

# save
save_plot(p1,"automatic_predicted_cell_types.jpg")

# ##############################################################
# Perform DEG analysis
all.markers <- FindAllMarkers(integrated_data,
                              only.pos = TRUE,
                              min.pct = 0.25,
                              logfc.threshold = 0.25)

# random select 3 annotation names from predicted.id
selected_annotations <- c("Astro", "Endo", "Macrophage")

# grep where species is Mouse and tissue_type is brain and cell_name is Astro
Astro_markers <- unique(cell_marker_data %>%
  filter(species == "Mouse" & tissue_type == "Brain"  & grepl("Astrocyte", cell_name))%>% pull(marker))

Endo_markers <- unique(cell_marker_data %>%
  filter(species == "Mouse" & tissue_type == "Brain" & grepl("Endothelial", cell_name))%>% pull(marker))

Macrophage_markers <- unique(cell_marker_data %>% 
  filter(species == "Mouse" & tissue_type == "Brain" & grepl("Macrophage", cell_name) )%>% pull(marker))


# Select top markers
top.markers <- all.markers %>% filter(gene %in% c(Astro_markers, Endo_markers, Macrophage_markers)) %>%
  group_by(cluster) %>%
 top_n(5, avg_log2FC)

# Select the top 2 markers for each group, sorted by avg_log2FC
Astro_markers_integ <- top.markers %>%
  filter(gene %in% Astro_markers) %>%
  arrange(desc(avg_log2FC)) %>%  # Sort by avg_log2FC
  head(2)  # Select the top 2 markers

Astro_markers_integ$group <- "Astrocytes"

Endo_markers_integ <- top.markers %>%
  filter(gene %in% Endo_markers) %>%
  arrange(desc(avg_log2FC)) %>%
  head(2)
Endo_markers_integ$group <- "Endothelial"

Macrophage_markers_integ <- top.markers %>%
  filter(gene %in% Macrophage_markers) %>%
  arrange(desc(avg_log2FC)) %>%
  head(2)
Macrophage_markers_integ$group <- "Macrophages"

# Combine the markers into a single dataframe
selected_markers <- bind_rows(Astro_markers_integ, Endo_markers_integ, Macrophage_markers_integ)

# UMAP visualization of marker genes
marker_plots <- lapply(1:nrow(selected_markers), function(i) {
  # Extract gene, group, and cluster for the current row
  gene <- selected_markers$gene[i]
  group <- selected_markers$group[i]
  cluster <- selected_markers$cluster[i]
  
  # Generate the FeaturePlot for the gene
  FeaturePlot(integrated_data, features = gene) +
    ggtitle(paste(gene, group, sep = " - "))
})


# Spatial visualization of marker genes
spatial_plots_slice_1 <- lapply(1:nrow(selected_markers), function(i) {
  # Extract gene, group, and cluster for the current row
  gene <- selected_markers$gene[i]
  group <- selected_markers$group[i]
  cluster <- selected_markers$cluster[i]
  
  # Generate the SpatialFeaturePlot for the gene
  SpatialFeaturePlot(integrated_data, features = gene, images = "slice1") +
    ggtitle(paste(gene, group, "Slice 1", sep = " - "))
})

# Print the spatial plots for each marker

# Spatial visualization of marker genes
spatial_plots_slice_2 <- lapply(1:nrow(selected_markers), function(i) {
  # Extract gene, group, and cluster for the current row
  gene <- selected_markers$gene[i]
  group <- selected_markers$group[i]
  cluster <- selected_markers$cluster[i]
  
  # Generate the SpatialFeaturePlot for the gene
  SpatialFeaturePlot(integrated_data, features = gene, images = "slice1.2") +
    ggtitle(paste(gene, group, "Slice 2", sep = " - "))
})

# Print the spatial plots for each marker


# Combine plots
marker_combined <- wrap_plots(marker_plots, ncol = 3)
spatial_combined_slice_2 <- wrap_plots(spatial_plots_slice_2,ncol=3)
spatial_combined_slice_1 <- wrap_plots(spatial_plots_slice_1,ncol=3)

marker_combined
spatial_combined_slice_1
spatial_combined_slice_2
selected_markers

# save
save_plot(marker_combined,"manual_predicted_cell_types_markers_umap.jpg",width = 15, height = 12)
save_plot(spatial_combined_slice_1,"manual_spatial_combined_markers_slice_1.jpg")
save_plot(spatial_combined_slice_2,"manual_spatial_combined_markers_slice_2.jpg")

################### 8 Deconvolution (9 Points + 5 Bonus) ####################################################


# ##########################################################################


# #####################################################
# Define the cell types you want to downsample from the integrated dataset
cell_types <- unique(integrated_data$predicted.id)

# Create a list to store downsampled cells for each cell type
downsampled_cells_integrated <- list()

# Downsample to a maximum of 250 cells per cell type in the integrated dataset
for (cell_type in cell_types) {
  # Get cells for the current cell type in the integrated data
  cells_of_type <- WhichCells(integrated_data, expression = predicted.id == cell_type)
  
  # Downsample to 250 cells, or use all if there are fewer than 250
  if (length(cells_of_type)>=2){
  downsampled_cells_integrated[[cell_type]] <- sample(cells_of_type, min(250, length(cells_of_type)))
  }
}

# Create a new Seurat object with the downsampled cells from the integrated data
integrated_data_downsampled <- subset(integrated_data, cells = unlist(downsampled_cells_integrated))

# Check the number of cells per cell type in the downsampled integrated dataset
table(integrated_data_downsampled$predicted.id)

# Step 1: SCTransform
integrated_data_downsampled <- SCTransform(integrated_data_downsampled,assay = "integrated")


# Step 2: PCA
integrated_data_downsampled <- RunPCA(integrated_data_downsampled, verbose = FALSE)

# Elbow plot to determine the number of dimensions for PCA (this will show the explained variance)
ElbowPlot(integrated_data_downsampled, ndims = 50)


# Step 3: UMAP
# Choose the number of dimensions based on the elbow plot or a set number (e.g., 15)
integrated_data_downsampled <- RunUMAP(integrated_data_downsampled, dims = 1:15, verbose = FALSE)

# Step 4: Clustering (using the PCA dimensions)
integrated_data_downsampled <- FindNeighbors(integrated_data_downsampled, dims = 1:15, verbose = FALSE)
integrated_data_downsampled <- FindClusters(integrated_data_downsampled, verbose = FALSE)


# #################################################
# Perform DEG analysis on the reference dataset for each subclass

Idents(reference) <- "subclass"
unique(integrated_data_downsampled$predicted.id)
# Find DEGs for each cell type (subclass) in the reference dataset that are in unique(integrated_data$predicted.id)

deg_results <- FindAllMarkers(reference, only.pos = TRUE, min.pct = 0.25, logfc.threshold = 0.25)

deg_reults_filter <- deg_results %>% filter(cluster %in% unique(integrated_data_downsampled$predicted.id))

spatial_genes <- rownames(GetAssayData(integrated_data_downsampled, slot = "counts"))

# Select the top 20 DEGs for each cell type (subclass) with the lowest p-values

top_deg_per_cell_type <- deg_reults_filter %>% 
  filter(gene %in% spatial_genes)  %>%
  group_by(cluster) %>%
  slice_min(order_by = p_val_adj, n = 20)  # Select top 20 DEGs for each cell type based on p-value



# View selected DEGs
head(top_deg_per_cell_type)

# #################################################
metadata_reference <- reference@meta.data
metadata_reference$predicted.id <- as.factor(metadata_reference$subclass)  # Assign subclass as predicted.id

# Create ExpressionSet for the reference dataset
count_matrix_reference <- GetAssayData(reference, slot = "counts")  # Get the count matrix
reference_exprSet <- ExpressionSet(assayData = as.matrix(count_matrix_reference),
                                   phenoData = AnnotatedDataFrame(metadata_reference))

top_genes <- top_deg_per_cell_type$gene
reference_exprSet_filtered <- reference_exprSet[top_genes, ]


# For the query dataset (spatial)
metadata_query <- integrated_data_downsampled@meta.data
metadata_query$predicted.id <- as.factor(metadata_query$predicted.id)  # Use the existing predicted.id for the query data

# Create ExpressionSet for the query dataset
count_matrix_query <- GetAssayData(integrated_data_downsampled, slot = "data")  # Get the count matrix
query_exprSet <- ExpressionSet(assayData = as.matrix(count_matrix_query),
                               phenoData = AnnotatedDataFrame(metadata_query))



# ##########################################################
table(query_exprSet@phenoData@data$predicted.id)
table(reference_exprSet_filtered@phenoData@data$subclass)


deconv_result <- SCDC_prop(
  bulk.eset = query_exprSet,  # The bulk sample expression set (spatial data)
  sc.eset = reference_exprSet_filtered,  # The single-cell expression set (reference data)
  ct.varname = "predicted.id",  # The column in the metadata containing cell types
  sample = "sample_id",  # If you have sample/subject labels, otherwise use NULL
  ct.sub = unique(query_exprSet$predicted.id),  # Use only the common cell types between reference and query datasets
)

# Check the deconvolution results
head(deconv_result)

# Add deconvolution results to Seurat object as a new assay
integrated_data[["deconvolution"]] <- CreateAssayObject(counts = deconv_result$proportions)

# Use SpatialFeaturePlot to visualize the spatial distribution of these cell types
astro_plot <- SpatialFeaturePlot(integrated_data, features = "VLMC") +
  ggtitle("Astrocytes Distribution")

macro_plot <- SpatialFeaturePlot(integrated_data, features = "Macrophages") +
  ggtitle("Macrophages Distribution")

# Save the plots
save_plot(astro_plot, "astrocytes_distribution_slice1.jpg")
save_plot(macro_plot, "macrophages_distribution_slice1.jpg")


################### Week 4: (8 Points) ######################################################################


# ##########################################################
createCellChat(integrated_data)


################### 10 Bonus: Summary (Max 5P) ##############################################################




