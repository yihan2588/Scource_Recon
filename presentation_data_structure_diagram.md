# BST Comparison Results - Data Structure for Presentation

## Presentation Data Hierarchy

```
Raw EEG Data
│
├── Source Reconstruction (sLORETA)
│   └── Individual Subject Results
│       ├── Subject_102 (Active Group)
│       │   ├── pre-stim epochs → sLORETA results
│       │   ├── stim epochs → sLORETA results
│       │   └── post-stim epochs → sLORETA results
│       │
│       ├── Subject_108 (Active Group)
│       │   ├── pre-stim epochs → sLORETA results
│       │   ├── stim epochs → sLORETA results
│       │   └── post-stim epochs → sLORETA results
│       │
│       └── Subject_107 (Sham Group)
│           ├── pre-stim epochs → sLORETA results
│           ├── stim epochs → sLORETA results
│           └── post-stim epochs → sLORETA results
│
└── BST Comparison Analysis
    │
    ├── 📊 PRIMARY DATA: Group-Level Comparisons
    │   │   ┌─────────────────────────────────────┐
    │   │   │        PERCENTAGE CHANGE MAPS       │
    │   │   │     (Main Presentation Focus)       │
    │   │   └─────────────────────────────────────┘
    │   │
    │   ├── Active Group Comparisons
    │   │   ├── Active_Stim_vs_Pre ────────────────┐
    │   │   ├── Active_Post_vs_Stim ───────────────┤ ◄── These show
    │   │   └── Active_Post_vs_Pre ────────────────┤     treatment effects
    │   │                                          │
    │   ├── Sham Group Comparisons                 │
    │   │   ├── Sham_Stim_vs_Pre ─────────────────┤ ◄── These show
    │   │   ├── Sham_Post_vs_Stim ────────────────┤     placebo effects
    │   │   └── Sham_Post_vs_Pre ─────────────────┤
    │   │                                          │
    │   └── Between-Group Comparisons              │
    │       ├── Active_vs_Sham_Pre ────────────────┤ ◄── These show
    │       ├── Active_vs_Sham_Stim ───────────────┤     treatment-specific
    │       └── Active_vs_Sham_Post ───────────────┘     differences
    │
    ├── 📈 SECONDARY DATA: Group-Level Averages
    │   │   ┌─────────────────────────────────────┐
    │   │   │      BASELINE ACTIVITY MAPS         │
    │   │   │    (Supporting Information)         │
    │   │   └─────────────────────────────────────┘
    │   │
    │   ├── Active Group Averages
    │   │   ├── Active_Pre_Avg ───────────────────┐
    │   │   ├── Active_Stim_Avg ──────────────────┤ ◄── Show baseline brain
    │   │   └── Active_Post_Avg ───────────────────┤     activity patterns
    │   │                                          │
    │   └── Sham Group Averages                    │
    │       ├── Sham_Pre_Avg ─────────────────────┤ ◄── Show control group
    │       ├── Sham_Stim_Avg ────────────────────┤     activity patterns
    │       └── Sham_Post_Avg ────────────────────┘
    │
    └── 📋 SECONDARY DATA: Individual Subject Examples
        │   ┌─────────────────────────────────────┐
        │   │     INDIVIDUAL VARIABILITY          │
        │   │    (Representative Examples)        │
        │   └─────────────────────────────────────┘
        │
        ├── Subject_102 (Active) Comparisons
        │   ├── Subject_102_Stim_vs_Pre ──────────┐
        │   ├── Subject_102_Post_vs_Stim ─────────┤ ◄── Show individual
        │   └── Subject_102_Post_vs_Pre ──────────┤     response patterns
        │                                         │
        └── Subject_107 (Sham) Comparisons        │
            ├── Subject_107_Stim_vs_Pre ─────────┤ ◄── Show individual
            ├── Subject_107_Post_vs_Stim ────────┤     control patterns
            └── Subject_107_Post_vs_Pre ─────────┘
```

## Presentation Flow Guide

### 🎯 **SLIDE 1-3: PRIMARY DATA** 
**Group-Level Percentage Change Maps**

**What you're showing:** 
- Brain regions where treatment caused significant changes
- Statistical power of group-averaged effects
- Direct comparison between Active vs Sham responses

**Key Message:** 
- "These maps show WHERE and HOW MUCH the brain changed due to stimulation"
- Red/Warm colors = Increased activity
- Blue/Cool colors = Decreased activity
- Percentage values = Magnitude of change

---

### 📊 **SLIDE 4-5: SECONDARY DATA TYPE 1**
**Group-Level Average Activity Maps**

**What you're showing:**
- Baseline brain activity patterns during each experimental phase
- Overall activity levels (not changes)
- Foundation for understanding the comparisons

**Key Message:**
- "These maps show the baseline brain activity that the changes are built upon"
- Helps audience understand what regions were active to begin with
- Provides context for interpreting the change maps

---

### 👤 **SLIDE 6-7: SECONDARY DATA TYPE 2**
**Individual Subject Examples**

**What you're showing:**
- Representative examples of individual responses
- Variability across subjects
- How group effects manifest in individual brains

**Key Message:**
- "These examples show how the group effects appear in individual subjects"
- Demonstrates consistency (or variability) of treatment effects
- Validates that group effects aren't driven by outliers

## Color Coding Legend

| Data Type | Color Scheme | Interpretation |
|-----------|--------------|----------------|
| **Group Comparisons** | Diverging (Red-Blue) | Red = Increase, Blue = Decrease |
| **Group Averages** | Sequential (Yellow-Red) | Intensity = Activity Level |
| **Individual Examples** | Diverging (Red-Blue) | Red = Increase, Blue = Decrease |

## Key Visualization Features

- **Contact Sheets**: Multiple time points in single view
- **Multiple Orientations**: Top, bottom, left, right brain views
- **Consistent Scaling**: Same color bounds for direct comparison
- **Statistical Threshold**: Only significant changes shown

## Presentation Tips

1. **Start with the big picture** (Group comparisons) → **Zoom into details** (Individual examples)
2. **Use consistent terminology**: "Active group", "Sham group", "Percentage change"
3. **Highlight key regions**: Point out specific brain areas showing effects
4. **Connect to hypothesis**: Relate findings back to original research questions
