function [figPath, figMeta] = plot_cluster_distribution(statFile, outDir, alpha, customTitle)
%PLOT_CLUSTER_DISTRIBUTION Visualizes the cluster permutation histogram.
%   Targeted for Brainstorm structures where distribution is inside 'StatClusters'.
%
%   Usage:
%       plot_cluster_distribution(file, dir, 0.05)              -> Auto title (filename)
%       plot_cluster_distribution(file, dir, 0.05, 'My Plot')   -> Custom title

    figPath = '';
    figMeta = struct();

    % --- 0. Handle Title Logic ---
    if nargin < 4 || isempty(customTitle)
        % Default: Use filename if no custom title provided
        [~, fNameRaw, ~] = fileparts(statFile);
        plotTitle = sprintf('Cluster Permutation: %s', strrep(fNameRaw, '_', '\_'));
    else
        % Use the custom string provided by the user
        plotTitle = customTitle;
    end

    % --- 1. Load Data ---
    if ~exist(statFile, 'file')
        warning('File not found: %s', statFile);
        return;
    end
    data = load(statFile);

    % --- 2. Extract Data (Targeting 'StatClusters') ---
    perm_dist = [];
    obs_stats = [];
    obs_pvals = [];
    statType = 'Cluster Statistic';

    % Check if StatClusters exists
    if isfield(data, 'StatClusters')
        sc = data.StatClusters;
        
        % Get Distribution
        if isfield(sc, 'posdistribution')
            perm_dist = sc.posdistribution;
        end
        
        % Get Observed Clusters
        if isfield(sc, 'posclusters') && ~isempty(sc.posclusters)
            obs_stats = [sc.posclusters.clusterstat];
            obs_pvals = [sc.posclusters.prob];
        end
    else
        warning('StatClusters structure not found in file.');
        return;
    end

    if isempty(perm_dist)
        warning('No permutation distribution found (StatClusters.posdistribution is empty).');
        return;
    end

    % Get Method Name (maxsum/maxsize) for label
    if isfield(data, 'Options') && isfield(data.Options, 'ClusterStatistic')
        statType = data.Options.ClusterStatistic; 
    end

    % --- 3. Prepare Plot ---
    hFig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1000, 600]);
    hold on;

    % A. Histogram of Null Distribution
    hHist = histogram(perm_dist, 50, 'Normalization', 'pdf', ...
                      'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none', ...
                      'DisplayName', 'Null Distribution');
    
    % B. Critical Threshold (95th percentile)
    cutoff_val = prctile(perm_dist, (1 - alpha) * 100);
    
    % Determine Y-axis height
    maxY = max(hHist.Values);
    if maxY == 0, maxY = 1; end
    maxY = maxY * 1.2; % Add headroom
    ylim([0, maxY]);

    % C. Threshold Line
    xline(cutoff_val, '--k', sprintf('Critical Cutoff (%.1f)', cutoff_val), ...
          'LineWidth', 2, 'LabelVerticalAlignment', 'top', ...
          'DisplayName', 'Alpha Threshold');

    % --- 4. Plot Observed Clusters ---
    hasSig = false;
    hasNonSig = false;

    for i = 1:length(obs_stats)
        val = obs_stats(i);
        p   = obs_pvals(i);

        if p < alpha
            % SIGNIFICANT: Red Line + Marker
            xline(val, 'Color', [0.85, 0.33, 0.1], 'LineWidth', 2);
            plot(val, maxY * 0.5, 'v', 'MarkerSize', 10, ...
                 'MarkerFaceColor', [0.85, 0.33, 0.1], 'MarkerEdgeColor', 'none', ...
                 'HandleVisibility', 'off');
            
            text(val, maxY * 0.55, sprintf('Sig: %.1f\n(p=%.3f)', val, p), ...
                 'Color', [0.85, 0.33, 0.1], 'FontSize', 9, 'FontWeight', 'bold', ...
                 'HorizontalAlignment', 'center');
            hasSig = true;
        else
            % NON-SIGNIFICANT: Faint Blue
            xline(val, 'Color', [0, 0.45, 0.74], 'LineWidth', 1, 'LineStyle', ':', ...
                  'Alpha', 0.5, 'HandleVisibility', 'off');
            hasNonSig = true;
        end
    end

    % --- 5. Fix X-Axis Scale ---
    currentX = xlim;
    maxObs = max([obs_stats, 0]);
    newMaxX = max(currentX(2), maxObs * 1.05);
    xlim([min(perm_dist), newMaxX]);

    % --- 6. Aesthetics & Save ---
    xlabel(sprintf('%s Value', statType));
    ylabel('Probability Density');
    
    % Apply the custom or default title
    % Interpreter 'none' ensures underscores (_) don't turn into subscripts
    title(plotTitle, 'Interpreter', 'none', 'FontSize', 12, 'FontWeight', 'bold');
    
    % Legend Logic
    legendItems = [hHist];
    legendLabels = {'Null Distribution'};
    
    if hasSig
        hSig = plot(nan, nan, 'Color', [0.85, 0.33, 0.1], 'LineWidth', 2);
        legendItems(end+1) = hSig; 
        legendLabels{end+1} = 'Significant Cluster';
    end
    if hasNonSig
        hNon = plot(nan, nan, 'Color', [0, 0.45, 0.74], 'LineStyle', ':', 'LineWidth', 1);
        legendItems(end+1) = hNon; 
        legendLabels{end+1} = 'Non-Sig Cluster';
    end
    
    legend(legendItems, legendLabels, 'Location', 'best');
    grid on; box on;

    % Save
    [~, fNameBase, ~] = fileparts(statFile);
    figPath = fullfile(outDir, [fNameBase, '_distribution.png']);
    saveas(hFig, figPath);
    close(hFig);

    % Metadata
    figMeta.alpha = alpha;
    figMeta.cutoff = cutoff_val;
    figMeta.nPerms = length(perm_dist);
    figMeta.maxObs = maxObs;
    figMeta.nSig = sum(obs_pvals < alpha);
end