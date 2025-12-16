function stat_test()
    % STAT_TEST: Lightweight cluster permutation testing script
    %
    % This streamlined workflow assumes averaging and projection are already complete.
    % It focuses solely on running cluster-based permutation statistics on existing
    % projected averaged source maps.
    %
    % Workflow:
    %   1) Connects to an existing Brainstorm protocol
    %   2) Lets the user pick subjects
    %   3) Lets the user select cluster statistic method (maxsum/maxsize/wcm)
    %   4) Lets the user configure number of randomizations
    %   5) Runs cluster permutation tests on _avg_projected files
    %   6) Generates plots, summaries, and JSON outputs

    % --- Setup ---
    strengthenDir = input('Enter the path to the STRENGTHEN folder: ', 's');
    if isempty(strengthenDir) || ~exist(strengthenDir, 'dir')
        error('STRENGTHEN directory not found or invalid. Exiting.');
    end

    scriptDir = fileparts(mfilename('fullpath'));
    addpath(scriptDir);

    logName = fullfile(strengthenDir, 'stat_test_run.log');
    logMessages = {};

    function addLog(msg)
        timestampStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        fullMsg = sprintf('[%s] %s', timestampStr, msg);
        disp(fullMsg);
        logMessages{end+1} = fullMsg; %#ok<AGROW>
        writeCumulativeLog(logName, logMessages);
    end

    addLog('=== Stat Test Pipeline Start ===');

    runTimestamp = datestr(now, 'yyyymmdd_HHMMSS');
    outputRootDir = fullfile(strengthenDir, 'StatTestOutputs');
    if ~exist(outputRootDir, 'dir')
        mkdir(outputRootDir);
    end
    runOutputDir = fullfile(outputRootDir, ['run_' runTimestamp]);
    if ~exist(runOutputDir, 'dir')
        mkdir(runOutputDir);
    end
    addLog(['Run outputs directory: ', runOutputDir]);

    % --- User Configuration for Statistics ---
    disp(' ');
    disp('=== Cluster Statistic Configuration ===');
    disp('Select cluster statistic method:');
    disp('1: maxsum (sum of all vertexe t-values in cluster)');
    disp('2: maxsize (count of vertexes in cluster)');
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
    nRand = -1;
    while nRand < 100
        try
            nRandStr = input('Enter number of randomizations [1000]: ', 's');
            if isempty(nRandStr), nRandStr = '1000'; end
            nRand = str2double(nRandStr);
            if isnan(nRand) || nRand < 100
                disp('Please enter a number >= 100.');
                nRand = -1;
            end
        catch
            disp('Invalid input.');
        end
    end
    addLog(sprintf('Number of randomizations: %d', nRand));

    % Cluster alpha
    disp(' ');
    clusterAlpha = -1;
    while clusterAlpha <= 0 || clusterAlpha >= 1
        try
            alphaStr = input('Enter cluster alpha value [0.05]: ', 's');
            if isempty(alphaStr), alphaStr = '0.05'; end
            clusterAlpha = str2double(alphaStr);
            if isnan(clusterAlpha) || clusterAlpha <= 0 || clusterAlpha >= 1
                disp('Please enter a value between 0 and 1.');
                clusterAlpha = -1;
            end
        catch
            disp('Invalid input.');
        end
    end
    addLog(sprintf('Cluster alpha: %.3f', clusterAlpha));

    % Night names configuration
    disp(' ');
    nightNamesStr = input('Enter night names (comma-separated) [Night1]: ', 's');
    if isempty(nightNamesStr)
        allNightNames = {'Night1'};
    else
        allNightNames = strtrim(split(nightNamesStr, ','));
    end
    addLog(sprintf('Night names: %s', strjoin(allNightNames, ', ')));

    % --- Start Brainstorm ---
    if ~brainstorm('status')
        addLog('Brainstorm not running. Starting in nogui mode...');
        brainstorm nogui;
        pause(5);
        addLog('Brainstorm started.');
    else
        addLog('Brainstorm already running.');
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

    disp(' ');
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

    % --- Subject Selection ---
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

    % --- Load group lookup ---
    groupLookupPath = fullfile(scriptDir, 'Assets', 'group_lookup.json');
    if ~exist(groupLookupPath, 'file')
        addLog(sprintf('Group lookup not found at %s. Exiting.', groupLookupPath));
        return;
    end

    try
        groupLookup = jsondecode(fileread(groupLookupPath));
    catch ME
        addLog(sprintf('ERROR: Failed to parse group lookup (%s). Error: %s', groupLookupPath, ME.message));
        return;
    end

    groupSubjects = fieldnames(groupLookup);
    groupLabels = cellfun(@string, struct2cell(groupLookup), 'UniformOutput', false);
    uniqueGroups = unique(string(groupLabels));

    if isempty(uniqueGroups)
        addLog('ERROR: No groups found in group_lookup.json. Exiting.');
        return;
    end

    addLog(sprintf('Found %d unique groups: %s', numel(uniqueGroups), strjoin(uniqueGroups, ', ')));

    % --- Run Statistics ---
    addLog('=== Starting Cluster Permutation Tests ===');
    
    stagePairs = struct( ...
        'name',    {'Stim_vs_Pre', 'Post_vs_Pre'}, ...
        'stageA',  {'stim',        'post-stim'}, ...
        'stageB',  {'pre-stim',    'pre-stim'});

    for iNight = 1:numel(allNightNames)
        nightName = allNightNames{iNight};
        addLog(sprintf('Processing Night: %s', nightName));
        
        for iGroup = 1:numel(uniqueGroups)
            currentGroup = uniqueGroups(iGroup);
            groupMask = strcmpi(string(groupLabels), currentGroup);
            subjectsInGroup = intersect(SubjectNames, groupSubjects(groupMask));
            
            if isempty(subjectsInGroup)
                addLog(sprintf('No subjects available for group %s. Skipping.', currentGroup));
                continue;
            end
            
            addLog(sprintf('Group: %s (%d subjects)', currentGroup, numel(subjectsInGroup)));

            for iPair = 1:numel(stagePairs)
                pair = stagePairs(iPair);
                condA = sprintf('%s_%s', nightName, pair.stageA);
                condB = sprintf('%s_%s', nightName, pair.stageB);

                addLog(sprintf('   Comparison: %s vs %s', condA, condB));

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
                        addLog(sprintf('      WARNING: Missing files for %s (%s). Skipping subject.', subj, pair.name));
                        continue;
                    end

                    sFilesA{end+1} = filesA(1).FileName; %#ok<AGROW>
                    sFilesB{end+1} = filesB(1).FileName; %#ok<AGROW>
                end

                if numel(sFilesA) < 2 || numel(sFilesB) < 2
                    addLog(sprintf('      Not enough data for %s %s (%s). Need >=2 subjects. Found: A=%d, B=%d', ...
                        currentGroup, pair.name, nightName, numel(sFilesA), numel(sFilesB)));
                    continue;
                end

                if numel(sFilesA) ~= numel(sFilesB)
                    addLog(sprintf('      Unequal subject counts for %s %s. A=%d, B=%d. Skipping.', ...
                        currentGroup, pair.name, numel(sFilesA), numel(sFilesB)));
                    continue;
                end

                addLog(sprintf('      Running cluster t-test: %s %s (%s) with %d subjects', ...
                    currentGroup, pair.name, nightName, numel(sFilesA)));
                
                try
                    statsResult = bst_process('CallProcess', 'process_ft_sourcestatistics', sFilesA, sFilesB, ...
                        'timewindow',         [0, 0], ...
                        'scoutsel',           {}, ...
                        'scoutfunc',          1, ...
                        'isabs',              0, ...
                        'avgtime',            0, ...
                        'randomizations',     nRand, ...
                        'statistictype',      2, ...
                        'tail',               'one+', ...
                        'correctiontype',     2, ...
                        'minnbchan',          0, ...
                        'clusteralpha',       clusterAlpha, ...
                        'clusterstatistic',   clusterStatisticOption);

                    if ~isempty(statsResult)
                        addLog(sprintf('      => Cluster test saved: %s', statsResult(1).FileName));
                        statFilesGenerated = {statsResult.FileName};
                        
                        % Generate outputs
                        outputs = build_group_analysis_outputs(statFilesGenerated, runOutputDir, clusterAlpha);
                        if ~isempty(outputs)
                            for iOut = 1:numel(outputs)
                                logSummary = sprintf('         Plot: %s | Summary JSON: %s | TXT: %s', ...
                                    local_or_empty(outputs(iOut).distributionFigure), ...
                                    local_or_empty(outputs(iOut).summaryJson), ...
                                    local_or_empty(outputs(iOut).summaryTxt));
                                addLog(logSummary);
                            end
                        end
                    else
                        addLog('      WARNING: Statistics returned empty result.');
                    end
                catch ME
                    addLog(sprintf('      ERROR: Statistics failed: %s', ME.message));
                end
            end
        end
    end

    addLog('Cluster statistics, plots, and summaries generated.');
    addLog(['Outputs stored under: ', runOutputDir]);
    addLog('=== Stat Test Pipeline End ===');
    return;

end

function txt = local_or_empty(strVal)
    if isempty(strVal)
        txt = '<none>';
    else
        txt = strVal;
    end
end

function writeCumulativeLog(logPath, messages)
    % Write all accumulated messages to the log file
    try
        fid = fopen(logPath, 'w');
        if fid == -1
            warning('Could not open log file: %s', logPath);
            return;
        end
        for i = 1:numel(messages)
            fprintf(fid, '%s\n', messages{i});
        end
        fclose(fid);
    catch ME
        warning('Error writing log: %s', ME.message);
    end
end