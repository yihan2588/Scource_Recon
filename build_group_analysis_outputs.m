function outputs = build_group_analysis_outputs(statFiles, outputRoot, alpha, contextLabel)
%BUILD_GROUP_ANALYSIS_OUTPUTS Generate plots and summaries for cluster stats.
%   outputs = build_group_analysis_outputs(statFiles, outputRoot, alpha, contextLabel)
%   iterates over the Brainstorm stat files listed in STATFILES (cell array of
%   file identifiers returned by bst_process) and produces distribution plots
%   plus textual/structured summaries for each. CONTEXTLABEL (optional) lets the
%   caller identify the group/contrast (e.g., "Active_Stim_vs_Pre_Night1") and
%   is injected into output folder names and metadata when supplied.
%
%   OUTPUTS is a struct array with fields:
%       - statFile            : Absolute path to the statistic file
%       - distributionFigure  : Path to the saved permutation distribution PNG
%       - summaryJson         : Path to the JSON summary (if generated)
%       - summaryMat          : Path to the MAT summary (if generated)
%       - summaryTxt          : Path to the TXT summary (if generated)
%       - metadata            : Struct containing plot + summary metadata
%       - context             : Struct describing label/timestamps used
%
    %   This helper depends on plot_cluster_distribution and summarize_cluster_anatomy.
%   (Previously used ft_cluster_helpers wrapper, now calls directly)

    if nargin < 4
        contextLabel = '';
    end
    if nargin < 3 || isempty(alpha)
        alpha = 0.05;
    end
    if nargin < 2 || isempty(outputRoot)
        outputRoot = pwd;
    end
    
    % Force outputRoot to be absolute
    if isjava(java.io.File(outputRoot))
         outputRoot = char(java.io.File(outputRoot).getAbsolutePath());
    elseif ~startsWith(outputRoot, filesep) && ~contains(outputRoot, ':')
         outputRoot = fullfile(pwd, outputRoot);
    end

    if nargin < 1 || isempty(statFiles)
        outputs = struct('statFile', {}, 'distributionFigure', {}, 'summaryJson', {}, ...
                         'summaryMat', {}, 'summaryTxt', {}, 'metadata', {}, 'context', {});
        return;
    end

    if ischar(statFiles) || isstring(statFiles)
        statFiles = cellstr(statFiles);
    end

    if isnumeric(contextLabel) || islogical(contextLabel)
        contextLabel = string(contextLabel);
    end
    if isstring(contextLabel)
        contextLabel = char(contextLabel);
    end
    if isempty(contextLabel)
        contextLabel = '';
    end

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    labelSlug = sanitize_label(contextLabel);

    outputs = repmat(struct('statFile', '', 'distributionFigure', '', 'summaryJson', '', ...
                             'summaryMat', '', 'summaryTxt', '', 'metadata', struct(), ...
                             'context', struct()), 0, 1);

    for i = 1:numel(statFiles)
        statId = statFiles{i};
        statFullPath = resolve_stat_path(statId);
        if isempty(statFullPath)
            warning('build_group_analysis_outputs:MissingStatFile', ...
                'Statistic file could not be resolved: %s', statId);
            continue;
        end

        [~, statBase, ~] = fileparts(statFullPath);
        displayName = statBase;
        if ~isempty(labelSlug)
            displayName = sprintf('%s_%s', labelSlug, statBase);
        end
        statOutDir = fullfile(outputRoot, sprintf('%s_%s', displayName, timestamp));
        if ~exist(statOutDir, 'dir')
            mkdir(statOutDir);
        end

        outEntry = struct('statFile', statFullPath, 'distributionFigure', '', ...
                          'summaryJson', '', 'summaryMat', '', 'summaryTxt', '', ...
                          'metadata', struct(), ...
                          'context', struct('label', contextLabel, 'slug', labelSlug, ...
                                            'timestamp', timestamp, 'outputDir', statOutDir));

        try
            [figPath, figMeta] = plot_cluster_distribution(statFullPath, statOutDir, alpha, contextLabel);
            outEntry.distributionFigure = figPath;
            outEntry.metadata.plot = figMeta;
        catch ME
            warning('build_group_analysis_outputs:PlotFailed', ...
                'Failed to plot distributions for %s: %s', statFullPath, ME.message);
        end

        try
            clusterSummary = summarize_cluster_anatomy(statFullPath, statOutDir, alpha);
            outEntry.summaryJson = clusterSummary.jsonPath;
            outEntry.summaryMat = clusterSummary.matPath;
            outEntry.summaryTxt = clusterSummary.textPath;
            clusterSummary.contextLabel = contextLabel;
            outEntry.metadata.summary = clusterSummary;
        catch ME
            warning('build_group_analysis_outputs:SummaryFailed', ...
                'Failed to summarise clusters for %s: %s', statFullPath, ME.message);
        end

        outputs(end + 1) = outEntry; %#ok<AGROW>
    end
end


function statFullPath = resolve_stat_path(statIdentifier)
    % Attempt to resolve a Brainstorm-relative stat file path to an absolute path,
    % allowing a few retries in case the file is still being written to disk.
    maxAttempts = 5;
    waitSeconds = 0.2;
    statFullPath = '';

    for attempt = 1:maxAttempts
        candidate = statIdentifier;
        if exist(candidate, 'file') == 2
            statFullPath = candidate;
            return;
        end

        try
            candidate = file_fullpath(statIdentifier);
        catch
            candidate = '';
        end

        if ~isempty(candidate) && exist(candidate, 'file') == 2
            statFullPath = candidate;
            return;
        end

        pause(waitSeconds);
    end
end

function slug = sanitize_label(label)
    label = string(label);
    if strlength(label) == 0
        slug = '';
        return;
    end
    label = regexprep(label, '\s+', '_');
    label = regexprep(label, '[^\w\-]', '_');
    slug = char(label);
end
