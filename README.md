# EEG Source Reconstruction & Analysis

This toolkit automates EEG source localization (sLORETA) and group-level statistical analysis using Brainstorm and FieldTrip.

## 1. Prepare Data Inputs
Your data must follow this exact directory structure:

```
STRENGTHEN/
├── Structural/
│   └── m2m_SubjectID/      # Anatomy from FreeSurfer Recon-all
├── EEG_data/
│   └── Subject_SubjectID/
│       └── NightX/
│           └── Output/
│               └── Slow_Wave/
│                   ├── noise_eeg_data.set   # Baseline recording
│                   └── sw_data/
│                       ├── *_pre-stim.set
│                       ├── *_stim.set
│                       └── *_post-stim.set
```

### Required Assets (in this mapped `Assets/` folder)
- `bad_channels_lookup.json`: List of bad channels (e.g., `["E001", "E055"]`).
- `group_lookup.json`: Maps Subject IDs to groups (e.g., `Active` or `SHAM`).
- `256_net_temp.xyz`: Channel location template.

---

## 2. Run Source Reconstruction
This step imports data, computes head models, runs sLORETA, and exports subject-level results.

1.  **Start specific script**:
    ```matlab
    main
    ```
2.  **Follow Prompts**:
    - Enter path to Brainstorm.
    - Enter path to `STRENGTHEN` folder.
    - Select Subjects/Nights.
    - **Manual Step**: Confirm bad channels for each night (defaults loaded from JSON).
3.  **Outputs**:
    - Location: `EEG_data/Subject_.../NightX/SourceRecon/`
    - Files:
        - `*.csv`: Source activations (Scouts).
        - `*.png`: Source maps, sensor caps, and alignment checks.

---

## 3. Run Statistical Analysis
Perform group-level comparisons (Active vs. SHAM) using cluster permutation tests.

1.  **Start specific script**:
    ```matlab
    group_analysis
    ```
2.  **Configuration**:
    - Select **Mode 1** (Average + Project).
    - Select Protocol and Subjects.
    - Choose statistic type (Default: `maxsum`) and permutations (Auto or >1000).
3.  **Outputs**:
    - Location: `STRENGTHEN/GroupAnalysisOutputs/run_TIMESTAMP/`
    - Files:
        - `*_cluster_distribution.png`: Plots of significant clusters.
        - `*_cluster_summary.txt`: Readable summary of significant regions.
        - `*_cluster_summary.mat/json`: Full statistical results.

## Troubleshooting
- **Missing Protocol**: If `group_analysis` finds no protocol, run `main` first.
- **Directory Errors**: Ensure your `EEG_data` and `Structural` folders strictly match the hierarchy above.
- **Bad Channels**: Use standard formats (e.g., `E123`) in the lookup JSON.
