function [figPath, metadata] = plot_cluster_distribution(statFullPath, outputDir, alpha)
%PLOT_CLUSTER_DISTRIBUTION Plot permutation distributions for Brainstorm stat files.
%   [figPath, metadata] = plot_cluster_distribution(statFullPath, outputDir, alpha)
%   loads the Brainstorm statistics file located at STATFULLPATH, extracts the
%   positive and negative permutation distributions stored in StatClusters, and
%   writes a two-panel figure to OUTPUTDIR that overlays the observed cluster
%   statistics with the null distributions. Clusters with p-values <= ALPHA are
%   highlighted in green, while non-significant clusters are drawn in grey. The
%   function returns the saved figure path and a metadata struct summarising the
%   contents of each subplot.
%
%   ALPHA defaults to 0.05 when omitted.
%
%   This helper operates on STATMAT structures saved by Brainstorm's FieldTrip
%   integration (ft_timelockstatistics / ft_sourcestatistics).
%
%   Example:
%       [fig, info] = plot_cluster_distribution(statFile, outputDir, 0.05);
%
%   See also: summarize_cluster_anatomy

    if nargin < 3 || isempty(alpha)
        alpha = 0.05;
    end
    if nargin < 2 || isempty(outputDir)
        outputDir = pwd;
    end

    figPath = '';
    metadata = struct('pos', [], 'neg', []);

    StatMat = load_statmat(statFullPath);
    if isempty(StatMat) || ~isfield(StatMat, 'StatClusters') || isempty(StatMat.StatClusters)
        return;
    end
    sc = StatMat.StatClusters;

    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    [~, baseName, ~] = fileparts(statFullPath);
    figPath = fullfile(outputDir, [baseName '_cluster_distribution.png']);

    fh = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1200, 700]);

    metadata.pos = render_distribution_subplot(fh, 1, sc, 'pos', alpha);
    metadata.neg = render_distribution_subplot(fh, 2, sc, 'neg', alpha);

    mainTitle = 'Cluster permutation distributions';
    if isfield(StatMat, 'Comment') && ~isempty(StatMat.Comment)
        mainTitle = sprintf('%s: %s', mainTitle, StatMat.Comment);
    end
    if exist('sgtitle', 'builtin') || exist('sgtitle', 'file')
        sgtitle(mainTitle, 'Interpreter', 'none');
    else
        annotation(fh, 'textbox', [0 0.95 1 0.05], 'String', mainTitle, ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'EdgeColor', 'none', 'FontWeight', 'bold', 'Interpreter', 'none');
    end

    try
        saveas(fh, figPath);
    catch ME %#ok<NASGU>
        warning('plot_cluster_distribution:SaveFailed', ...
            'Failed to save figure to %s', figPath);
    end
    close(fh);
end


function metadata = render_distribution_subplot(figHandle, subplotIndex, sc, polarity, alpha)
    metadata = struct('distribution', [], 'observed', [], 'pValues', [], ...
                      'significantIdx', [], 'clusterIndices', []);
    ax = subplot(2, 1, subplotIndex, 'Parent', figHandle);
    hold(ax, 'on');

    distField = [polarity 'distribution'];
    clusterField = [polarity 'clusters'];

    dist = [];
    if isfield(sc, distField)
        dist = sc.(distField);
    end
    if ~isempty(dist)
        histogram(ax, dist(:), 'FaceColor', [0.3 0.55 0.9], 'EdgeColor', [0.2 0.2 0.2]);
        metadata.distribution = dist(:)';
    end

    clusters = [];
    if isfield(sc, clusterField)
        clusters = sc.(clusterField);
    end

    yl = [0 1];
    if ~isempty(dist)
        yl = get(ax, 'YLim');
        if yl(2) == 0
            yl(2) = 1;
        end
    end

    if ~isempty(clusters)
        observedStats = arrayfun(@(c) get_field(c, 'clusterstat', NaN), clusters);
        pvals = arrayfun(@(c) get_field(c, 'prob', NaN), clusters);
        metadata.observed = observedStats;
        metadata.pValues = pvals;
        metadata.clusterIndices = 1:numel(clusters);
        metadata.significantIdx = find(pvals <= alpha);

        for i = 1:numel(observedStats)
            val = observedStats(i);
            if isnan(val)
                continue;
            end
            if pvals(i) <= alpha
                color = [0.0 0.6 0.2];
            else
                color = [0.5 0.5 0.5];
            end
            line(ax, [val val], [yl(1) yl(2) * 0.95], 'Color', color, 'LineWidth', 2);
        end
    end

    xlabel(ax, sprintf('%s cluster statistic', capitalize(polarity)));
    ylabel(ax, 'Count');
    title(ax, sprintf('%s clusters (\alpha = %.3f)', capitalize(polarity), alpha), 'Interpreter', 'none');
    grid(ax, 'on');
    hold(ax, 'off');
end


function StatMat = load_statmat(statFullPath)
    StatMat = [];
    if nargin < 1 || isempty(statFullPath) || ~exist(statFullPath, 'file')
        warning('plot_cluster_distribution:MissingFile', 'Statistic file not found: %s', statFullPath);
        return;
    end
    try
        data = load(statFullPath);
        if isfield(data, 'StatMat')
            StatMat = data.StatMat;
            return;
        end
        fields = fieldnames(data);
        for i = 1:numel(fields)
            if isstruct(data.(fields{i}))
                StatMat = data.(fields{i});
                return;
            end
        end
        warning('plot_cluster_distribution:InvalidFile', ...
            'Unrecognised stat file format for %s', statFullPath);
    catch ME
        warning('plot_cluster_distribution:LoadFailed', ...
            'Failed to load statistic file %s: %s', statFullPath, ME.message);
    end
end


function value = get_field(structure, fieldName, defaultValue)
    if isstruct(structure) && isfield(structure, fieldName) && ~isempty(structure.(fieldName))
        value = structure.(fieldName);
    else
        value = defaultValue;
    end
end


function str = capitalize(str)
    if isempty(str)
        return;
    end
    str = lower(str);
    str(1) = upper(str(1));
end
