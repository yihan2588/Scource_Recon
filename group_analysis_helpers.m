function outputs = build_group_analysis_outputs(statFiles, outputRoot, alpha)
%BUILD_GROUP_ANALYSIS_OUTPUTS Generate plots and summaries for cluster stats.
%   outputs = build_group_analysis_outputs(statFiles, outputRoot, alpha) iterates
%   over the Brainstorm stat files listed in STATFILES (cell array of full paths),
%   renders permutation distribution plots, summarises cluster anatomy, and
%   returns a struct array describing the generated artefacts.
%
%   OUTPUTS is a struct array with fields:
%       - statFile
%       - distributionFigure
%       - summaryJson
%       - summaryMat
%       - summaryTxt
%       - metadata (plot metadata + cluster summary)
%
%   OUTPUTROOT is the directory under which per-stat folders will be created.
%   ALPHA defaults to 0.05 when omitted.
%
%   This helper depends on ft_cluster_helpers (plot_cluster_distribution,
%   summarize_cluster_anatomy).

    if nargin < 3 || isempty(alpha)
        alpha = 0.05;
    end
    if nargin < 2 || isempty(outputRoot)
        outputRoot = pwd;
    end
    if nargin < 1 || isempty(statFiles)
        outputs = struct('statFile', {}, 'distributionFigure', {}, 'summaryJson', {}, ...
                         'summaryMat', {}, 'summaryTxt', {}, 'metadata', {});
        return;
    end

    if ischar(statFiles) || isstring(statFiles)
        statFiles = cellstr(statFiles);
    end

    ensure_helpers_on_path();

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    outputs = repmat(struct('statFile', '', 'distributionFigure', '', 'summaryJson', '', ...
                             'summaryMat', '', 'summaryTxt', '', 'metadata', struct()), 0, 1);

    for i = 1:numel(statFiles)
        statPath = statFiles{i};
        if ~exist(statPath, 'file')
            warning('build_group_analysis_outputs:MissingStatFile', ...
                'Statistic file not found: %s', statPath);
            continue;
        end

        [~, statBase, ~] = fileparts(statPath);
        statOutDir = fullfile(outputRoot, sprintf('%s_%s', statBase, timestamp));
        if ~exist(statOutDir, 'dir')
            mkdir(statOutDir);
        end

        outEntry = struct('statFile', statPath, 'distributionFigure', '', ...
                          'summaryJson', '', 'summaryMat', '', 'summaryTxt', '', ...
                          'metadata', struct());

        try
            [figPath, figMeta] = plot_cluster_distribution(statPath, statOutDir, alpha);
            outEntry.distributionFigure = figPath;
            outEntry.metadata.plot = figMeta;
        catch ME
            warning('build_group_analysis_outputs:PlotFailed', ...
                'Failed to plot distributions for %s: %s', statPath, ME.message);
        end

        try
            clusterSummary = summarize_cluster_anatomy(statPath, statOutDir, alpha);
            outEntry.summaryJson = clusterSummary.jsonPath;
            outEntry.summaryMat = clusterSummary.matPath;
            outEntry.summaryTxt = clusterSummary.textPath;
            outEntry.metadata.summary = clusterSummary;
        catch ME
            warning('build_group_analysis_outputs:SummaryFailed', ...
                'Failed to summarise clusters for %s: %s', statPath, ME.message);
        end

        outputs(end + 1) = outEntry; %#ok<AGROW>
    end
end


function ensure_helpers_on_path()
    helperFunctions = {'plot_cluster_distribution', 'summarize_cluster_anatomy'};
    missing = helperFunctions(~cellfun(@(fn) (exist(fn, 'file') == 2), helperFunctions));
    if isempty(missing)
        return;
    end

    currentFile = mfilename('fullpath');
    helperDir = fileparts(currentFile);
    addpath(helperDir);

    stillMissing = helperFunctions(~cellfun(@(fn) (exist(fn, 'file') == 2), helperFunctions));
    if ~isempty(stillMissing)
        error('build_group_analysis_outputs:MissingHelpers', ...
            'Required helper functions are not available on the MATLAB path: %s', strjoin(stillMissing, ', '));
    end
end
