# BST_COMPARISON User Guide

## Overview

`bst_comparison` is a MATLAB function that performs post-processing analysis on Brainstorm source reconstruction results. It automates the creation of stage averages, statistical comparisons, and publication-ready visualizations for EEG/MEG studies.

## Prerequisites

- **Brainstorm** must be installed and accessible in MATLAB
- **Completed source reconstruction pipeline** with sLORETA results
- **STRENGTHEN project structure** with properly organized data
- **Sufficient disk space** for output images and files

## Quick Start

1. Open MATLAB and navigate to the directory containing `bst_comparison.m`
2. Run: `bst_comparison()`
3. Follow the interactive prompts

## Execution Modes

### Mode 1: Full Comparison Pipeline
**Complete analysis pipeline including averaging, comparisons, and screenshots**

- Averages sLORETA results for each experimental stage
- Projects sources to default anatomy for group analysis
- Performs statistical comparisons between stages
- Generates contact sheet visualizations
- Optional group analysis (Active vs Sham groups)

### Mode 2: Screenshot Single Result
**Generate custom screenshots for specific result files**

- Select individual result files for visualization
- Customize output names and visualization bounds
- Generate contact sheets with user-defined parameters

## Processing Options

### Data Processing Modes
1. **Source space only** - Cortical source analysis and visualizations
2. **Sensor space only** - Scalp topography analysis and visualizations  
3. **Both** - Complete analysis in both source and sensor space

### Group Analysis (Mode 1 Only)
- **Active vs Sham comparison** when multiple subjects are available
- **Within-group averaging** for each experimental condition
- **Between-group statistical comparisons** 

## User Inputs

### Protocol Selection
- Choose from existing Brainstorm protocols
- Protocol must contain completed source reconstruction results

### Subject Selection
- **Individual subjects**: Enter numbers (e.g., `1,3,5`) to select specific subjects
- **All subjects**: Press Enter or select "Process All Subjects"

### Group Analysis Setup (if enabled)
- **Active group**: Enter subject numbers separated by commas (e.g., `102,108,109`)
- **Sham group**: Enter subject numbers separated by commas (e.g., `107,110`)
- Numbers are automatically converted to full subject names (e.g., `102` → `Subject_102`)

### Visualization Parameters
- **Comparison bounds**: Percentage bounds for difference maps (e.g., `50` for ±50%)
- **Custom names**: For Mode 2, specify custom output file names

## Output Structure

### Main Output Directory
```
STRENGTHEN_folder/
├── comparison_run.log                    # Processing log
├── contact_sheet_stages_comparison/      # Main visualization output
│   ├── Subject_XXX/                     # Individual subject results
│   │   └── Night1/
│   │       ├── contact_sheets/          # Stage averages & comparisons
│   │       │   ├── top/                 # Top view contact sheets
│   │       │   ├── bottom/              # Bottom view contact sheets
│   │       │   ├── left_intern/         # Left internal view
│   │       │   └── right_intern/        # Right internal view
│   │       └── sensor/                  # 2D topography results
│   └── GroupAnalysis/                   # Group analysis results
│       ├── Active/                      # Active group results
│       ├── Sham/                        # Sham group results
│       └── ActiveVsSham/                # Between-group comparisons
└── custom_contact_sheets/               # Mode 2 custom outputs
    └── Subject_XXX/
```

### Generated Files

#### Stage Averages
- **Source maps**: `SubjectName_NightName_stage_avg_orientation_contact_sheet.png`
- **Sensor maps**: `SubjectName_NightName_stage_sensor_avg_2D_topo_contact_sheet.png`

#### Comparison Maps  
- **Source comparisons**: `SubjectName_NightName_ComparisonName_orientation_contact_sheet.png`
- **Sensor comparisons**: `SubjectName_NightName_ComparisonName_sensor_2D_topo_contact_sheet.png`

#### Group Analysis
- **Group averages**: `GroupName_NightName_stage_group_avg_orientation_contact_sheet.png`
- **Group comparisons**: `GroupName_NightName_ComparisonName_orientation_contact_sheet.png`
- **Between-group**: `ActiveVsSham_NightName_stage_orientation_contact_sheet.png`

### Comparison Types
1. **Stim vs Pre**: Stimulation compared to pre-stimulation baseline
2. **Post vs Stim**: Post-stimulation compared to stimulation  
3. **Post vs Pre**: Post-stimulation compared to pre-stimulation baseline

## Detailed Workflow

### Mode 1: Full Pipeline

1. **Protocol Setup**
   - Select Brainstorm protocol
   - Choose processing mode (source/sensor/both)
   - Select subjects to process

2. **Group Analysis Configuration** (optional)
   - Enable group analysis for multi-subject studies
   - Define Active and Sham groups using subject numbers
   - Set visualization bounds for difference maps

3. **Individual Subject Processing**
   - Average sLORETA results within each experimental stage
   - Project averaged sources to default anatomy
   - Compute stage-wise comparisons using power difference formula
   - Generate sensor space averages and comparisons (if selected)

4. **Group Analysis** (if enabled)
   - Collect projected files from Group_analysis subject in Brainstorm
   - Average within groups (Active/Sham) for each stage
   - Perform within-group comparisons (pre/stim/post)
   - Execute between-group comparisons (Active vs Sham)

5. **Visualization Generation**
   - Create contact sheet screenshots for all results
   - Apply appropriate colormaps (default for averages, custom for comparisons)
   - Generate multiple viewing angles (top, bottom, left internal, right internal)

### Mode 2: Custom Screenshots

1. **File Selection**
   - Choose specific result files from selected conditions
   - Preview file information before processing

2. **Custom Configuration**
   - Specify custom output names for each file
   - Set percentage bounds for visualization
   - Choose whether to continue or stop after each file

3. **Output Generation**
   - Generate contact sheets with custom parameters
   - Save with user-specified naming convention

## Important Notes

### Data Requirements
- **Completed source reconstruction**: sLORETA results must be available for all selected subjects/conditions
- **Consistent naming**: Subject folders should follow `Subject_XXX` format
- **Stage organization**: Conditions should be organized as `NightX_stage` (e.g., `Night1_pre-stim`)

### Group Analysis Requirements
- **Projected sources**: Individual subjects must have averaged sources projected to default anatomy
- **Group_analysis subject**: Brainstorm automatically creates this when projecting to default anatomy
- **Consistent stages**: All subjects should have the same experimental stages

### Performance Considerations
- **Processing time**: Full pipeline can take several minutes to hours depending on data size
- **Memory usage**: Large datasets may require significant RAM
- **Disk space**: Contact sheets and intermediate files require substantial storage

## Troubleshooting

### Common Issues

**"No sLORETA files found"**
- Verify source reconstruction is complete
- Check condition naming conventions
- Ensure selected subjects have processed data

**"No projected files found in Group_analysis"**
- Run individual subject analysis first (Mode 1 without group analysis)
- Verify sources were projected to default anatomy
- Check that Group_analysis subject exists in Brainstorm

**"Could not find group average files"**
- Ensure group analysis completed successfully
- Verify Active/Sham group definitions are correct
- Check that all group subjects have projected files

**Memory or performance issues**
- Process fewer subjects at once
- Close unnecessary MATLAB variables
- Increase MATLAB memory allocation

### Getting Help

1. **Check the log file**: `comparison_run.log` contains detailed processing information
2. **Verify input data**: Ensure all prerequisites are met
3. **Review Brainstorm protocol**: Check that source reconstruction completed successfully
4. **Test with single subject**: Use Mode 1 with one subject to isolate issues

## Output Interpretation

### Visualization Types
- **Stage averages**: Show baseline brain activity patterns for each experimental phase
- **Difference maps**: Highlight brain regions with significant changes between conditions
- **Group comparisons**: Reveal treatment effects and between-group differences

### Color Scales
- **Stage averages**: Default Brainstorm colormap (absolute values, globally scaled)
- **Comparison maps**: Custom diverging colormap with user-defined bounds (red-blue-white)
- **Percentage values**: Difference maps show percentage change relative to baseline

### Contact Sheet Layout
- **11 time points**: From -50ms to +50ms around peak activation
- **Multiple orientations**: Top, bottom, left internal, right internal views
- **Consistent scaling**: Within each file type for direct comparison

This guide provides comprehensive information for using bst_comparison effectively. For additional support or feature requests, consult the development team or Brainstorm documentation.
