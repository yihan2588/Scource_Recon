# Figure Analysis and Improvement Suggestions

## Areas That Could Be Clearer or Improved

### 1. **Input Section Clarity Issues**

**Unclear Elements:**
- The relationship between the "5s non-SW, pre-stimulation baseline EEG recording" and the "100 ms EEG epoch centered around the negative peak" is not visually clear
- The timeline/temporal relationship between baseline recording and slow wave detection is ambiguous
- The MRI and EEG electrode positions appear disconnected from the EEG signal processing

**Suggestions:**
- Add a timeline showing the temporal sequence: baseline recording → slow wave detection → epoch extraction
- Show how the baseline and epoch data are used differently in the pipeline
- Add arrows or connections showing how MRI and electrode positions feed into the coregistration step

### 2. **Processing Pipeline Technical Accuracy**

**Potential Issues:**
- Step order may not perfectly match the actual implementation (BEM surfaces are typically generated before noise covariance in practice)
- The forward model computation should explicitly mention "lead field matrix calculation"
- Missing mention of channel projection to scalp surface (which happens in your code)

**Suggestions:**
- Reorder steps to match actual processing sequence: Coregistration → BEM → Forward model → Noise covariance → Source reconstruction
- Add sub-steps for channel processing (bad channel exclusion, projection to scalp)
- Clarify that noise covariance can be computed from any condition, not necessarily the same epoch

### 3. **Visual Flow and Connections**

**Unclear Elements:**
- The arrows don't clearly show which inputs feed into which processing steps
- The connection between the brain surface (red dots) and source reconstruction (colored brain regions) needs clarification
- The relationship between the 3D brain map and the CSV data matrix is not obvious

**Suggestions:**
- Use different arrow styles or colors to show data flow vs. processing steps
- Add intermediate visualizations showing electrode projection and forward model
- Show more clearly how the 3D source map translates to the DKT atlas regions in the CSV

### 4. **Missing Technical Details**

**Information Gaps:**
- No mention of the time window analysis (-50ms to +50ms around negative peak)
- Missing information about the sLORETA algorithm specifics (minimum norm estimation)
- No indication of coordinate systems or registration accuracy
- Missing mention of the "all scouts" function that extracts time series for all DKT regions

**Suggestions:**
- Add timing information to the epoch extraction
- Briefly explain what sLORETA does (inverse modeling via minimum norm estimation)
- Mention coordinate system transformations
- Show that CSV contains time-series data, not just single values

### 5. **Output Section Improvements**

**Unclear Elements:**
- The data matrix visualization doesn't clearly show it's time-series data
- No indication of what the color scale represents in the brain map
- Missing information about multiple output formats (screenshots, sensor cap images, etc.)

**Suggestions:**
- Show the CSV as time-series with time axis labeled
- Add a color bar to the brain visualization
- Indicate that multiple visualization outputs are generated (Mollweide projections, sensor caps, etc.)

### 6. **Terminology and Acronyms**

**Consistency Issues:**
- "SW" is used without definition in some places
- "DKT atlas" mentioned in legend but not in figure
- "sLORETA" could use brief explanation

**Suggestions:**
- Define all acronyms on first use
- Be consistent with "slow wave" vs "SW" usage
- Add brief explanations for technical terms

### 7. **Overall Figure Organization**

**Structural Improvements:**
- Consider adding panel labels (A, B, C) for easier reference
- Group related elements more clearly (e.g., all anatomical inputs together)
- Show the iterative nature of processing (that this happens for each detected slow wave)
- Consider showing that this pipeline runs for multiple subjects/nights/stages

**Data Flow Improvements:**
- Make it clearer that the same forward model is used for all epochs from a subject
- Show that noise covariance is computed once per night but applied to all slow waves
- Indicate batch processing aspects

### 8. **Scientific Context**

**Missing Context:**
- No indication of the research question or clinical application
- Missing information about experimental stages (pre-stim, stim, post-stim)
- No mention of the statistical analysis that follows

**Suggestions:**
- Add context about sleep slow wave research
- Mention that this enables comparison across experimental conditions
- Indicate downstream statistical analyses
