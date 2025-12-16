# Group Analysis Pipeline – Brainstorm Call Validation

## Overview
The source group analysis pipeline now calls the plotting and cluster-summary helpers directly (`plot_cluster_distribution.m`, `summarize_cluster_anatomy.m`). The legacy dispatcher `ft_cluster_helpers.m` remains as a thin shim solely for backwards compatibility with any older code paths. All helper logic resides in the standalone functions.

## Brainstorm process usage audit
The following Brainstorm processes are used in the pipeline. Their option blocks have been checked against the corresponding Brainstorm 24.10 sources to confirm that signatures and option names match the upstream implementation.

| Call site | Process | Purpose | Key options validated |
|-----------|---------|---------|------------------------|
| `group_analysis.m` (stage averaging) | `process_select_files_results` | Select sLORETA results for a subject/condition | `subjectname`, `condition`, `tag`, `outprocesstab` (see `process_select_files_results.m`) |
| `group_analysis.m` (stage averaging) | `process_average` | Mean of selected sLORETA results | `avgtype = 1` (everything), `avg_func = 2` (mean abs), `weighted = 0` (see `process_average.m`) |
| `group_analysis.m` (tagging files) | `process_add_tag` | Append tags to averaged/projection file names | `tag`, `output = 'name'` (see `process_add_tag.m`) |
| `group_analysis.m` (projection) | `process_project_sources` | Project averages to default surface | `headmodeltype = 'surface'` (see `process_project_sources.m`) |
| `group_analysis.m` (cluster statistics) | `process_ft_sourcestatistics` | Cluster-based paired/permutation test | Options: `randomizations`, `statistictype = 1`, `tail = 'one+'`, `correctiontype = 2`, `clusteralpha`, `clusterstatistic`, `minnbchan`, `timewindow` (see `process_ft_sourcestatistics.m`) |
| `build_group_analysis_outputs.m` | Helper pipeline | No Brainstorm processes invoked directly; relies on the local helper implementations |

Each call was cross-referenced with the upstream Brainstorm MATLAB sources under `brainstorm3/toolbox/process/functions/` to ensure that option names and expected value ranges align with the implementation shipped in this repository.

## Helper refactor summary
- `plot_cluster_distribution.m` and `summarize_cluster_anatomy.m` now contain the full plotting/summary logic.
- `ft_cluster_helpers.m` is a dispatcher that forwards legacy calls to the new helpers without adding new functionality.
- `build_group_analysis_outputs.m` and `group_analysis_helpers.m` reference the helpers directly and issue meaningful warnings if a stat file cannot be resolved or a helper raises an exception.

## Next steps
- Run `group_analysis` end-to-end on a protocol once cluster results are available to verify successful generation of PNG, JSON, MAT, and TXT outputs with the new helpers.
- Monitor future Brainstorm updates for signature changes to the validated processes above; update the option blocks if the upstream API evolves.
