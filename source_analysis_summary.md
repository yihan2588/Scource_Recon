# Source Analysis Pipeline - Mode 1 Summary

## Overview
The `bst_comparison.m` script implements a comprehensive source analysis pipeline that processes sLORETA (standardized Low Resolution Electromagnetic Tomography) results to understand brain activity changes across experimental stages.

## Analysis Methodology

### 1. Data Averaging
- **Process**: Averages the absolute values of all sLORETA results for each experimental stage
- **Formula**: `mean(abs(sLORETA_data))`
- **Purpose**: Captures overall activity magnitude while removing directional information
- **Stages Analyzed**:
  - `pre-stim`: Baseline brain activity before stimulation
  - `stim`: Brain activity during stimulation
  - `post-stim`: Brain activity after stimulation

### 2. Power Comparison Analysis
- **Process**: Calculates percentage change in power between experimental stages
- **Formula**: `100 × (DataA² - DataB²) / DataB²`
- **Comparisons Performed**:
  - **Stim vs Pre**: `100 × (Stim² - Pre²) / Pre²`
  - **Post vs Stim**: `100 × (Post² - Stim²) / Stim²`
  - **Post vs Pre**: `100 × (Post² - Pre²) / Pre²`

### 3. Mathematical Rationale
- **Squaring the data** (DataA², DataB²) converts the analysis to power domain
- **Power differences** highlight changes in signal strength/intensity
- **Percentage normalization** allows comparison across different baseline levels
- **Positive values** indicate increased activity in condition A vs B
- **Negative values** indicate decreased activity in condition A vs B

## Key Features

### Automated Processing
- Connects to existing Brainstorm protocols
- Processes multiple subjects and experimental nights
- Creates new conditions with comparison results
- Generates comprehensive visualization outputs

### Quality Control
- Validates data availability before processing
- Handles missing files gracefully with warnings
- Maintains detailed logging throughout the process
- Preserves original data while creating new analysis results

### Visualization Output
- **Contact sheet screenshots** for easy comparison
- **Multiple brain orientations** (top, bottom, left internal, right internal)
- **Standardized colormaps** for consistent interpretation
- **Organized file structure** for presentation and analysis

## Clinical/Research Interpretation

### What the Results Show
1. **Stage Averages**: Overall brain activity patterns during each experimental phase
2. **Stim vs Pre**: How stimulation immediately changes brain activity from baseline
3. **Post vs Stim**: How brain activity evolves after stimulation ends
4. **Post vs Pre**: Net cumulative effect of the entire stimulation protocol

### Practical Applications
- **Treatment efficacy**: Measure how brain stimulation affects neural activity
- **Temporal dynamics**: Understand immediate vs. lasting effects of intervention
- **Individual differences**: Compare responses across subjects and sessions
- **Protocol optimization**: Identify optimal stimulation parameters

## Technical Implementation

### Data Flow
1. **Input**: Individual sLORETA source reconstruction files
2. **Processing**: Averaging and power comparison calculations
3. **Output**: New Brainstorm conditions with comparison results
4. **Visualization**: Automated screenshot generation for analysis

### File Organization
```
STRENGTHEN_folder/
├── contact_sheet_stages_comparison/
│   ├── Subject1/
│   │   ├── Night1/
│   │   │   ├── source/
│   │   │   │   ├── top/
│   │   │   │   ├── bottom/
│   │   │   │   ├── left_intern/
│   │   │   │   └── right_intern/
│   │   │   └── sensor/
│   │   └── Night2/
│   └── Subject2/
└── comparison_run.log
```

## Usage in Presentations

### For Scientific Presentations
- Use the visual flow chart to explain methodology
- Show before/after brain maps from the screenshot outputs
- Highlight percentage changes in key brain regions
- Demonstrate statistical significance of observed changes

### For Clinical Reports
- Focus on the practical interpretation of results
- Emphasize the temporal progression (pre → stim → post)
- Use the percentage change values to quantify treatment effects
- Include multiple brain views for comprehensive assessment

## Quality Metrics
- **Data completeness**: All three stages must be available for valid comparison
- **Statistical robustness**: Averaging reduces noise and improves signal-to-noise ratio
- **Reproducibility**: Standardized processing ensures consistent results across sessions
- **Visualization quality**: Multiple orientations provide comprehensive brain coverage
