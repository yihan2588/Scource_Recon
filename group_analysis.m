function group_analysis()
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
    strengthenDir = input('Enter the path to the STRENGTHEN folder: ', 's');
    if isempty(strengthenDir) || ~exist(strengthenDir, 'dir')
        error('STRENGTHEN directory not found or invalid. Exiting.');
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

    % --- Execution mode ---
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

    disp('=== Select the Protocol to Analyze ===');
    protocolNames = sort(protocolNames);
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
    iProtocol = bst_get('Protocol', selectedProtocolName);
    gui_brainstorm('SetCurrentProtocol', iProtocol);
    addLog(['Selected protocol: ', selectedProtocolName]);

    % --- Processing mode (must include source space) ---
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
    addLog(sprintf('Selected %d subjects to process: %s', numel(SubjectNames), strjoin(SubjectNames, ', ')));

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
        addLog(sprintf('Found nights for %s: %s', SubjName, strjoin(uniqueNightNames, ', ')));

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

                        for iSub = 1:numel(subjectsInGroup)
                            subj = subjectsInGroup{iSub};

                            filesA = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                                'subjectname',   'Group_analysis', ...
                                'condition',     condA, ...
                                'tag',           subj, ...
                                'includebad',    0, ...
                                'includeintra',  0, ...
                                'includecommon', 0, ...
                                'outprocesstab', 'process2a');
                            filesB = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                                'subjectname',   'Group_analysis', ...
                                'condition',     condB, ...
                                'tag',           subj, ...
                                'includebad',    0, ...
                                'includeintra',  0, ...
                                'includecommon', 0, ...
                                'outprocesstab', 'process2b');

                            if isempty(filesA) || isempty(filesB)
                                addLog(sprintf('WARNING: Missing files for %s (%s). Skipping subject.', subj, pair.name));
                                continue;
                            end

                            sFilesA{end+1} = filesA(1).FileName; %#ok<AGROW>
                            sFilesB{end+1} = filesB(1).FileName; %#ok<AGROW>
                        end

                        if numel(sFilesA) < 2 || numel(sFilesB) < 2
                            addLog(sprintf('Not enough data for %s %s (%s). Need >=2 subjects.', currentGroup, pair.name, nightName));
                            continue;
                        end

                        if numel(sFilesA) ~= numel(sFilesB)
                            addLog(sprintf('Unequal subject counts for %s %s. Skipping.', currentGroup, pair.name));
                            continue;
                        end

                        addLog(sprintf('Running cluster t-test: %s %s (%s)', currentGroup, pair.name, nightName));
                        statsResult = bst_process('CallProcess', 'process_ft_sourcestatistics', sFilesA, sFilesB, ...
                            'timewindow',     [-0.05, 0.05], ...
                            'scoutsel',       {}, ...
                            'scoutfunc',      1, ...
                            'isabs',          0, ...
                            'avgtime',        0, ...
                            'randomizations', 1000, ...
                            'statistictype',  1, ...
                            'tail',           'two', ...
                            'correctiontype', 2, ...
                            'minnbchan',      0, ...
                            'clusteralpha',   0.05);

                        if ~isempty(statsResult)
                            addLog(sprintf('   => Cluster test saved: %s', statsResult(1).FileName));
                        end
                    end
                end
            end
        end
    end

    addLog('Projected stage averages are ready. Continue with manual comparison and visualization steps.');
    addLog('=== Comparison Pipeline End (manual continuation required) ===');
    return;

end
