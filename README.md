# EEG Source Reconstruction Pipeline

This workspace contains two MATLAB entry points that automate the parts of our Brainstorm-based EEG workflow that can be scripted safely. The intent is to standardise data handling up to the point where manual review is still required.

## Prerequisites

- MATLAB with access to the Brainstorm MATLAB toolbox.
- STRENGTHEN project directory structured as:
  - `Structural/m2m_xxx/` (head models from CAT12 / FreeSurfer)
  - `EEG_data/Subject_xxx/Night1/...` (EEGLAB `.set` files under `Output/Slow_Wave/...`).
  *(Channel templates and lookups live in this repository under `Assets/`.)*
- The repository files added to the MATLAB path (the scripts do this automatically).

## 1. Source Reconstruction (`main.m`)

`main.m` orchestrates anatomy import, channel preparation, and sLORETA inversion for each subject’s Night1 recordings.

### What it does

1. Asks for:
   - Brainstorm code directory (the folder that contains `brainstorm.m`).
   - STRENGTHEN project root.
2. Parses `Structural/` and `EEG_data/` to build the list of available subjects and nights.
3. Loads default bad channels from `Assets/bad_channels_lookup.json` (per-subject list). You can override per night when prompted.
4. For each selected subject (Night1 only):
   - Imports anatomy with fiducials from `fiducials_lookup.json` if present.
   - Generates BEM surfaces once per subject.
   - Imports noise and NegPeak-triggered epochs, overwrites channels using the bundled 256-net template (`Assets/256_net_temp.xyz`), applies bad-channel flags, and projects sensors to the scalp.
   - Computes noise covariance, OpenMEEG head model, and runs sLORETA on each stage (`pre-stim`, `stim`, `post-stim`).
   - Exports scout CSVs and multiple screenshots for each stage into `SourceRecon/` under the night directory.

### Running it

```matlab
main
```

Follow the prompts. When asked for bad channels you may press Enter to accept the defaults loaded from `Assets/bad_channels_lookup.json`.

At the end of the subject-level processing, the script now asks whether you want to launch the automated group analysis. Answering **y** reuses the Brainstorm protocol, STRENGTHEN path, and subject list you already selected, then runs `group_analysis` in non-interactive mode (avg + project, source-space only). Answering **n** keeps the previous manual workflow.

Outputs (per subject/Night1):
```
EEG_data/Subject_xxx/Night1/SourceRecon/
    *.csv  (DKT scout averages)
    *_Source.png, *_Mollweide.png, *_SensorCap.png
    *_Channels3D.png, *_NoiseCov*.png
```
A cumulative log is also written to `<STRENGTHEN>/recon_run.log`.

## 2. Group Analysis & FieldTrip Stats (`group_analysis.m`)

`group_analysis.m` prepares condition-level averages, launches FieldTrip cluster permutation statistics, and now generates post-hoc summaries/plots for every test run. The pipeline is fully scripted so you can go from subject-level averages to group-level reports in one pass.

### Workflow

1. Run the script:
   ```matlab
   group_analysis
   ```
2. Choose execution mode **1** (the only supported option).
3. Select the Brainstorm protocol and subjects to process.
4. For each subject/night, the script:
   - Collects all `sLORETA` results for each stage.
   - Creates `*_avg` files using mean absolute value across trials.
   - Projects those averages to the default anatomy (`*_avg_projected`).
5. After subject-level processing, the script uses `Assets/group_lookup.json` to identify `Active` vs `SHAM` participants, aggregates their projected files inside Brainstorm’s `Group_analysis` subject, and runs FieldTrip cluster-based permutation tests for `Stim_vs_Pre` and `Post_vs_Pre`.

### What’s new in the automated stats step

- **Cluster statistic selection**: The workflow defaults to FieldTrip’s `clusterstatistic = maxsize`, but you can change the default near the top of `group_analysis.m`. The choice is logged for each run so you always know which statistic was used.
- **Permutation distribution plots**: Every FieldTrip stat file now spawns `*_cluster_distribution.png`, which shows the positive/negative null distributions with the observed cluster statistics overlaid. Significant clusters are coloured in green.
- **Cluster summaries**: For each stat file we export `*_cluster_summary.json`, `*_cluster_summary.mat`, and a human-readable `*_cluster_summary.txt`. These reports list cluster p-values, sizes, and atlas overlaps (or scout labels if ROI averages were used), plus centroid coordinates.
- **Structured output tree**: All artefacts are saved under `<STRENGTHEN>/GroupAnalysisOutputs/run_yyyymmdd_HHMMSS/`, making it straightforward to version and compare different analyses. The log file records the run folder along with every generated asset.

### Outputs per statistical contrast

Inside the run directory you will find, for each FieldTrip result (`*.mat` stat file):

- `<statname>_cluster_distribution.png`
- `<statname>_cluster_summary.json`
- `<statname>_cluster_summary.mat`
- `<statname>_cluster_summary.txt`

Each asset is referenced in the log with absolute paths.

### Logs

- Source reconstruction log: `<STRENGTHEN>/recon_run.log`
- Group analysis log: `<STRENGTHEN>/comparison_run.log`

Both logs capture timestamps, parameter choices, and output locations to aid reproducibility.

## Configuration Files

- `Assets/bad_channels_lookup.json` — subject → comma-separated bad channels (E### format) used as defaults by `main.m`.
- `Assets/fiducials_lookup.json` — optional per-subject fiducials used by `importAnatomy`. If a subject is missing, default fiducials are applied.
- `Assets/group_lookup.json` — maps each subject ID to `Active` or `SHAM` for automated group comparisons in `group_analysis.m`.

## Manual Post-Processing

After `group_analysis.m` completes you can dive into Brainstorm for interactive review:

- Inspect the generated plots and summaries to spot interesting clusters quickly.
- Use Brainstorm’s GUI to build additional contrasts or visualisations on top of the `*_avg_projected` files.
- The atlas overlap tables can guide ROI-focused follow-up analyses.

With these additions, the scripted workflow now covers: subject-level averaging, source projection, FieldTrip cluster permutation tests, distribution plots, cluster anatomical summaries, and organised reporting. Adjust the defaults in `group_analysis.m` if you need to tweak FieldTrip parameters for other projects.
