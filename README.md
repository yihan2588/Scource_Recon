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

Outputs (per subject/Night1):
```
EEG_data/Subject_xxx/Night1/SourceRecon/
    *.csv  (DKT scout averages)
    *_Source.png, *_Mollweide.png, *_SensorCap.png
    *_Channels3D.png, *_NoiseCov*.png
```
A cumulative log is also written to `<STRENGTHEN>/recon_run.log`.

## 2. Comparison Preparation (`group_analysis.m`)

`group_analysis.m` now stops after creating per-stage averages and projecting them to the default anatomy. This ensures the Brainstorm database contains the `_avg` and `_avg_projected` files needed for manual comparisons/visualisation.

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
5. After subject-level processing, the script uses `Assets/group_lookup.json` to identify `Active` vs `SHAM` participants, aggregates their projected files inside Brainstorm’s `Group_analysis` subject, and runs fixed FT cluster-based t-tests for `Stim_vs_Pre` and `Post_vs_Pre` (Stim/Post assigned to Process2a, Pre to Process2b).

After completion the log will state:
```
Projected stage averages are ready. Continue with manual comparison and visualization steps.
```
Continue inside Brainstorm with your preferred manual comparison pipeline (e.g., create arithmetic contrasts, screenshots, or group analyses) using the newly generated `_avg_projected` files.

## Configuration Files

- `Assets/bad_channels_lookup.json` — subject → comma-separated bad channels (E### format) used as defaults by `main.m`.
- `Assets/fiducials_lookup.json` — optional per-subject fiducials used by `importAnatomy`. If a subject is missing, default fiducials are applied.
- `Assets/group_lookup.json` — maps each subject ID to `Active` or `SHAM` for automated group comparisons in `group_analysis.m`.

## Manual Steps (Post-Script)

- Review the exported screenshots and CSV summaries for each stage to verify there are no anomalies (misaligned sensors, empty scouts, etc.).
- Use Brainstorm’s GUIs to build power comparisons, group averages, and contact sheets based on the `_avg_projected` files.

## Logs

- Source reconstruction log: `<STRENGTHEN>/recon_run.log`
- Comparison preparation log: `<STRENGTHEN>/comparison_run.log`

Both logs capture timestamps and high-level status messages to aid troubleshooting.
