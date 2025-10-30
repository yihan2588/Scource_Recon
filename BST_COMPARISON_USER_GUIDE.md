# BST Comparison Tool - User Guide

## Overview
The BST Comparison tool is a post-processing pipeline for Brainstorm source reconstruction results. It performs stage-wise comparisons (pre-stimulation, stimulation, post-stimulation) and generates visualization screenshots.

## Prerequisites
- Brainstorm must be installed and accessible
- You must have already run source reconstruction analysis (source_recon) to create processed data
- A STRENGTHEN project directory with your data

## What the Tool Does
1. **Averages** sLORETA results for each experimental stage
2. **Compares** power changes between stages using the formula: (A²-B²)/B² × 100%
3. **Generates** comparison conditions for:
   - Stimulation vs. Pre-stimulation
   - Post-stimulation vs. Stimulation  
   - Post-stimulation vs. Pre-stimulation
4. **Creates** contact sheet screenshots of all results

## User Inputs Required

### 1. STRENGTHEN Directory Path
- **What it is**: Path to your main project folder containing Brainstorm data
- **Example**: `/Users/yourname/STRENGTHEN_Project`

### 2. Execution Mode Selection
Choose between two modes:

**Mode 1: Full Comparison Pipeline**
- Runs complete analysis and generates all comparisons
- Recommended for comprehensive analysis

**Mode 2: Screenshot a Single Result**
- Only generates screenshots of existing results
- Use when you want to visualize specific conditions

---

## Mode 1: Full Pipeline Options

### Protocol Selection
- **What it shows**: List of available Brainstorm protocols
- **How to select**: Enter the number corresponding to your protocol
- **Example**:
  ```
  1: STRENGTHEN_EEG_Protocol
  2: Test_Protocol
  Select protocol number (1-2): 1
  ```

### Processing Mode
Choose what type of analysis to perform:

**Option 1: Source space only**
- Analyzes 3D brain source activations
- Generates brain surface visualizations

**Option 2: Sensor space only** 
- Analyzes 2D scalp topographies
- Generates electrode-level maps

**Option 3: Both** (Recommended)
- Performs both source and sensor space analysis
- Most comprehensive option

### Subject Selection
- **What it shows**: List of all subjects in your protocol
- **Selection options**:
  - Enter specific numbers: `1,3,5` (processes subjects 1, 3, and 5)
  - Select all: Choose the "Process All Subjects" option
  - Default: Press Enter to process all subjects

**Example**:
```
1: Subject001
2: Subject002  
3: Subject003
4: Process All Subjects
Enter subject numbers (1,3) or 4 for all [all]: 1,2
```

---

## Mode 2: Single Screenshot Options

### Subject Selection
- **What it shows**: List of subjects in the selected protocol
- **How to select**: Enter the number for one subject

### Condition Selection
- **What it shows**: All available conditions/results for the selected subject
- **How to select**: Enter condition numbers separated by commas
- **Example**: `1,3,5` to screenshot conditions 1, 3, and 5

---

## Output Files

### Screenshots Generated
**Source Space (3D Brain Views)**:
- `top` - Top view of brain
- `bottom` - Bottom view of brain  
- `left_intern` - Left hemisphere internal view
- `right_intern` - Right hemisphere internal view

**Sensor Space (2D Topography)**:
- Scalp topography maps showing electrode-level activity

### File Organization
```
STRENGTHEN_folder/
├── contact_sheet_stages_comparison/
│   └── SubjectName/
│       └── NightName/
│           ├── source/
│           │   ├── top/
│           │   ├── bottom/
│           │   ├── left_intern/
│           │   └── right_intern/
│           └── sensor/
└── single_screenshots/
    └── SubjectName/
        ├── top/
        ├── bottom/
        ├── left_intern/
        └── right_intern/
```

### Log Files
- `comparison_run.log` - Detailed processing log with timestamps

## Tips for Usage

1. **First Time Users**: Start with Mode 1, Option 3 (Both) to get complete analysis
2. **Quick Visualization**: Use Mode 2 when you just need screenshots of existing results
3. **Subject Selection**: Process a few subjects first to verify settings before running all
4. **File Management**: Check the output directories to confirm screenshots are being saved correctly

## Error Handling
- If no protocols are found: Run source_recon first to create processed data
- If subjects are missing: Verify your STRENGTHEN directory path is correct
- If screenshots fail: Check that Brainstorm is properly connected and data exists

## Common Use Cases

**Scenario 1: Complete New Analysis**
1. Select Mode 1
2. Choose "Both" for processing mode  
3. Select all subjects
4. Review generated screenshots in output folders

**Scenario 2: Re-generate Specific Screenshots**
1. Select Mode 2
2. Choose specific subject
3. Select conditions of interest
4. Screenshots saved to single_screenshots folder

**Scenario 3: Source Analysis Only**
1. Select Mode 1
2. Choose "Source space only"
3. Select subjects
4. Faster processing, brain visualizations only
