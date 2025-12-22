function group_analysis(opts)
    if nargin < 1 || isempty(opts)
        opts = struct();
    elseif ~isstruct(opts)
        error('group_analysis:InvalidInput', 'Options input must be provided as a struct.');
    end

    hasField = @(name) isfield(opts, name) && ~isempty(opts.(name));

    subjectNamesOverride = {};
    if hasField('subjectNames')
        subjVal = opts.subjectNames;
        if ischar(subjVal)
            subjectNamesOverride = {subjVal};
        elseif isstring(subjVal)
            subjectNamesOverride = cellstr(subjVal(:));
        elseif iscell(subjVal)
            subjectNamesOverride = cellfun(@(c) char(string(c)), subjVal(:), 'UniformOutput', false);
        else
            error('group_analysis:InvalidInput', 'subjectNames must be a character vector, string, or cell array of strings.');
        end
    end

    execModeOverride = [];
    if hasField('execMode')
        execModeOverride = opts.execMode;
    end

    processingModeOverride = [];
    if hasField('processingMode')
        processingModeOverride = opts.processingMode;
    end

    protocolOverride = '';
    if hasField('protocolName')
        protocolOverride = char(string(opts.protocolName));
    end

    strengthenOverride = '';
    if hasField('strengthenDir')
        strengthenOverride = char(string(opts.strengthenDir));
    end

    % BST_COMPARISON: Simplified post-processing to average and project sLORETA results.
    %
    % This streamlined workflow:
    %   1) Connects to an existing Brainstorm protocol.
    %   2) Lets the user pick subjects.
    %   3) For each subject/night/stage:
    %        - Averages all sLORETA results (mean absolute value).
    %        - Projects the averaged map to default anatomy (tagged *_avg_projected).
    %   4) Stops, leaving any comparisons/visualisation to be done manually in Brainstorm.

    % --- Setup ---
    automatedMode = ~isempty(strengthenOverride) || ~isempty(protocolOverride) || ~isempty(subjectNamesOverride) || ~isempty(execModeOverride) || ~isempty(processingModeOverride);

    if ~isempty(strengthenOverride)
        strengthenDir = strengthenOverride;
        if ~exist(strengthenDir, 'dir')
            error('group_analysis:InvalidStrengthenDir', 'Provided STRENGTHEN directory not found: %s', strengthenDir);
        end
    else
        strengthenDir = '';
        while isempty(strengthenDir) || ~exist(strengthenDir, 'dir')
            strengthenDir = strtrim(input('Enter the path to the STRENGTHEN folder: ', 's'));
            if isempty(strengthenDir)
                disp('STRENGTHEN directory path cannot be empty.');
            elseif ~exist(strengthenDir, 'dir')
                disp(['STRENGTHEN directory not found: ', strengthenDir]);
            end
        end
    end

    scriptDir = fileparts(mfilename('fullpath'));
    addpath(scriptDir);

    logName = fullfile(strengthenDir, 'comparison_run.log');
    logMessages = {};

    function addLog(msg)
        timestampStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        fullMsg = sprintf('[%s] %s', timestampStr, msg);
        disp(fullMsg);
        logMessages{end+1} = fullMsg; %#ok<AGROW>
        writeCumulativeLog(logName, logMessages);
    end

    addLog('=== Comparison Pipeline Start ===');

    runTimestamp = datestr(now, 'yyyymmdd_HHMMSS');
    outputRootDir = fullfile(strengthenDir, 'GroupAnalysisOutputs');
    if ~exist(outputRootDir, 'dir')
        mkdir(outputRootDir);
    end
    runOutputDir = fullfile(outputRootDir, ['run_' runTimestamp]);
    if ~exist(runOutputDir, 'dir')
        mkdir(runOutputDir);
    end
    addLog(['Run outputs directory: ', runOutputDir]);

    clusterAlpha = 0.05;          % Alpha used for cluster significance
    allNightNames = {};

    % --- Execution mode ---
    if ~isempty(execModeOverride)
        execMode = execModeOverride;
        if ~ismember(execMode, [1, 2])
            error('group_analysis:InvalidExecMode', 'Execution mode override must be 1 or 2.');
        end
        addLog(sprintf('Execution mode override set to %d.', execMode));
    elseif automatedMode
        execMode = 1;
        addLog('Execution mode defaulted to 1 (Average + Project) for automated run.');
    else
        disp(' ');
        disp('Select Execution Mode:');
        disp('1: Average + Project (recommended)');
        disp('2: Screenshot a Single Result');
        execMode = -1;
        while ~ismember(execMode, [1, 2])
            try
                execModeStr = input('Enter your choice (1-2) [1]: ', 's');
                if isempty(execModeStr), execModeStr = '1'; end
                execMode = str2double(execModeStr);
                if ~ismember(execMode, [1, 2])
                    disp('Invalid choice.');
                end
            catch
                disp('Invalid input.');
            end
        end
        addLog(sprintf('Execution mode selected interactively: %d.', execMode));
    end

    if ~brainstorm('status')
        addLog('Brainstorm not running. Starting in nogui mode...');
        brainstorm nogui;
        pause(5);
        addLog('Brainstorm started.');
    else
        addLog('Brainstorm already running.');
    end

    if execMode ~= 1
        addLog('Mode 2 (screenshot only) is disabled in this simplified workflow. Exiting.');
        return;
    end

    % --- Protocol selection ---
    protocolNames = {};
    DbDir = bst_get('BrainstormDbDir');
    if isempty(DbDir) || ~exist(DbDir, 'dir')
        addLog('ERROR: Brainstorm database directory not found. Exiting.');
        return;
    end

    dirContents = dir(DbDir);
    subDirs = dirContents([dirContents.isdir] & ~ismember({dirContents.name},{'.','..'}));
    for iDir = 1:length(subDirs)
        protocolMatPath = fullfile(DbDir, subDirs(iDir).name, 'data', 'protocol.mat');
        if exist(protocolMatPath, 'file')
            matData = load(protocolMatPath, 'ProtocolInfo');
            if isfield(matData, 'ProtocolInfo') && isfield(matData.ProtocolInfo, 'Comment')
                protocolNames{end+1} = matData.ProtocolInfo.Comment; %#ok<AGROW>
            end
        end
    end

    if isempty(protocolNames)
        addLog('ERROR: No existing protocols found. Please run source_recon first. Exiting.');
        return;
    end

    protocolNames = sort(protocolNames);

    if ~isempty(protocolOverride)
        matchIdx = find(strcmpi(protocolNames, protocolOverride), 1);
        if isempty(matchIdx)
            error('group_analysis:ProtocolNotFound', 'Protocol "%s" not found in Brainstorm database.', protocolOverride);
        end
        selectedProtocolName = protocolNames{matchIdx};
        addLog(sprintf('Protocol override matched: %s', selectedProtocolName));
    else
        disp('=== Select the Protocol to Analyze ===');
        for i = 1:numel(protocolNames)
            disp([num2str(i) ': ' protocolNames{i}]);
        end

        choiceNum = -1;
        while choiceNum < 1 || choiceNum > numel(protocolNames)
            try
                choiceStr = input(['Select protocol number (1-' num2str(numel(protocolNames)) '): '], 's');
                choiceNum = str2double(choiceStr);
                if isnan(choiceNum) || floor(choiceNum) ~= choiceNum
                    choiceNum = -1;
                    disp('Invalid input.');
                end
            catch
                choiceNum = -1;
                disp('Invalid input.');
            end
        end

        selectedProtocolName = protocolNames{choiceNum};
    end

    iProtocol = bst_get('Protocol', selectedProtocolName);
    gui_brainstorm('SetCurrentProtocol', iProtocol);
    addLog(['Selected protocol: ', selectedProtocolName]);

    % --- Processing mode (must include source space) ---
    if ~isempty(processingModeOverride)
        modeChoice = processingModeOverride;
        if ~ismember(modeChoice, [1, 2, 3])
            error('group_analysis:InvalidProcessingMode', 'Processing mode override must be 1, 2, or 3.');
        end
        addLog(sprintf('Processing mode override set to %d.', modeChoice));
    elseif automatedMode
        modeChoice = 1;
        addLog('Processing mode defaulted to 1 (Source space only) for automated run.');
    else
        disp(' ');
        disp('Select processing mode:');
        disp('1: Source space only');
        disp('2: Sensor space only');
        disp('3: Both');
        modeChoice = -1;
        while ~ismember(modeChoice, [1, 2, 3])
            try
                modeChoiceStr = input('Enter your choice (1-3) [1]: ', 's');
                if isempty(modeChoiceStr)
                    modeChoiceStr = '1';
                end
                modeChoice = str2double(modeChoiceStr);
                if ~ismember(modeChoice, [1, 2, 3])
                    disp('Invalid choice. Please enter 1, 2, or 3.');
                end
            catch
                disp('Invalid choice. Please enter 1, 2, or 3.');
            end
        end
        addLog(sprintf('Processing mode selected interactively: %d.', modeChoice));
    end

    do_source = ismember(modeChoice, [1, 3]);
    if ~do_source
        addLog('Source-space processing must be enabled for this workflow. Exiting.');
        return;
    end

    dataDir = fullfile(DbDir, selectedProtocolName, 'data');
    dirContents = dir(dataDir);
    subjDirs = dirContents([dirContents.isdir] & ~startsWith({dirContents.name}, {'.', '@'}));
    SubjectNames = {subjDirs.name};

    if isempty(SubjectNames)
        addLog('ERROR: No subject folders found in the protocol''s data directory. Exiting.');
        return;
    end
    addLog(sprintf('Found %d subjects in the protocol: %s', numel(SubjectNames), strjoin(SubjectNames, ', ')));

    disp(' ');
    disp('=== Available Subjects ===');
    for i = 1:numel(SubjectNames)
        disp([num2str(i) ': ' SubjectNames{i}]);
    end
    disp([num2str(numel(SubjectNames) + 1) ': Process All Subjects']);

    if ~isempty(subjectNamesOverride)
        SubjectNames = intersect(SubjectNames, subjectNamesOverride, 'stable');
        if isempty(SubjectNames)
            error('group_analysis:NoSubjects', 'None of the provided subjects exist in the selected protocol.');
        end
        addLog(sprintf('Subject override applied: %s', strjoin(SubjectNames, ', ')));
    else
        selectedIndices = [];
        while isempty(selectedIndices)
            try
                choiceStr = input(['Enter subject numbers to process (e.g., 1,3,5) or ' num2str(numel(SubjectNames) + 1) ' for all [all]: '], 's');
                if isempty(choiceStr)
                    choiceStr = num2str(numel(SubjectNames) + 1);
                end

                if str2double(choiceStr) == (numel(SubjectNames) + 1)
                    selectedIndices = 1:numel(SubjectNames);
                else
                    selectedIndices = str2num(choiceStr); %#ok<ST2NM>
                    if any(selectedIndices < 1) || any(selectedIndices > numel(SubjectNames)) || any(floor(selectedIndices) ~= selectedIndices)
                        disp('Invalid selection. Please enter valid numbers from the list.');
                        selectedIndices = [];
                    end
                end
            catch
                disp('Invalid input format.');
                selectedIndices = [];
            end
        end

        SubjectNames = SubjectNames(selectedIndices);
    end
    addLog(sprintf('Selected %d subjects to process: %s', numel(SubjectNames), strjoin(SubjectNames, ', ')));

    % --- User Configuration for Statistics ---
    if automatedMode
        clusterStatisticOption = 1;   % Default for automated mode
        nRandUser = -1;  % -1 means use automatic calculation
        addLog('Cluster statistic method defaulted to maxsum (1) for automated run.');
        addLog('Number of randomizations will be calculated automatically based on subjects.');
    else
        disp(' ');
        disp('=== Cluster Statistic Configuration ===');
        disp('Select cluster statistic method:');
        disp('1: maxsum (sum of t-values in cluster) - Default');
        disp('2: maxsize (count of significant samples)');
        disp('3: wcm (weighted cluster mass)');
        
        clusterStatisticOption = -1;
        while ~ismember(clusterStatisticOption, [1, 2, 3])
            try
                choiceStr = input('Enter your choice (1-3) [1]: ', 's');
                if isempty(choiceStr), choiceStr = '1'; end
                clusterStatisticOption = str2double(choiceStr);
                if ~ismember(clusterStatisticOption, [1, 2, 3])
                    disp('Invalid choice. Please enter 1, 2, or 3.');
                end
            catch
                disp('Invalid input.');
            end
        end
        
        methodNames = {'maxsum', 'maxsize', 'wcm'};
        addLog(sprintf('Cluster statistic method: %s', methodNames{clusterStatisticOption}));
        
        % Number of randomizations
        disp(' ');
        disp('Number of randomizations can be:');
        disp('  - Specified manually (recommended >= 1000)');
        disp('  - Calculated automatically based on number of subjects (2^n)');
        nRandUser = -1;
        while nRandUser < 0
            try
                nRandStr = input('Enter number of randomizations [auto]: ', 's');
                if isempty(nRandStr) || strcmpi(nRandStr, 'auto')
                    nRandUser = -1;  % Use automatic calculation
                    break;
                end
                nRandUser = str2double(nRandStr);
                if isnan(nRandUser) || nRandUser < 100
                    disp('Please enter a number >= 100, or press Enter for automatic calculation.');
                    nRandUser = -1;
                end
            catch
                disp('Invalid input.');
            end
        end
        
        if nRandUser == -1
            addLog('Number of randomizations will be calculated automatically (2^n based on subjects).');
        else
            addLog(sprintf('Number of randomizations set to: %d', nRandUser));
        end
    end

    for iSubj = 1:numel(SubjectNames)
        SubjName = SubjectNames{iSubj};
        addLog(sprintf('--- Starting Subject %d/%d: %s ---', iSubj, numel(SubjectNames), SubjName));

        subjDir = fullfile(dataDir, SubjName);
        condDirContents = dir(subjDir);
        condDirs = condDirContents([condDirContents.isdir] & ~startsWith({condDirContents.name}, {'.', '@'}));
        condNames = {condDirs.name};
        condNamesForNightDetection = condNames(~contains(condNames, '_vs_'));

        nightNames = {};
        for iCond = 1:numel(condNamesForNightDetection)
            parts = strsplit(condNamesForNightDetection{iCond}, '_');
            if numel(parts) > 1
                nightNames{end+1} = parts{1}; %#ok<AGROW>
            end
        end
        uniqueNightNames = unique(nightNames);
        if isempty(uniqueNightNames)
            addLog(sprintf('No night folders detected for %s. Skipping subject.', SubjName));
            continue;
        end
        addLog(sprintf('Found nights for %s: %s', SubjName, strjoin(uniqueNightNames, ', ')));
        allNightNames = union(allNightNames, uniqueNightNames, 'stable');

        for iNight = 1:numel(uniqueNightNames)
            NightName = uniqueNightNames{iNight};
            addLog(sprintf('Processing Night: %s', NightName));

            stages = {'pre-stim', 'stim', 'post-stim'};

            addLog('Step 1: Averaging sLORETA results...');
            for iStage = 1:numel(stages)
                stage = stages{iStage};
                condition = [NightName, '_', stage];
                avg_tag = [stage, '_avg'];

                sFiles_select = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                    'subjectname', SubjName, ...
                    'condition',   condition, ...
                    'tag',         'sLORETA', ...
                    'outprocesstab', 'process1');

                if isempty(sFiles_select)
                    addLog(sprintf('WARNING: No sLORETA files found for %s. Skipping averaging.', condition));
                    continue;
                end

                sFiles_avg = bst_process('CallProcess', 'process_average', sFiles_select, [], ...
                    'avgtype',    1, ...
                    'avg_func',   2, ...
                    'weighted',   0);

                bst_process('CallProcess', 'process_add_tag', sFiles_avg, [], ...
                    'tag',      avg_tag, ...
                    'output',   'name');
                addLog(sprintf('   => Created average file with tag: %s', avg_tag));
            end

            addLog('Step 1.5: Projecting averaged sources to default anatomy...');
            for iStage = 1:numel(stages)
                stage = stages{iStage};
                condition = [NightName, '_', stage];
                avg_tag = [stage, '_avg'];
                projected_tag = [stage, '_avg_projected'];

                sFiles_avg = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                    'subjectname', SubjName, ...
                    'condition',   condition, ...
                    'tag',         avg_tag);

                if isempty(sFiles_avg)
                    addLog(sprintf('WARNING: No averaged file found for projection: %s', avg_tag));
                    continue;
                end

                try
                    sFiles_projected = bst_process('CallProcess', 'process_project_sources', sFiles_avg, [], ...
                        'headmodeltype', 'surface');

                    if ~isempty(sFiles_projected)
                        bst_process('CallProcess', 'process_add_tag', sFiles_projected, [], ...
                            'tag', projected_tag, ...
                            'output', 'name');
                        addLog(sprintf('   => Projected %s to default anatomy with tag: %s', stage, projected_tag));
                    end
                catch ME
                    addLog(sprintf('WARNING: Failed to project %s: %s', stage, ME.message));
                end
            end

            addLog('Step 1 complete: stage averages projected to default anatomy.');
        end
    end

    % --- Group-level selection and statistics ---
    groupLookupPath = fullfile(scriptDir, 'Assets', 'group_lookup.json');
    if ~exist(groupLookupPath, 'file')
        addLog(sprintf('Group lookup not found at %s. Skipping group analyses.', groupLookupPath));
    else
        try
            groupLookup = jsondecode(fileread(groupLookupPath));
        catch ME
            addLog(sprintf('ERROR: Failed to parse group lookup (%s). Error: %s', groupLookupPath, ME.message));
            groupLookup = struct();
        end

        groupSubjects = fieldnames(groupLookup);
        groupLabels = cellfun(@string, struct2cell(groupLookup), 'UniformOutput', false);
        uniqueGroups = unique(string(groupLabels));

        if ~isempty(uniqueGroups)
            stagePairs = struct( ...
                'name',    {'Stim_vs_Pre', 'Post_vs_Pre'}, ...
                'stageA',  {'stim',        'post-stim'}, ...
                'stageB',  {'pre-stim',    'pre-stim'});

            if isempty(allNightNames)
                allNightNames = {'Night1'};
            end

            for iNight = 1:numel(allNightNames)
                nightName = allNightNames{iNight};
                addLog(sprintf('Evaluating group statistics for night: %s', nightName));
                for iGroup = 1:numel(uniqueGroups)
                    currentGroup = uniqueGroups(iGroup);
                    groupMask = strcmpi(string(groupLabels), currentGroup);
                    subjectsInGroup = intersect(SubjectNames, groupSubjects(groupMask));
                    if isempty(subjectsInGroup)
                        addLog(sprintf('No subjects available for group %s. Skipping.', currentGroup));
                        continue;
                    end

                    for iPair = 1:numel(stagePairs)
                        pair = stagePairs(iPair);
                        condA = sprintf('%s_%s', nightName, pair.stageA);
                        condB = sprintf('%s_%s', nightName, pair.stageB);

                        sFilesA = {};
                        sFilesB = {};

                        projectedTagA = [pair.stageA, '_avg_projected'];
                        projectedTagB = [pair.stageB, '_avg_projected'];

                        for iSub = 1:numel(subjectsInGroup)
                            subj = subjectsInGroup{iSub};

                            fileA = select_projected_subject_file(subj, condA, projectedTagA, 'process2a');
                            fileB = select_projected_subject_file(subj, condB, projectedTagB, 'process2b');

                            if isempty(fileA) || isempty(fileB)
                                addLog(sprintf('WARNING: Missing projected files for %s (%s). Skipping subject.', subj, pair.name));
                                continue;
                            end

                            sFilesA{end+1} = fileA.FileName; %#ok<AGROW>
                            sFilesB{end+1} = fileB.FileName; %#ok<AGROW>
                        end

                        if numel(sFilesA) < 2 || numel(sFilesB) < 2
                            addLog(sprintf('Not enough data for %s %s (%s). Need >=2 subjects.', currentGroup, pair.name, nightName));
                            continue;
                        end

                        if numel(sFilesA) ~= numel(sFilesB)
                            addLog(sprintf('Unequal subject counts for %s %s. Skipping.', currentGroup, pair.name));
                            continue;
                        end

                        subjectsProvided = numel(subjectsInGroup);
                        subjectsUsed = numel(sFilesA);
                        if subjectsUsed ~= subjectsProvided
                            addLog(sprintf('NOTE: Using %d/%d subjects for %s %s (%s) due to missing projected files.', subjectsUsed, subjectsProvided, currentGroup, pair.name, nightName));
                        end
                        
                        % Determine number of randomizations
                        if nRandUser == -1
                            % Automatic calculation based on subjects
                            nRandBase = max(subjectsUsed, subjectsProvided);
                            nRand = max(1, 2 ^ nRandBase);
                        else
                            % Use user-specified value
                            nRand = nRandUser;
                        end
                        addLog(sprintf('Running cluster t-test: %s %s (%s) with %d permutations (subjects used=%d)', currentGroup, pair.name, nightName, nRand, subjectsUsed));
                        statsResult = bst_process('CallProcess', 'process_ft_sourcestatistics', sFilesA, sFilesB, ...
                            'timewindow',     [0, 0], ...
                            'scoutsel',       {}, ...
                            'scoutfunc',      1, ...
                            'isabs',          0, ...
                            'avgtime',        0, ...
                            'randomizations', nRand, ...
                            'statistictype',  2, ...
                            'tail',           'one+', ...
                            'correctiontype', 2, ...
                            'minnbchan',      0, ...
                            'clusteralpha',   clusterAlpha, ...
                            'clusterstatistic', clusterStatisticOption);

                        if ~isempty(statsResult)
                            % Apply group/stage tag to the newly created stat maps BEFORE logging
                            statTag = sprintf('%s_%s_%s', currentGroup, pair.name, nightName);
                            try
                                bst_process('CallProcess', 'process_add_tag', statsResult, [], ...
                                    'tag',      statTag, ...
                                    'output',   'name');
                                addLog(sprintf('   => Cluster test saved and tagged (%s): %s', statTag, statsResult(1).FileName));
                            catch ME_tag
                                addLog(sprintf('WARNING: Cluster test saved but failed to tag %s (%s): %s', statsResult(1).FileName, statTag, ME_tag.message));
                            end

                            statFilesGenerated = {statsResult.FileName};
                            contextLabel = statTag;
                            outputs = build_group_analysis_outputs(statFilesGenerated, runOutputDir, clusterAlpha, contextLabel);
                            if ~isempty(outputs)
                                for iOut = 1:numel(outputs)
                                    logSummary = sprintf('      Plot: %s | Summary JSON: %s | TXT: %s', ...
                                        local_or_empty(outputs(iOut).distributionFigure), ...
                                        local_or_empty(outputs(iOut).summaryJson), ...
                                        local_or_empty(outputs(iOut).summaryTxt));
                                    addLog(logSummary);
                                end
                            end
                        end


                    end
                end
            end
        end
    end

    addLog('Cluster statistics, plots, and summaries generated.');
    addLog(['Outputs stored under: ', runOutputDir]);
    addLog('=== Comparison Pipeline End ===');
    return;

end

function fileStruct = select_projected_subject_file(subj, conditionName, projectedTag, processTab)
    % Helper to select a single projected file for a subject-condition pair.
    % Prefers the newest matching entry if duplicates exist.

    sFiles = bst_process('CallProcess', 'process_select_files_results', [], [], ...
        'subjectname',   'Group_analysis', ...
        'condition',     conditionName, ...
        'tag',           projectedTag, ...
        'includebad',    0, ...
        'includeintra',  0, ...
        'includecommon', 0, ...
        'outprocesstab', processTab);

    if isempty(sFiles)
        fileStruct = struct();
        return;
    end

    % Filter to the specific subject tagged during projection. Some comments use "<Stage> | <Subject>" order, so check both patterns.
    subj = string(subj);
    subjMatches = arrayfun(@(f) local_comment_matches_subject(f.Comment, subj), sFiles);
    sFiles = sFiles(subjMatches);

    if isempty(sFiles)
        fileStruct = struct();
        return;
    end

    % Select the most recent file if metadata is available; otherwise take the last entry
    if numel(sFiles) > 1
        if all(isfield(sFiles, 'LastModified'))
            try
                [~, idxNewest] = max(datenum({sFiles.LastModified}));
                fileStruct = sFiles(idxNewest);
                return;
            catch
                % Fall through to default selection if timestamps cannot be parsed
            end
        end
        fileStruct = sFiles(end);
    else
        fileStruct = sFiles(1);
    end
end

function isMatch = local_comment_matches_subject(commentStr, subj)
    if isempty(commentStr)
        isMatch = false;
        return;
    end

    tokens = split(string(commentStr), "|");
    tokens = strtrim(tokens);

    subjectMatches = strcmpi(tokens, subj) | contains(tokens, subj, 'IgnoreCase', true);
    directMatch = contains(commentStr, subj, 'IgnoreCase', true);

    isMatch = any(subjectMatches) || directMatch;
end

function txt = local_or_empty(strVal)
    if isempty(strVal)
        txt = '<none>';
    else
        txt = strVal;
    end
end
