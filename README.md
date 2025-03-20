# STRENGTHEN: EEG Source Reconstruction Pipeline

## Overview

STRENGTHEN is a MATLAB-based pipeline for EEG source reconstruction using Brainstorm. It processes EEG data to identify the neural sources of brain activity, with a focus on slow wave analysis. The pipeline automates several steps including anatomy import, BEM surface generation, channel location correction, noise covariance computation, head model creation, and sLORETA source estimation.

## Dependencies

- **MATLAB**: Tested with MATLAB R2019b or newer
- **Brainstorm**: An open-source application dedicated to MEG/EEG analysis ([Download Brainstorm](https://neuroimage.usc.edu/brainstorm/))
- **EEGLAB**: For EEG data preprocessing (used for file formats)

## Directory Structure

The pipeline expects the following directory structure:

```
STRENGTHEN/
├── Assets/
│   └── 256_net_temp.xyz       # EEG electrode template file (256 channels)
├── Structural/
│   └── m2m_XXX/               # FreeSurfer-formatted anatomical data
└── EEG_data/
    └── Subject_XXX/
        └── NightX/
            └── Output/
                └── Slow_Wave/
                    ├── slow_waves/      # Contains .set files for each slow wave
                    └── noise_eeg_data.set  # Noise data for covariance calculation
```

## Main Functions

- `main.m`: Main pipeline script that orchestrates the entire process
- `parseStrengthenPaths.m`: Parses the directory structure to find subjects and nights
- `selectSubjectsNights.m`: Allows user to select specific subjects and nights to process
- `importAnatomy.m`: Imports anatomical data into Brainstorm
- `generateBEM.m`: Generates boundary element model surfaces
- `importMainEEG.m`: Imports EEG data for the negative peak events
- `importNoiseEEG.m`: Imports noise EEG data for covariance calculation
- `computeNoiseCov.m`: Computes noise covariance matrix
- `computeHeadModel.m`: Computes the forward model (head model)
- `OverwriteChannel.m`: Overwrites channel locations with template coordinates
- `runSLORETA.m`: Runs sLORETA source estimation
- Various screenshot and export functions for results visualization

## Setup and Installation

1. Install MATLAB and Brainstorm
2. Clone or download this repository
3. Ensure your data follows the expected directory structure
4. Rename the electrode template file to `256_net_temp.xyz` in the Assets directory

## Usage

1. Start MATLAB and navigate to the STRENGTHEN directory
2. Run the main script:
   ```matlab
   main
   ```
3. When prompted, enter the path to the STRENGTHEN folder
4. Select which subjects and nights to process when prompted
5. The pipeline will process the selected data and generate results in the respective `Output/SourceRecon` directories

## Pipeline Workflow

1. Parse the STRENGTHEN directory structure to identify subjects and nights
2. Allow user to select specific subjects and nights to process
3. For each selected subject:
   - Import anatomical data
   - For each selected night:
     - Import noise EEG data
     - For each slow wave:
       - Import EEG data
       - Overwrite channel locations with template
       - Compute noise covariance
       - Generate BEM surfaces (once per subject)
       - Compute head model (once per subject)
   - Run sLORETA source estimation for all waves
   - Export results as CSV files and screenshots

## Output

For each subject and processed slow wave, the pipeline generates:
- Source reconstruction results in Brainstorm database
- CSV files with scout values
- Screenshots of the source activity
- Channel and noise covariance visualizations
- Log files documenting the processing steps

## Notes

- The pipeline is designed to work with the Brainstorm database structure
- Electrode positions are standardized using the 256-channel template
- The sLORETA method is used for source estimation
- Results are organized by subject and individual slow waves

## Troubleshooting

- Ensure Brainstorm is properly installed and configured
- Check that the data follows the expected directory structure
- Verify that the electrode template file exists in the Assets directory
- Review the log files for any errors or warnings

## Citation

If you use this pipeline in your research, please cite:
- The Brainstorm software: Tadel F, Baillet S, Mosher JC, Pantazis D, Leahy RM. Brainstorm: A User-Friendly Application for MEG/EEG Analysis. Computational Intelligence and Neuroscience, vol. 2011, Article ID 879716, 13 pages, 2011. doi:10.1155/2011/879716
- The sLORETA method: Pascual-Marqui RD. Standardized low-resolution brain electromagnetic tomography (sLORETA): technical details. Methods Find Exp Clin Pharmacol. 2002;24 Suppl D:5-12.