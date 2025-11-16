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

    StatMat = local_load_statmat(statFullPath);
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

    metadata.pos = local_render_distribution_subplot(fh, 1, sc, 'pos', alpha);
    metadata.neg = local_render_distribution_subplot(fh, 2, sc, 'neg', alpha);

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


function summary = summarize_cluster_anatomy(statFullPath, outputDir, alpha)
%SUMMARIZE_CLUSTER_ANATOMY Produce structured summaries of Brainstorm clusters.
%   summary = summarize_cluster_anatomy(statFullPath, outputDir, alpha) loads the
%   statistics file located at STATFULLPATH, enumerates positive and negative
%   clusters, maps their spatial indices back to 3-D coordinates and atlas/ROI
%   annotations, and saves the outputs to OUTPUTDIR as JSON, MAT, and TXT files.
%   The returned SUMMARY struct includes the per-cluster details along with the
%   paths to the generated artefacts. Clusters with p-values <= ALPHA (default
%   0.05) are flagged as significant.

    if nargin < 3 || isempty(alpha)
        alpha = 0.05;
    end
    if nargin < 2 || isempty(outputDir)
        outputDir = pwd;
    end

    summary = struct('statFile', statFullPath, 'comment', '', 'alpha', alpha, ...
                     'generated', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                     'clusters', [], 'jsonPath', '', 'matPath', '', 'textPath', '');

    StatMat = local_load_statmat(statFullPath);
    if isempty(StatMat) || ~isfield(StatMat, 'StatClusters') || isempty(StatMat.StatClusters)
        return;
    end

    summary.comment = local_get_field(StatMat, 'Comment', '');

    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    [~, baseName, ~] = fileparts(statFullPath);
    jsonPath = fullfile(outputDir, [baseName '_cluster_summary.json']);
    matPath  = fullfile(outputDir, [baseName '_cluster_summary.mat']);
    textPath = fullfile(outputDir, [baseName '_cluster_summary.txt']);

    timeVector = local_get_field(StatMat, 'Time', []);
    freqVector = local_get_field(StatMat, 'Freqs', []);
    rowLabels  = local_get_field(StatMat, 'Description', []);
    gridLoc    = local_get_field(StatMat, 'GridLoc', []);
    gridAtlas  = local_get_field(StatMat, 'GridAtlas', []);

    clustersPos = local_build_cluster_summaries(StatMat.StatClusters, 'pos', alpha, timeVector, freqVector, rowLabels, gridLoc, gridAtlas);
    clustersNeg = local_build_cluster_summaries(StatMat.StatClusters, 'neg', alpha, timeVector, freqVector, rowLabels, gridLoc, gridAtlas);
    summary.clusters = [clustersPos; clustersNeg];

    summary.jsonPath = jsonPath;
    summary.matPath  = matPath;
    summary.textPath = textPath;

    if exist('jsonencode', 'file') == 2
        jsonText = jsonencode(summary);
        fid = fopen(jsonPath, 'w');
        if fid ~= -1
            fwrite(fid, jsonText, 'char');
            fclose(fid);
        else
            warning('summarize_cluster_anatomy:JSONWriteFailed', ...
                'Unable to write JSON summary to %s', jsonPath);
            summary.jsonPath = '';
        end
    else
        warning('summarize_cluster_anatomy:JSONEncodeUnavailable', ...
            'jsonencode not available in this MATLAB release. Skipping JSON output.');
        summary.jsonPath = '';
    end

    try
        save(matPath, 'summary');
    catch ME
        warning('summarize_cluster_anatomy:MATSaveFailed', ...
            'Could not save MAT summary: %s', ME.message);
        summary.matPath = '';
    end

    local_write_text_summary(summary, textPath);
    summary.textPath = textPath;
end


%% ------------------------------------------------------------------------
function metadata = local_render_distribution_subplot(figHandle, subplotIndex, sc, polarity, alpha)
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
        observedStats = arrayfun(@(c) local_get_field(c, 'clusterstat', NaN), clusters);
        pvals = arrayfun(@(c) local_get_field(c, 'prob', NaN), clusters);
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

    xlabel(ax, sprintf('%s cluster statistic', local_capitalize(polarity)));
    ylabel(ax, 'Count');
    title(ax, sprintf('%s clusters (\alpha = %.3f)', local_capitalize(polarity), alpha), 'Interpreter', 'none');
    grid(ax, 'on');
    hold(ax, 'off');
end


function clusters = local_build_cluster_summaries(sc, polarity, alpha, timeVector, freqVector, rowLabels, gridLoc, gridAtlas)
    template = struct('id', '', 'type', '', 'index', NaN, 'pvalue', NaN, ...
                      'clusterstat', NaN, 'size', struct('total', 0, 'vertices', 0, ...
                      'timePoints', 0, 'frequencyPoints', 0), 'vertexIndices', [], ...
                      'timeIndices', [], 'frequencyIndices', [], 'timeRange', [], ...
                      'frequencyRange', [], 'coordinates', struct('centroid', [], 'points', []), ...
                      'atlasOverlap', [], 'isSignificant', false);
    clusters = repmat(template, 0, 1);

    clusterField = [polarity 'clusters'];
    labelField = [polarity 'clusterslabelmat'];

    if ~isfield(sc, clusterField) || isempty(sc.(clusterField)) || ...
            ~isfield(sc, labelField) || isempty(sc.(labelField))
        return;
    end

    clusterArray = sc.(clusterField);
    labelMat = sc.(labelField);

    for idx = 1:numel(clusterArray)
        mask = (labelMat == idx);
        if ~any(mask(:))
            continue;
        end

        [spaceIdx, timeIdx, freqIdx, totalPoints] = local_extract_cluster_indices(mask);
        atlasOverlap = local_compute_atlas_overlap(spaceIdx, gridAtlas, rowLabels);
        coordinates = local_compute_coordinates(spaceIdx, gridLoc, gridAtlas);
        timeRange = local_compute_range(timeVector, timeIdx);
        freqRange = local_compute_freq_range(freqVector, freqIdx);

        clusterStruct = template;
        clusterStruct.id = sprintf('%s_%d', polarity, idx);
        clusterStruct.type = polarity;
        clusterStruct.index = idx;
        clusterStruct.pvalue = local_get_field(clusterArray(idx), 'prob', NaN);
        clusterStruct.clusterstat = local_get_field(clusterArray(idx), 'clusterstat', NaN);
        clusterStruct.size = struct('total', totalPoints, 'vertices', numel(spaceIdx), ...
                                    'timePoints', numel(timeIdx), 'frequencyPoints', numel(freqIdx));
        clusterStruct.vertexIndices = spaceIdx(:)';
        clusterStruct.timeIndices = timeIdx(:)';
        clusterStruct.frequencyIndices = freqIdx(:)';
        clusterStruct.timeRange = timeRange;
        clusterStruct.frequencyRange = freqRange;
        clusterStruct.coordinates = coordinates;
        clusterStruct.atlasOverlap = atlasOverlap;
        clusterStruct.isSignificant = local_is_significant(clusterStruct.pvalue, alpha);

        clusters(end + 1) = clusterStruct; %#ok<AGROW>
    end
end


function [spaceIdx, timeIdx, freqIdx, totalPoints] = local_extract_cluster_indices(mask)
    totalPoints = nnz(mask);
    dims = ndims(mask);
    sz = size(mask);

    switch dims
        case 2
            [spaceIdx, timeIdx] = find(mask);
            freqIdx = [];
        case 3
            if sz(1) == 1 % degenerate spatial dimension (e.g., ROI matrices)
                mask = squeeze(mask);
                [spaceIdx, timeIdx, freqIdx] = local_extract_cluster_indices(mask);
                return;
            end
            [spaceIdx, timeIdx, freqIdx] = ind2sub(sz, find(mask));
        otherwise
            mask = reshape(mask, sz(1), []);
            [spaceIdx, timeIdx] = find(mask);
            freqIdx = [];
    end

    spaceIdx = unique(spaceIdx(:));
    timeIdx = unique(timeIdx(:));
    freqIdx = unique(freqIdx(:));
end


function atlasOverlap = local_compute_atlas_overlap(spaceIdx, gridAtlas, rowLabels)
    atlasOverlap = repmat(struct('atlas', '', 'label', '', 'count', 0, 'percentage', 0), 0, 1);

    if isempty(spaceIdx)
        return;
    end

    if ~isempty(gridAtlas) && isstruct(gridAtlas)
        if ~isfield(gridAtlas, 'Scouts') && numel(gridAtlas) == 1
            scouts = struct('Vertices', []);
            if isfield(gridAtlas, 'Vertices')
                scouts.Vertices = gridAtlas.Vertices;
                gridAtlas = struct('Name', local_get_field(gridAtlas, 'Name', 'Atlas'), 'Scouts', scouts);
            end
        end

        for a = 1:numel(gridAtlas)
            atlas = gridAtlas(a);
            if ~isfield(atlas, 'Scouts') || isempty(atlas.Scouts)
                continue;
            end
            atlasName = local_get_field(atlas, 'Name', sprintf('Atlas%d', a));
            for s = 1:numel(atlas.Scouts)
                scout = atlas.Scouts(s);
                if ~isfield(scout, 'Vertices') || isempty(scout.Vertices)
                    continue;
                end
                overlap = intersect(spaceIdx(:)', scout.Vertices(:)');
                if isempty(overlap)
                    continue;
                end
                entry = struct('atlas', atlasName, ...
                               'label', local_get_field(scout, 'Label', sprintf('Scout%d', s)), ...
                               'count', numel(overlap), ...
                               'percentage', numel(overlap) / numel(spaceIdx));
                atlasOverlap(end + 1) = entry; %#ok<AGROW>
            end
        end
        if ~isempty(atlasOverlap)
            [~, order] = sort([atlasOverlap.count], 'descend');
            atlasOverlap = atlasOverlap(order);
        end
    elseif ~isempty(rowLabels)
        if iscell(rowLabels)
            selectedLabels = rowLabels(spaceIdx);
        elseif isstring(rowLabels)
            selectedLabels = cellstr(rowLabels(spaceIdx));
        else
            selectedLabels = arrayfun(@(idx) sprintf('ROI%d', idx), spaceIdx, 'UniformOutput', false);
        end
        [uniqueLabels, ~, ic] = unique(selectedLabels);
        for k = 1:numel(uniqueLabels)
            count = sum(ic == k);
            entry = struct('atlas', 'ROI', 'label', uniqueLabels{k}, ...
                           'count', count, 'percentage', count / numel(spaceIdx));
            atlasOverlap(end + 1) = entry; %#ok<AGROW>
        end
        [~, order] = sort([atlasOverlap.count], 'descend');
        atlasOverlap = atlasOverlap(order);
    end
end


function coordinates = local_compute_coordinates(spaceIdx, gridLoc, gridAtlas)
    coordinates = struct('centroid', [], 'points', []);

    if isempty(spaceIdx)
        return;
    end

    if ~isempty(gridLoc) && isnumeric(gridLoc) && size(gridLoc, 1) >= max(spaceIdx)
        coords = gridLoc(spaceIdx, :);
        coordinates.points = coords;
        coordinates.centroid = mean(coords, 1, 'omitnan');
        return;
    end

    if ~isempty(gridAtlas) && isstruct(gridAtlas)
        collected = zeros(numel(spaceIdx), 3);
        hasCoord = false(numel(spaceIdx), 1);
        for a = 1:numel(gridAtlas)
            atlas = gridAtlas(a);
            if ~isfield(atlas, 'Scouts') || isempty(atlas.Scouts)
                continue;
            end
            for s = 1:numel(atlas.Scouts)
                scout = atlas.Scouts(s);
                if ~isfield(scout, 'Vertices') || isempty(scout.Vertices)
                    continue;
                end
                [isOverlap, loc] = ismember(spaceIdx(:)', scout.Vertices(:)');
                if ~any(isOverlap)
                    continue;
                end
                for idx = find(isOverlap)
                    if isfield(scout, 'Seed') && ~isempty(scout.Seed)
                        collected(idx, :) = scout.Seed(:)';
                        hasCoord(idx) = true;
                    elseif ~isempty(gridLoc) && isnumeric(gridLoc) && size(gridLoc, 1) >= max(scout.Vertices)
                        collected(idx, :) = mean(gridLoc(scout.Vertices, :), 1, 'omitnan');
                        hasCoord(idx) = true;
                    end
                end
            end
        end
        if any(hasCoord)
            coordinates.points = collected;
            coordinates.points(~hasCoord, :) = NaN;
            coordinates.centroid = mean(collected(hasCoord, :), 1, 'omitnan');
        end
    end
end


function range = local_compute_range(vector, indices)
    if isempty(vector) || isempty(indices)
        range = [];
        return;
    end
    vector = vector(:)';
    indices = unique(indices(:)');
    indices(indices < 1 | indices > numel(vector)) = [];
    if isempty(indices)
        range = [];
    else
        range = [vector(indices(1)), vector(indices(end))];
    end
end


function range = local_compute_freq_range(freqVector, indices)
    if isempty(freqVector) || isempty(indices)
        range = [];
        return;
    end

    indices = unique(indices(:)');
    if isnumeric(freqVector)
        freqVector = freqVector(:)';
        indices(indices < 1 | indices > numel(freqVector)) = [];
        if isempty(indices)
            range = [];
        else
            range = [freqVector(indices(1)), freqVector(indices(end))];
        end
    elseif iscell(freqVector)
        range = freqVector(indices);
    else
        range = [];
    end
end


function local_write_text_summary(summary, textPath)
    lines = {};
    lines{end + 1} = sprintf('Stat file: %s', summary.statFile);
    lines{end + 1} = sprintf('Comment : %s', summary.comment);
    lines{end + 1} = sprintf('Alpha   : %.4f', summary.alpha);
    lines{end + 1} = sprintf('Generated on %s', summary.generated);
    lines{end + 1} = '';

    clusters = summary.clusters;
    if isempty(clusters)
        lines{end + 1} = 'No clusters detected.';
    else
        for cIdx = 1:numel(clusters)
            c = clusters(cIdx);
            lines{end + 1} = sprintf('Cluster %s (%s) -- p = %.4f, stat = %.4f', ...
                c.id, c.type, c.pvalue, c.clusterstat);
            lines{end + 1} = sprintf('    Size: %d points (%d vertices, %d time, %d freq)', ...
                c.size.total, c.size.vertices, c.size.timePoints, c.size.frequencyPoints);
            if numel(c.timeRange) == 2
                lines{end + 1} = sprintf('    Time range: [%.4f, %.4f] s', c.timeRange(1), c.timeRange(2));
            end
            if isnumeric(c.frequencyRange) && numel(c.frequencyRange) == 2
                lines{end + 1} = sprintf('    Frequency range: [%.2f, %.2f] Hz', c.frequencyRange(1), c.frequencyRange(2));
            elseif iscell(c.frequencyRange) && ~isempty(c.frequencyRange)
                lines{end + 1} = sprintf('    Frequency bins: %s', strjoin(c.frequencyRange, ', '));
            end
            if ~isempty(c.coordinates) && isfield(c.coordinates, 'centroid') && numel(c.coordinates.centroid) == 3
                lines{end + 1} = sprintf('    Centroid: [%.2f, %.2f, %.2f] mm', ...
                    c.coordinates.centroid(1), c.coordinates.centroid(2), c.coordinates.centroid(3));
            end
            if ~isempty(c.atlasOverlap)
                topLabels = min(5, numel(c.atlasOverlap));
                labelStrs = cell(1, topLabels);
                for k = 1:topLabels
                    ol = c.atlasOverlap(k);
                    labelStrs{k} = sprintf('%s (%s, %.1f%%)', ol.label, ol.atlas, ol.percentage * 100);
                end
                lines{end + 1} = sprintf('    Atlas overlap: %s', strjoin(labelStrs, '; '));
            end
            lines{end + 1} = sprintf('    Significant (alpha=%.3f): %s', summary.alpha, local_tf(c.isSignificant));
            lines{end + 1} = '';
        end
    end

    fid = fopen(textPath, 'w');
    if fid ~= -1
        fprintf(fid, '%s\n', lines{:});
        fclose(fid);
    else
        warning('summarize_cluster_anatomy:TextWriteFailed', ...
            'Unable to write text summary to %s', textPath);
    end
end


%% ------------------------------------------------------------------------
function StatMat = local_load_statmat(statFullPath)
    StatMat = [];
    if nargin < 1 || isempty(statFullPath) || ~exist(statFullPath, 'file')
        warning('local_load_statmat:MissingFile', 'Statistic file not found: %s', statFullPath);
        return;
    end
    try
        data = load(statFullPath);
        if isfield(data, 'StatMat')
            StatMat = data.StatMat;
            return;
        end
        % Fallback: first struct in file
        fields = fieldnames(data);
        for i = 1:numel(fields)
            if isstruct(data.(fields{i}))
                StatMat = data.(fields{i});
                return;
            end
        end
        warning('local_load_statmat:InvalidFile', ...
            'Unrecognised stat file format for %s', statFullPath);
    catch ME
        warning('local_load_statmat:LoadFailed', ...
            'Failed to load statistic file %s: %s', statFullPath, ME.message);
    end
end


function value = local_get_field(structure, fieldName, defaultValue)
    if isstruct(structure) && isfield(structure, fieldName) && ~isempty(structure.(fieldName))
        value = structure.(fieldName);
    else
        value = defaultValue;
    end
end


function tf = local_is_significant(pValue, alpha)
    tf = false;
    if isnumeric(pValue) && ~isnan(pValue) && isnumeric(alpha) && ~isnan(alpha)
        tf = pValue <= alpha;
    end
end


function out = local_tf(flag)
    if flag
        out = 'yes';
    else
        out = 'no';
    end
end


function str = local_capitalize(str)
    if isempty(str)
        return;
    end
    str = lower(str);
    str(1) = upper(str(1));
end
