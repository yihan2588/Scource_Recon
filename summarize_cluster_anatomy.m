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

    StatMat = load_statmat(statFullPath);
    if isempty(StatMat) || ~isfield(StatMat, 'StatClusters') || isempty(StatMat.StatClusters)
        return;
    end

    summary.comment = get_field(StatMat, 'Comment', '');

    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    [~, baseName, ~] = fileparts(statFullPath);
    jsonPath = fullfile(outputDir, [baseName '_cluster_summary.json']);
    matPath  = fullfile(outputDir, [baseName '_cluster_summary.mat']);
    textPath = fullfile(outputDir, [baseName '_cluster_summary.txt']);

    timeVector = get_field(StatMat, 'Time', []);
    freqVector = get_field(StatMat, 'Freqs', []);
    rowLabels  = get_field(StatMat, 'Description', []);
    gridLoc    = get_field(StatMat, 'GridLoc', []);
    gridAtlas  = get_field(StatMat, 'GridAtlas', []);

    clustersPos = build_cluster_summaries(StatMat.StatClusters, 'pos', alpha, timeVector, freqVector, rowLabels, gridLoc, gridAtlas);
    clustersNeg = build_cluster_summaries(StatMat.StatClusters, 'neg', alpha, timeVector, freqVector, rowLabels, gridLoc, gridAtlas);
    summary.clusters = [clustersPos; clustersNeg]; %#ok<AGROW>

    summary.jsonPath = jsonPath;
    summary.matPath  = matPath;
    summary.textPath = textPath;

    if exist('jsonencode', 'file') == 2 %#ok<EXIST>
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

    write_text_summary(summary, textPath);
    if exist(textPath, 'file') == 2
        summary.textPath = textPath;
    else
        summary.textPath = '';
    end
end


function clusters = build_cluster_summaries(sc, polarity, alpha, timeVector, freqVector, rowLabels, gridLoc, gridAtlas)
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

        [spaceIdx, timeIdx, freqIdx, totalPoints] = extract_cluster_indices(mask);
        atlasOverlap = compute_atlas_overlap(spaceIdx, gridAtlas, rowLabels);
        coordinates = compute_coordinates(spaceIdx, gridLoc, gridAtlas);
        timeRange = compute_range(timeVector, timeIdx);
        freqRange = compute_freq_range(freqVector, freqIdx);

        clusterStruct = template;
        clusterStruct.id = sprintf('%s_%d', polarity, idx);
        clusterStruct.type = polarity;
        clusterStruct.index = idx;
        clusterStruct.pvalue = get_field(clusterArray(idx), 'prob', NaN);
        clusterStruct.clusterstat = get_field(clusterArray(idx), 'clusterstat', NaN);
        clusterStruct.size = struct('total', totalPoints, 'vertices', numel(spaceIdx), ...
                                    'timePoints', numel(timeIdx), 'frequencyPoints', numel(freqIdx));
        clusterStruct.vertexIndices = spaceIdx(:)';
        clusterStruct.timeIndices = timeIdx(:)';
        clusterStruct.frequencyIndices = freqIdx(:)';
        clusterStruct.timeRange = timeRange;
        clusterStruct.frequencyRange = freqRange;
        clusterStruct.coordinates = coordinates;
        clusterStruct.atlasOverlap = atlasOverlap;
        clusterStruct.isSignificant = is_significant(clusterStruct.pvalue, alpha);

        clusters(end + 1) = clusterStruct; %#ok<AGROW>
    end
end


function [spaceIdx, timeIdx, freqIdx, totalPoints] = extract_cluster_indices(mask)
    totalPoints = nnz(mask);
    dims = ndims(mask);
    sz = size(mask);

    switch dims
        case 2
            [spaceIdx, timeIdx] = find(mask);
            freqIdx = [];
        case 3
            if sz(1) == 1
                mask = squeeze(mask);
                [spaceIdx, timeIdx, freqIdx] = extract_cluster_indices(mask);
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


function atlasOverlap = compute_atlas_overlap(spaceIdx, gridAtlas, rowLabels)
    atlasOverlap = repmat(struct('atlas', '', 'label', '', 'count', 0, 'percentage', 0), 0, 1);

    if isempty(spaceIdx)
        return;
    end

    if ~isempty(gridAtlas) && isstruct(gridAtlas)
        if ~isfield(gridAtlas, 'Scouts') && numel(gridAtlas) == 1
            scouts = struct('Vertices', []);
            if isfield(gridAtlas, 'Vertices')
                scouts.Vertices = gridAtlas.Vertices;
                gridAtlas = struct('Name', get_field(gridAtlas, 'Name', 'Atlas'), 'Scouts', scouts);
            end
        end

        for a = 1:numel(gridAtlas)
            atlas = gridAtlas(a);
            if ~isfield(atlas, 'Scouts') || isempty(atlas.Scouts)
                continue;
            end
            atlasName = get_field(atlas, 'Name', sprintf('Atlas%d', a));
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
                               'label', get_field(scout, 'Label', sprintf('Scout%d', s)), ...
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


function coordinates = compute_coordinates(spaceIdx, gridLoc, gridAtlas)
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


function range = compute_range(vector, indices)
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


function range = compute_freq_range(freqVector, indices)
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


function write_text_summary(summary, textPath)
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
            lines{end + 1} = sprintf('    Significant (alpha=%.3f): %s', summary.alpha, tf(c.isSignificant));
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


function StatMat = load_statmat(statFullPath)
    StatMat = [];
    if nargin < 1 || isempty(statFullPath) || ~exist(statFullPath, 'file')
        warning('summarize_cluster_anatomy:MissingFile', 'Statistic file not found: %s', statFullPath);
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
        warning('summarize_cluster_anatomy:InvalidFile', ...
            'Unrecognised stat file format for %s', statFullPath);
    catch ME
        warning('summarize_cluster_anatomy:LoadFailed', ...
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


function tfFlag = is_significant(pValue, alpha)
    tfFlag = false;
    if isnumeric(pValue) && ~isnan(pValue) && isnumeric(alpha) && ~isnan(alpha)
        tfFlag = pValue <= alpha;
    end
end


function out = tf(flag)
    if flag
        out = 'yes';
    else
        out = 'no';
    end
end
