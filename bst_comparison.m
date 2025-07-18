function bst_comparison()
    % BST_COMPARISON: Post-processing pipeline for source_recon results.
    %
    % LOGIC:
    %   1) Connect to an existing Brainstorm protocol.
    %   2) Identify subjects and nights that have been processed.
    %   3) For each subject/night:
    %       a) Average (abs value) all sLORETA results for each stage (pre, stim, post).
    %       b) Perform power percentage change comparisons (A^2-B^2)/B^2 for:
    %          - Stim vs. Pre
    %          - Post vs. Stim
    %          - Post vs. Pre
    %       c) Save comparison results to new conditions.
    %       d) Take contact sheet screenshots of all averaged and comparison maps.

    % --- Setup ---
    % Prompt user for the STRENGTHEN directory path
    strengthenDir = input('Enter the path to the STRENGTHEN folder: ', 's');
    if isempty(strengthenDir) || ~exist(strengthenDir, 'dir')
        error('STRENGTHEN directory not found or invalid. Exiting.');
    end

    % Get directory of this script
    scriptDir = fileparts(mfilename('fullpath'));
    addpath(scriptDir);

    % Setup cumulative logging
    logName = fullfile(strengthenDir, 'comparison_run.log');
    logMessages = {};

    function addLog(msg)
        timestampStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        fullMsg = sprintf('[%s] %s', timestampStr, msg);
        disp(fullMsg);
        logMessages{end+1} = fullMsg;
        writeCumulativeLog(logName, logMessages);
    end

    addLog('=== Comparison Pipeline Start ===');

    % --- Ask for main execution mode ---
    disp(' ');
    disp('Select Execution Mode:');
    disp('1: Run Full Comparison Pipeline');
    disp('2: Screenshot a Single Result');
    execMode = -1;
    while ~ismember(execMode, [1, 2])
        try
            execModeStr = input('Enter your choice (1-2) [1]: ', 's');
            if isempty(execModeStr), execModeStr = '1'; end
            execMode = str2double(execModeStr);
            if ~ismember(execMode, [1, 2]), disp('Invalid choice.'); end
        catch
            disp('Invalid input.');
        end
    end

    % Ensure Brainstorm is running
    if ~brainstorm('status')
        addLog('Brainstorm not running. Starting in nogui mode...');
        brainstorm nogui;
        pause(5);
        addLog('Brainstorm started.');
    else
        addLog('Brainstorm already running.');
    end

if execMode == 1
    % =================================================
    % === MODE 1: FULL COMPARISON PIPELINE
    % =================================================
    addLog('Executing Full Comparison Pipeline...');

    % --- Protocol Selection ---
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
                protocolNames{end+1} = matData.ProtocolInfo.Comment;
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

    % --- Ask user for processing mode ---
    disp(' ');
    disp('Select processing mode:');
    disp('1: Source space only');
    disp('2: Sensor space only');
    disp('3: Both');
    modeChoice = -1;
    while ~ismember(modeChoice, [1, 2, 3])
        try
            modeChoiceStr = input('Enter your choice (1-3) [3]: ', 's');
            if isempty(modeChoiceStr)
                modeChoiceStr = '3';
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
    do_sensor = ismember(modeChoice, [2, 3]);
    addLog(sprintf('Processing mode set: Source=%d, Sensor=%d', do_source, do_sensor));

    % --- Get Subjects and Nights from Protocol ---
    dataDir = fullfile(DbDir, selectedProtocolName, 'data');
    dirContents = dir(dataDir);
    % Filter for directories, excluding '.', '..', and special '@' folders
    subjDirs = dirContents([dirContents.isdir] & ~startsWith({dirContents.name}, {'.', '@'}));
    SubjectNames = {subjDirs.name};
    
    if isempty(SubjectNames)
        addLog('ERROR: No subject folders found in the protocol''s data directory. Exiting.');
        return;
    end
    addLog(sprintf('Found %d subjects in the protocol: %s', numel(SubjectNames), strjoin(SubjectNames, ', ')));

    % --- Allow user to select subjects ---
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
    
    SubjectNames = SubjectNames(selectedIndices); % Overwrite the list with the selected subjects
    addLog(sprintf('Selected %d subjects to process: %s', numel(SubjectNames), strjoin(SubjectNames, ', ')));

    % --- Ask for Group Analysis ---
    addLog('ENTERING GROUP ANALYSIS SECTION'); % Debug checkpoint
    do_group_analysis = false;
    activeSubjects = {};
    shamSubjects = {};
    
    addLog(sprintf('DEBUG: do_source type=%s, value=%s', class(do_source), mat2str(do_source)));
    addLog(sprintf('DEBUG: numel(SubjectNames) type=%s, value=%s', class(numel(SubjectNames)), mat2str(numel(SubjectNames))));
    addLog(sprintf('DEBUG: Condition evaluation: %s && %s > 1 = %s', mat2str(do_source), mat2str(numel(SubjectNames)), mat2str(do_source && numel(SubjectNames) > 1)));
    
    if do_source && numel(SubjectNames) > 1
        addLog('Group analysis conditions met - prompting user...');
        disp(' ');
        disp('=== GROUP ANALYSIS OPTION ===');
        groupChoice = '';
        while ~ismember(lower(groupChoice), {'y', 'yes', 'n', 'no'})
            groupChoice = input('Perform group analysis? (y/n) [n]: ', 's');
            if isempty(groupChoice)
                groupChoice = 'n';
            end
            addLog(sprintf('User entered: "%s"', groupChoice));
        end
        addLog(sprintf('Final group choice: "%s"', groupChoice));
        
        if ismember(lower(groupChoice), {'y', 'yes'})
            do_group_analysis = true;
            addLog('Group analysis enabled');
            
            % Get Active group subjects
            activeStr = '';
            while isempty(activeStr)
                activeStr = input('Active group subjects (comma-separated numbers, e.g., 102,108,109): ', 's');
                if isempty(activeStr)
                    disp('Active group cannot be empty.');
                end
            end
            activeNumbers = strtrim(strsplit(activeStr, ','));
            
            % Get Sham group subjects  
            shamStr = '';
            while isempty(shamStr)
                shamStr = input('Sham group subjects (comma-separated numbers, e.g., 107,110): ', 's');
                if isempty(shamStr)
                    disp('Sham group cannot be empty.');
                end
            end
            shamNumbers = strtrim(strsplit(shamStr, ','));
            
            % Convert numbers to full subject names
            activeSubjects = {};
            for i = 1:numel(activeNumbers)
                fullName = ['Subject_' activeNumbers{i}];
                if ismember(fullName, SubjectNames)
                    activeSubjects{end+1} = fullName;
                else
                    addLog(['WARNING: Subject not found: ' fullName]);
                end
            end
            
            shamSubjects = {};
            for i = 1:numel(shamNumbers)
                fullName = ['Subject_' shamNumbers{i}];
                if ismember(fullName, SubjectNames)
                    shamSubjects{end+1} = fullName;
                else
                    addLog(['WARNING: Subject not found: ' fullName]);
                end
            end
            
            % Validate that we have subjects in both groups
            if isempty(activeSubjects)
                addLog('ERROR: No valid active subjects found.');
                do_group_analysis = false;
            end
            if isempty(shamSubjects)
                addLog('ERROR: No valid sham subjects found.');
                do_group_analysis = false;
            end
            
            addLog(sprintf('Active group (%d subjects): %s', numel(activeSubjects), strjoin(activeSubjects, ', ')));
            addLog(sprintf('Sham group (%d subjects): %s', numel(shamSubjects), strjoin(shamSubjects, ', ')));
        end
    end

    % --- Get User-Defined Bounds for Comparisons ---
    user_bound = [];
    while isempty(user_bound) || user_bound <= 0
        try
            boundStr = input('Enter comparison bounds (e.g., 50 for ±50%) [50]: ', 's');
            if isempty(boundStr)
                user_bound = 50; % Default
                disp('Using default bound: 50%');
                break;
            end
            user_bound = str2double(boundStr);
            if isnan(user_bound) || user_bound <= 0
                disp('Please enter a positive number.');
                user_bound = [];
            end
        catch
            disp('Invalid input. Please enter a positive number.');
            user_bound = [];
        end
    end
    addLog(sprintf('Using comparison bounds: ±%g%%', user_bound));


    % --- Main Loop ---
    for iSubj = 1:numel(SubjectNames)
        SubjName = SubjectNames{iSubj};
        addLog(sprintf('--- Starting Subject %d/%d: %s ---', iSubj, numel(SubjectNames), SubjName));

        % Find nights for this subject by inspecting condition folder names
        subjDir = fullfile(dataDir, SubjName);
        condDirContents = dir(subjDir);
        condDirs = condDirContents([condDirContents.isdir] & ~startsWith({condDirContents.name}, {'.', '@'}));
        condNames = {condDirs.name};
        % Exclude comparison conditions from previous runs from night detection
        condNamesForNightDetection = condNames(~contains(condNames, '_vs_'));
        
        nightNames = {};
        for iCond = 1:numel(condNamesForNightDetection)
            parts = strsplit(condNamesForNightDetection{iCond}, '_');
            if numel(parts) > 1
                nightNames{end+1} = parts{1};
            end
        end
        uniqueNightNames = unique(nightNames);
        addLog(sprintf('Found nights for %s: %s', SubjName, strjoin(uniqueNightNames, ', ')));

        for iNight = 1:numel(uniqueNightNames)
            NightName = uniqueNightNames{iNight};
            addLog(sprintf('Processing Night: %s', NightName));
            
            % Define stages and comparison pairs
            stages = {'pre-stim', 'stim', 'post-stim'};
            comparisons = {
                {'stim', 'pre-stim', 'Stim_vs_Pre'}, ...
                {'post-stim', 'stim', 'Post_vs_Stim'}, ...
                {'post-stim', 'pre-stim', 'Post_vs_Pre'}  ...
            };
            
            % Define a base output directory
            baseOutputDir = fullfile(strengthenDir, 'contact_sheet_stages_comparison', SubjName, NightName);

            if do_source
                % --- Step 1: Average sLORETA results for each stage ---
                addLog('Step 1: Averaging sLORETA results...');
            for iStage = 1:numel(stages)
                stage = stages{iStage};
                condition = [NightName, '_', stage];
                avg_tag = [stage, '_avg'];
                
                addLog(sprintf('Averaging stage: %s', stage));
                
                % Select all sLORETA results in the condition
                sFiles_select = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                    'subjectname', SubjName, ...
                    'condition',   condition, ...
                    'tag',         'sLORETA', ...
                    'outprocesstab', 'process1');
                
                if isempty(sFiles_select)
                    addLog(sprintf('WARNING: No sLORETA files found for %s. Skipping averaging.', condition));
                    continue;
                end

                % Average (absolute value)
                sFiles_avg = bst_process('CallProcess', 'process_average', sFiles_select, [], ...
                    'avgtype',    1, ...  % Everything
                    'avg_func',   2, ...  % mean(abs(x))
                    'weighted',   0);
                
                % Add tag
                bst_process('CallProcess', 'process_add_tag', sFiles_avg, [], ...
                    'tag',      avg_tag, ...
                    'output',   'name');
                    
                addLog(sprintf('   => Created average file with tag: %s', avg_tag));
            end

            % --- Step 1.5: Project averaged sources to default anatomy ---
            addLog('Step 1.5: Projecting averaged sources to default anatomy...');
            for iStage = 1:numel(stages)
                stage = stages{iStage};
                condition = [NightName, '_', stage];
                avg_tag = [stage, '_avg'];
                projected_tag = [stage, '_avg_projected'];
                
                % Find the averaged file
                sFiles_avg = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                    'subjectname', SubjName, ...
                    'condition',   condition, ...
                    'tag',         avg_tag);
                
                if isempty(sFiles_avg)
                    addLog(sprintf('WARNING: No averaged file found for projection: %s', avg_tag));
                    continue;
                end
                
                try
                    % Project to default anatomy - let Brainstorm figure out the default
                    sFiles_projected = bst_process('CallProcess', 'process_project_sources', sFiles_avg, [], ...
                        'headmodeltype', 'surface');  % Cortex surface
                    
                    if ~isempty(sFiles_projected)
                        % Add projected tag to the new file
                        bst_process('CallProcess', 'process_add_tag', sFiles_projected, [], ...
                            'tag', projected_tag, ...
                            'output', 'name');
                        addLog(sprintf('   => Projected %s to default anatomy with tag: %s', stage, projected_tag));
                    end
                catch ME
                    addLog(sprintf('WARNING: Failed to project %s: %s', stage, ME.message));
                end
            end

            % --- Step 2: Perform Comparisons ---
            addLog('Step 2: Performing power difference comparisons...');
            comparison_results = {}; % Cell array to store handles to the new results
            for iComp = 1:numel(comparisons)
                comp_pair = comparisons{iComp};
                stageA_name = comp_pair{1};
                stageB_name = comp_pair{2};
                comp_name = comp_pair{3};
                
                condA = [NightName, '_', stageA_name];
                condB = [NightName, '_', stageB_name];
                tagA = [stageA_name, '_avg'];
                tagB = [stageB_name, '_avg'];
                
                addLog(sprintf('Comparing: %s', comp_name));

                % Select File A struct
                sFileA_struct = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                    'subjectname',   SubjName, ...
                    'condition',     condA, ...
                    'tag',           tagA);

                % Select File B struct
                sFileB_struct = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                    'subjectname',   SubjName, ...
                    'condition',     condB, ...
                    'tag',           tagB);
                    
                if isempty(sFileA_struct) || isempty(sFileB_struct)
                    addLog(sprintf('WARNING: Could not find one or both avg files for comparison %s. Skipping.', comp_name));
                    comparison_results{iComp} = []; % Add empty placeholder
                    continue;
                end
                
                % Replicate the example script: extract filenames into cell arrays
                sFileA_cell = {sFileA_struct(1).FileName};
                sFileB_cell = {sFileB_struct(1).FileName};

                % Run comparison and CAPTURE the output file handle
                sNewResult = bst_process('CallProcess', 'process_matlab_eval2', sFileA_cell, sFileB_cell, ...
                    'matlab', ['Data = 100 * (DataA.^2 - DataB.^2) ./ (DataB.^2);' 10 'Condition = ''' comp_name ''';']);
                
                comparison_results{iComp} = sNewResult; % Store the handle
                if ~isempty(sNewResult)
                    addLog(sprintf('   => Created comparison condition: %s', comp_name));
                else
                    addLog(sprintf('   ERROR: Failed to create comparison condition: %s', comp_name));
                end
            end
            end

            if do_sensor
                % --- Sensor Space Analysis ---
                addLog('--- Starting Sensor Space (2D Topography) Analysis ---');
            % Step 4: Average raw data for each stage
            addLog('Step 4: Averaging raw sensor data...');
            for iStage = 1:numel(stages)
                stage = stages{iStage};
                condition = [NightName, '_', stage];
                avg_tag = [stage, '_sensor_avg'];
                sFiles_select = bst_process('CallProcess', 'process_select_files_data', [], [], 'subjectname', SubjName, 'condition', condition);
                if isempty(sFiles_select), continue; end
                sFiles_avg = bst_process('CallProcess', 'process_average', sFiles_select, [], 'avgtype', 1, 'avg_func', 1, 'weighted', 0);
                bst_process('CallProcess', 'process_add_tag', sFiles_avg, [], 'tag', avg_tag, 'output', 'name');
            end

            % Step 5: Perform Sensor Space Comparisons
            addLog('Step 5: Performing sensor space relative difference comparisons...');
            for iComp = 1:numel(comparisons)
                comp_pair = comparisons{iComp};
                comp_name_sensor = [comp_pair{3}, '_sensor'];
                condA = [NightName, '_', comp_pair{1}];
                condB = [NightName, '_', comp_pair{2}];
                tagA = [comp_pair{1}, '_sensor_avg'];
                tagB = [comp_pair{2}, '_sensor_avg'];
                sFileA_struct = bst_process('CallProcess', 'process_select_files_data', [], [], 'subjectname', SubjName, 'condition', condA, 'tag', tagA);
                sFileB_struct = bst_process('CallProcess', 'process_select_files_data', [], [], 'subjectname', SubjName, 'condition', condB, 'tag', tagB);
                if isempty(sFileA_struct) || isempty(sFileB_struct), continue; end
                sFileA_cell = {sFileA_struct(1).FileName};
                sFileB_cell = {sFileB_struct(1).FileName};
                bst_process('CallProcess', 'process_matlab_eval2', sFileA_cell, sFileB_cell, 'matlab', ['Data = 100 * (DataA - DataB) ./ DataB;' 10 'Condition = ''' comp_name_sensor ''';']);
            end
            end
        end % End night loop
    end % End subject loop

    % --- GROUP ANALYSIS ---
    if do_group_analysis && do_source
        addLog('=== Starting Group Analysis ===');
        
        % Find all unique nights across all subjects
        allNights = {};
        for iSubj = 1:numel(SubjectNames)
            SubjName = SubjectNames{iSubj};
            subjDir = fullfile(dataDir, SubjName);
            condDirContents = dir(subjDir);
            condDirs = condDirContents([condDirContents.isdir] & ~startsWith({condDirContents.name}, {'.', '@'}));
            condNames = {condDirs.name};
            condNamesForNightDetection = condNames(~contains(condNames, '_vs_'));
            nightNames = {};
            for iCond = 1:numel(condNamesForNightDetection)
                parts = strsplit(condNamesForNightDetection{iCond}, '_');
                if numel(parts) > 1
                    nightNames{end+1} = parts{1};
                end
            end
            allNights = [allNights, nightNames];
        end
        uniqueAllNights = unique(allNights);
        addLog(sprintf('Processing group analysis for nights: %s', strjoin(uniqueAllNights, ', ')));
        
        % Process each night for group analysis
        for iNight = 1:numel(uniqueAllNights)
            NightName = uniqueAllNights{iNight};
            addLog(sprintf('Group analysis for Night: %s', NightName));
            
            stages = {'pre-stim', 'stim', 'post-stim'};
            comparisons = {
                {'stim', 'pre-stim', 'Stim_vs_Pre'}, ...
                {'post-stim', 'stim', 'Post_vs_Stim'}, ...
                {'post-stim', 'pre-stim', 'Post_vs_Pre'}  ...
            };
            
            % Process Active and Sham groups
            groups = {activeSubjects, shamSubjects};
            groupNames = {'Active', 'Sham'};
            
            for iGroup = 1:numel(groups)
                groupSubjects = groups{iGroup};
                groupName = groupNames{iGroup};
                
                if isempty(groupSubjects)
                    addLog(sprintf('WARNING: No subjects in %s group. Skipping.', groupName));
                    continue;
                end
                
                addLog(sprintf('Processing %s group (%d subjects): %s', groupName, numel(groupSubjects), strjoin(groupSubjects, ', ')));
                
                % Average within group for each stage
                for iStage = 1:numel(stages)
                    stage = stages{iStage};
                    projected_tag = [stage, '_avg_projected'];
                    group_avg_tag = [groupName, '_', stage, '_group_avg'];
                    
                    addLog(sprintf('Averaging %s group %s stage...', groupName, stage));
                    
                    % Collect all projected files for this stage from group subjects
                    % NOTE: Projected files are stored in "Group analysis" subject, not original subjects
                    groupFiles = {};
                    condition = [NightName, '_', stage];
                    
                    % Find all projected files for this condition in Group analysis subject
                    sFiles_projected = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                        'subjectname', 'Group_analysis', ...
                        'condition',   condition, ...
                        'tag',         projected_tag);
                    
                    if ~isempty(sFiles_projected)
                        % Filter projected files to include only those from group subjects
                        for iFile = 1:numel(sFiles_projected)
                            projFile = sFiles_projected(iFile);
                            % Check if this projected file corresponds to one of our group subjects
                            % The file comment should contain the original subject name
                            for iSubj = 1:numel(groupSubjects)
                                subjName = groupSubjects{iSubj};
                                if contains(projFile.Comment, subjName)
                                    groupFiles{end+1} = projFile;
                                    addLog(sprintf('Found projected file for %s: %s', subjName, projFile.Comment));
                                    break;
                                end
                            end
                        end
                    else
                        addLog(sprintf('WARNING: No projected files found in Group_analysis for condition: %s', condition));
                    end
                    
                    addLog(sprintf('Collected %d projected files for %s group %s stage', numel(groupFiles), groupName, stage));
                    
                    if ~isempty(groupFiles)
                        % Average across subjects using mean(abs(x))
                        sFiles_group_avg = bst_process('CallProcess', 'process_average', groupFiles, [], ...
                            'avgtype',    1, ...  % Everything
                            'avg_func',   2, ...  % mean(abs(x))
                            'weighted',   0);
                        
                        % Add group tag
                        bst_process('CallProcess', 'process_add_tag', sFiles_group_avg, [], ...
                            'tag',      group_avg_tag, ...
                            'output',   'name');
                        
                        addLog(sprintf('   => Created %s group average: %s', groupName, group_avg_tag));
                    end
                end
                
                % Perform group-level comparisons
                addLog(sprintf('Performing %s group comparisons...', groupName));
                for iComp = 1:numel(comparisons)
                    comp_pair = comparisons{iComp};
                    stageA_name = comp_pair{1};
                    stageB_name = comp_pair{2};
                    comp_name = [groupName, '_', comp_pair{3}];
                    
                    tagA = [groupName, '_', stageA_name, '_group_avg'];
                    tagB = [groupName, '_', stageB_name, '_group_avg'];
                    
                    addLog(sprintf('Group comparison: %s', comp_name));
                    
                    % Find group average files
                    sFileA_struct = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                        'tag', tagA);
                    sFileB_struct = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                        'tag', tagB);
                    
                    if isempty(sFileA_struct) || isempty(sFileB_struct)
                        addLog(sprintf('WARNING: Could not find group average files for %s. Skipping.', comp_name));
                        continue;
                    end
                    
                    % Run group comparison
                    sFileA_cell = {sFileA_struct(1).FileName};
                    sFileB_cell = {sFileB_struct(1).FileName};
                    
                    sNewResult = bst_process('CallProcess', 'process_matlab_eval2', sFileA_cell, sFileB_cell, ...
                        'matlab', ['Data = 100 * (DataA.^2 - DataB.^2) ./ (DataB.^2);' 10 'Condition = ''' comp_name ''';']);
                    
                    if ~isempty(sNewResult)
                        addLog(sprintf('   => Created group comparison: %s', comp_name));
                    end
                end
            end
            
            % Between-group comparisons
            if numel(activeSubjects) > 0 && numel(shamSubjects) > 0
                addLog('Performing between-group comparisons (Active vs Sham)...');
                for iStage = 1:numel(stages)
                    stage = stages{iStage};
                    comp_name = ['Active_vs_Sham_', stage];
                    
                    tagActive = ['Active_', stage, '_group_avg'];
                    tagSham = ['Sham_', stage, '_group_avg'];
                    
                    % Find group average files
                    sFileActive_struct = bst_process('CallProcess', 'process_select_files_results', [], [], 'tag', tagActive);
                    sFileSham_struct = bst_process('CallProcess', 'process_select_files_results', [], [], 'tag', tagSham);
                    
                    if ~isempty(sFileActive_struct) && ~isempty(sFileSham_struct)
                        sFileActive_cell = {sFileActive_struct(1).FileName};
                        sFileSham_cell = {sFileSham_struct(1).FileName};
                        
                        sNewResult = bst_process('CallProcess', 'process_matlab_eval2', sFileActive_cell, sFileSham_cell, ...
                            'matlab', ['Data = 100 * (DataA.^2 - DataB.^2) ./ (DataB.^2);' 10 'Condition = ''' comp_name ''';']);
                        
                        if ~isempty(sNewResult)
                            addLog(sprintf('   => Created between-group comparison: %s', comp_name));
                        end
                    end
                end
            end
        end
        
        addLog('=== Group Analysis Complete ===');
    end

    % --- Screenshot Loop ---
    addLog('--- Generating all screenshots using Mode 2 contact sheet approach ---');
    
    % Process individual subjects first
    for iSubj = 1:numel(SubjectNames)
        SubjName = SubjectNames{iSubj};
        addLog(sprintf('--- Generating screenshots for Subject: %s ---', SubjName));
        subjDir = fullfile(dataDir, SubjName);
        condDirContents = dir(subjDir);
        condDirs = condDirContents([condDirContents.isdir] & ~startsWith({condDirContents.name}, {'.', '@'}));
        condNames = {condDirs.name};
        condNamesForNightDetection = condNames(~contains(condNames, '_vs_'));
        nightNames = {};
        for iCond = 1:numel(condNamesForNightDetection)
            parts = strsplit(condNamesForNightDetection{iCond}, '_');
            if numel(parts) > 1, nightNames{end+1} = parts{1}; end
        end
        uniqueNightNames = unique(nightNames);

        for iNight = 1:numel(uniqueNightNames)
            NightName = uniqueNightNames{iNight};
            addLog(sprintf('... Night: %s', NightName));
            
            stages = {'pre-stim', 'stim', 'post-stim'};
            comparisons = {
                {'stim', 'pre-stim', 'Stim_vs_Pre'}, ...
                {'post-stim', 'stim', 'Post_vs_Stim'}, ...
                {'post-stim', 'pre-stim', 'Post_vs_Pre'}  ...
            };
            baseOutputDir = fullfile(strengthenDir, 'contact_sheet_stages_comparison', SubjName, NightName);
            
            if do_source
                addLog('... generating source contact sheets');
                
                % Generate contact sheets for stage averages (use default colormap behavior)
                for iStage = 1:numel(stages)
                    stage = stages{iStage};
                    condition = [NightName, '_', stage];
                    avg_tag = [stage, '_avg'];
                    
                    sResult = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                        'subjectname', SubjName, ...
                        'condition',   condition, ...
                        'tag',         avg_tag);
                    
                    if ~isempty(sResult)
                        % For stage averages, use default Brainstorm colormap (no custom bounds)
                        filename = [SubjName, '_', NightName, '_', stage, '_avg'];
                        generate_stage_average_contact_sheet(sResult, baseOutputDir, filename);
                        addLog(sprintf('   => Stage average contact sheet: %s', stage));
                    end
                end
                
                % Generate contact sheets for comparisons (use user-defined bounds)
                for iComp = 1:numel(comparisons)
                    comp_name = comparisons{iComp}{3};
                    
                    sResult = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                        'subjectname', SubjName, ...
                        'condition',   comp_name);
                    
                    if ~isempty(sResult)
                        filename = [SubjName, '_', NightName, '_', comp_name];
                        generate_custom_contact_sheet(sResult, baseOutputDir, filename, user_bound);
                        addLog(sprintf('   => Comparison contact sheet: %s', comp_name));
                    end
                end
            end

            if do_sensor
                addLog('... generating sensor contact sheets');
                
                % Generate contact sheets for sensor stage averages
                for iStage = 1:numel(stages)
                    stage = stages{iStage};
                    condition = [NightName, '_', stage];
                    avg_tag = [stage, '_sensor_avg'];
                    
                    sResult = bst_process('CallProcess', 'process_select_files_data', [], [], ...
                        'subjectname', SubjName, ...
                        'condition',   condition, ...
                        'tag',         avg_tag);
                    
                    if ~isempty(sResult)
                        filename = [SubjName, '_', NightName, '_', stage, '_sensor_avg'];
                        generate_sensor_stage_average_contact_sheet(sResult, baseOutputDir, filename);
                        addLog(sprintf('   => Sensor stage contact sheet: %s', stage));
                    end
                end
                
                % Generate contact sheets for sensor comparisons
                for iComp = 1:numel(comparisons)
                    comp_name_sensor = [comparisons{iComp}{3}, '_sensor'];
                    
                    sResult = bst_process('CallProcess', 'process_select_files_data', [], [], ...
                        'subjectname', SubjName, ...
                        'condition',   comp_name_sensor);
                    
                    if ~isempty(sResult)
                        filename = [SubjName, '_', NightName, '_', comp_name_sensor];
                        generate_custom_sensor_contact_sheet(sResult, baseOutputDir, filename, user_bound);
                        addLog(sprintf('   => Sensor comparison contact sheet: %s', comp_name_sensor));
                    end
                end
            end
        end
    end
    
    % Generate screenshots for group analysis results
    if do_group_analysis && do_source
        addLog('--- Generating group analysis screenshots ---');
        
        % Find all unique nights for group analysis
        allNights = {};
        for iSubj = 1:numel(SubjectNames)
            SubjName = SubjectNames{iSubj};
            subjDir = fullfile(dataDir, SubjName);
            condDirContents = dir(subjDir);
            condDirs = condDirContents([condDirContents.isdir] & ~startsWith({condDirContents.name}, {'.', '@'}));
            condNames = {condDirs.name};
            condNamesForNightDetection = condNames(~contains(condNames, '_vs_'));
            nightNames = {};
            for iCond = 1:numel(condNamesForNightDetection)
                parts = strsplit(condNamesForNightDetection{iCond}, '_');
                if numel(parts) > 1
                    nightNames{end+1} = parts{1};
                end
            end
            allNights = [allNights, nightNames];
        end
        uniqueAllNights = unique(allNights);
        
        for iNight = 1:numel(uniqueAllNights)
            NightName = uniqueAllNights{iNight};
            addLog(sprintf('Group screenshots for Night: %s', NightName));
            
            stages = {'pre-stim', 'stim', 'post-stim'};
            comparisons = {
                {'stim', 'pre-stim', 'Stim_vs_Pre'}, ...
                {'post-stim', 'stim', 'Post_vs_Stim'}, ...
                {'post-stim', 'pre-stim', 'Post_vs_Pre'}  ...
            };
            
            % Process each group
            groupNames = {'Active', 'Sham'};
            for iGroup = 1:numel(groupNames)
                groupName = groupNames{iGroup};
                baseOutputDir = fullfile(strengthenDir, 'contact_sheet_stages_comparison', 'GroupAnalysis', groupName, NightName);
                
                % Group stage averages
                for iStage = 1:numel(stages)
                    stage = stages{iStage};
                    group_avg_tag = [groupName, '_', stage, '_group_avg'];
                    
                    sResult = bst_process('CallProcess', 'process_select_files_results', [], [], 'tag', group_avg_tag);
                    
                    if ~isempty(sResult)
                        filename = [groupName, '_', NightName, '_', stage, '_group_avg'];
                        generate_stage_average_contact_sheet(sResult, baseOutputDir, filename);
                        addLog(sprintf('   => %s group stage contact sheet: %s', groupName, stage));
                    end
                end
                
                % Group comparisons
                for iComp = 1:numel(comparisons)
                    comp_name = [groupName, '_', comparisons{iComp}{3}];
                    
                    sResult = bst_process('CallProcess', 'process_select_files_results', [], [], 'condition', comp_name);
                    
                    if ~isempty(sResult)
                        filename = [groupName, '_', NightName, '_', comparisons{iComp}{3}];
                        generate_custom_contact_sheet(sResult, baseOutputDir, filename, user_bound);
                        addLog(sprintf('   => %s group comparison contact sheet: %s', groupName, comparisons{iComp}{3}));
                    end
                end
            end
            
            % Between-group comparisons
            if numel(activeSubjects) > 0 && numel(shamSubjects) > 0
                baseOutputDir = fullfile(strengthenDir, 'contact_sheet_stages_comparison', 'GroupAnalysis', 'ActiveVsSham', NightName);
                
                for iStage = 1:numel(stages)
                    stage = stages{iStage};
                    comp_name = ['Active_vs_Sham_', stage];
                    
                    sResult = bst_process('CallProcess', 'process_select_files_results', [], [], 'condition', comp_name);
                    
                    if ~isempty(sResult)
                        filename = ['ActiveVsSham_', NightName, '_', stage];
                        generate_custom_contact_sheet(sResult, baseOutputDir, filename, user_bound);
                        addLog(sprintf('   => Active vs Sham contact sheet: %s', stage));
                    end
                end
            end
        end
    end

    addLog('=== Comparison Pipeline End ===');
    disp(['Cumulative log saved to: ', logName]);
else
    % =================================================
    % === MODE 2: SCREENSHOT SINGLE RESULT
    % =================================================
    addLog('Executing Screenshot Only Mode...');

    % --- Protocol Selection (reused) ---
    protocolNames = {};
    DbDir = bst_get('BrainstormDbDir');
    if isempty(DbDir) || ~exist(DbDir, 'dir'), addLog('ERROR: Brainstorm DB not found.'); return; end
    dirContents = dir(DbDir);
    subDirs = dirContents([dirContents.isdir] & ~ismember({dirContents.name},{'.','..'}));
    for iDir = 1:length(subDirs)
        protocolMatPath = fullfile(DbDir, subDirs(iDir).name, 'data', 'protocol.mat');
        if exist(protocolMatPath, 'file')
            matData = load(protocolMatPath, 'ProtocolInfo');
            if isfield(matData, 'ProtocolInfo') && isfield(matData.ProtocolInfo, 'Comment'), protocolNames{end+1} = matData.ProtocolInfo.Comment; end
        end
    end
    if isempty(protocolNames), addLog('ERROR: No protocols found.'); return; end
    disp('=== Select the Protocol ===');
    protocolNames = sort(protocolNames);
    for i = 1:numel(protocolNames), disp([num2str(i) ': ' protocolNames{i}]); end
    choiceNum = -1;
    while choiceNum < 1 || choiceNum > numel(protocolNames)
        try
            choiceStr = input(['Select protocol number (1-' num2str(numel(protocolNames)) '): '], 's');
            choiceNum = str2double(choiceStr);
            if isnan(choiceNum) || floor(choiceNum) ~= choiceNum, choiceNum = -1; disp('Invalid input.'); end
        catch
            choiceNum = -1; disp('Invalid input.');
        end
    end
    selectedProtocolName = protocolNames{choiceNum};
    iProtocol = bst_get('Protocol', selectedProtocolName);
    gui_brainstorm('SetCurrentProtocol', iProtocol);
    addLog(['Selected protocol: ', selectedProtocolName]);

    % --- Subject Selection (reused) ---
    dataDir = fullfile(DbDir, selectedProtocolName, 'data');
    dirContents = dir(dataDir);
    subjDirs = dirContents([dirContents.isdir] & ~startsWith({dirContents.name}, {'.', '@'}));
    SubjectNames = {subjDirs.name};
    if isempty(SubjectNames), addLog('ERROR: No subjects found.'); return; end
    disp(' '); disp('=== Select a Subject ===');
    for i = 1:numel(SubjectNames), disp([num2str(i) ': ' SubjectNames{i}]); end
    choiceNum = -1;
    while choiceNum < 1 || choiceNum > numel(SubjectNames)
        try
            choiceStr = input(['Select subject number (1-' num2str(numel(SubjectNames)) '): '], 's');
            choiceNum = str2double(choiceStr);
            if isnan(choiceNum) || floor(choiceNum) ~= choiceNum, choiceNum = -1; disp('Invalid input.'); end
        catch
            choiceNum = -1; disp('Invalid input.');
        end
    end
    SubjName = SubjectNames{choiceNum};
    addLog(['Selected subject: ', SubjName]);

    % --- Condition/Result Selection ---
    subjDir = fullfile(dataDir, SubjName);
    condDirContents = dir(subjDir);
    condDirs = condDirContents([condDirContents.isdir] & ~startsWith({condDirContents.name}, {'.', '@'}));
    condNames = {condDirs.name};
    if isempty(condNames), addLog('ERROR: No conditions found for this subject.'); return; end
    
    disp(' '); disp('=== Available Conditions/Results ===');
    for i = 1:numel(condNames), disp([num2str(i) ': ' condNames{i}]); end
    
    selectedIndices = [];
    while isempty(selectedIndices)
        try
            choiceStr = input('Enter condition numbers to process (e.g., 1,3,5): ', 's');
            if isempty(choiceStr)
                error('Selection cannot be empty.');
            end
            selectedIndices = str2num(choiceStr); %#ok<ST2NM>
            if any(selectedIndices < 1) || any(selectedIndices > numel(condNames)) || any(floor(selectedIndices) ~= selectedIndices)
                disp('Invalid selection. Please enter valid numbers from the list.');
                selectedIndices = [];
            end
        catch ME
            disp(['Invalid input format: ' ME.message]);
            selectedIndices = [];
        end
    end
    
    selectedConditions = condNames(selectedIndices);
    addLog(sprintf('Selected conditions: %s', strjoin(selectedConditions, ', ')));

    % --- Loop through selected conditions and process all source files ---
    allSourceFiles = {};
    allConditionNames = {};
    
    % Collect all source files from selected conditions
    for iCond = 1:numel(selectedConditions)
        selectedCondition = selectedConditions{iCond};
        addLog(sprintf('Finding source files in condition %d/%d: %s', iCond, numel(selectedConditions), selectedCondition));

        % Find all result files in this condition
        sResults = bst_process('CallProcess', 'process_select_files_results', [], [], 'subjectname', SubjName, 'condition', selectedCondition);
        if isempty(sResults)
            addLog(['WARNING: Could not find any result files for condition: ' selectedCondition '. Skipping.']);
            continue;
        end
        
        % Add all files to the collection
        for iFile = 1:length(sResults)
            allSourceFiles{end+1} = sResults(iFile);
            allConditionNames{end+1} = selectedCondition;
        end
    end
    
    if isempty(allSourceFiles)
        addLog('ERROR: No source files found in selected conditions.');
        return;
    end
    
    addLog(sprintf('Found %d source files total to process', length(allSourceFiles)));
    
    % Loop through each source file and generate contact sheets
    for iFile = 1:length(allSourceFiles)
        sFile = allSourceFiles{iFile};
        conditionName = allConditionNames{iFile};
        
        % Display file information
        disp(' ');
        disp('===========================================');
        disp(sprintf('Processing file %d/%d:', iFile, length(allSourceFiles)));
        disp(sprintf('Condition: %s', conditionName));
        disp(sprintf('File: %s', sFile.FileName));
        disp('===========================================');
        
        % Ask user for custom output name
        customName = '';
        while isempty(customName)
            customName = input('Enter custom name for this file (will create XXX_top, XXX_bottom, etc.): ', 's');
            if isempty(customName)
                disp('Name cannot be empty. Please enter a valid name.');
            else
                % Clean the name (remove invalid characters)
                customName = regexprep(customName, '[^\w\-_]', '_');
                if isempty(customName)
                    disp('Invalid name after cleaning. Please use alphanumeric characters, hyphens, or underscores.');
                    customName = '';
                end
            end
        end
        
        addLog(sprintf('Processing file %d/%d with custom name: %s', iFile, length(allSourceFiles), customName));
        
        % Prompt user for percentage bounds
        user_bound = [];
        while isempty(user_bound) || user_bound <= 0
            try
                boundStr = input('Enter percentage bound (e.g., 50 for -50% to +50%) [50]: ', 's');
                if isempty(boundStr)
                    user_bound = 50; % Default
                    disp('Using default bound: 50%');
                    break;
                end
                user_bound = str2double(boundStr);
                if isnan(user_bound) || user_bound <= 0
                    disp('Please enter a positive number.');
                    user_bound = [];
                end
            catch
                disp('Invalid input. Please enter a positive number.');
                user_bound = [];
            end
        end
        
        % Create output directory
        outputDir = fullfile(strengthenDir, 'custom_contact_sheets', SubjName);
        if ~exist(outputDir, 'dir'), mkdir(outputDir); end
        
        % Generate custom contact sheets with user-specified name
        generate_custom_contact_sheet_with_name(sFile, outputDir, customName, user_bound);
        addLog(['Contact sheets saved in: ' outputDir]);
        
        % Ask user if they want to continue or stop
        if iFile < length(allSourceFiles)
            disp(' ');
            continueChoice = input('Continue to next file? (y/n) [y]: ', 's');
            if isempty(continueChoice)
                continueChoice = 'y';
            end
            if ~strcmpi(continueChoice, 'y') && ~strcmpi(continueChoice, 'yes')
                addLog('User chose to stop processing.');
                break;
            end
        end
    end
end

end

% --- HELPER FUNCTION FOR SCREENSHOTS ---
function process_screenshot_group(sFiles_group, type, colormap_type, baseOutputDir, SubjName, NightName, orientations, data_field_accessor, use_abs, display_units, dataThreshold, fixed_sym_max)
    if isempty(sFiles_group)
        return;
    end

    % If a fixed maximum is provided, use it. Otherwise, calculate from the group.
    if strcmpi(type, 'sensor') && nargin >= 12 && ~isempty(fixed_sym_max) && isfinite(fixed_sym_max)
        symMax = fixed_sym_max;
        gMax = fixed_sym_max;
    elseif nargin >= 12 && ~isempty(fixed_sym_max) && isfinite(fixed_sym_max)
        symMax = fixed_sym_max;
        gMax = fixed_sym_max;
    else
        % Find min/max for the local group
        gMin = inf;
        gMax = -inf;
        for i = 1:numel(sFiles_group)
            sFile = sFiles_group{i};
            if strcmpi(type, 'source')
                bst_file = in_bst_results(sFile(1).FileName, 0);
            else % sensor
                bst_file = in_bst_data(sFile(1).FileName);
            end
            data = data_field_accessor(bst_file);
            if use_abs
                data = abs(data);
            end
            gMin = min(gMin, min(data(:)));
            gMax = max(gMax, max(data(:)));
        end

        if isinf(gMin) || isinf(gMax)
            disp(['SKIPPING screenshot group for ' colormap_type ': No data found.']);
            return;
        end
        
        % Determine symmetric max for non-absolute scales
        symMax = max(abs([gMin, gMax]));
    end

    % Loop through files to take screenshots
    for i = 1:numel(sFiles_group)
        sFile = sFiles_group{i};
        res_cond_name = sFile(1).Condition;

        if strcmpi(type, 'source')
            % 3D Source screenshots
            for iOrient = 1:numel(orientations)
                orientation = orientations{iOrient};
                outputDir = fullfile(baseOutputDir, 'source', orientation);
                if ~exist(outputDir, 'dir'), mkdir(outputDir); end
                
                try
                    outputFileName = fullfile(outputDir, [res_cond_name, '.png']);
                    
                    % Start a new report
                    bst_report('Start', sFile);

                    % Call the snapshot process
                    sFiles_snap = bst_process('CallProcess', 'process_snapshot', sFile, [], ...
                        'type',           'sources_contact', ...
                        'orient',         orientation, ...
                        'contact_time',   [-0.05, 0.05], ...
                        'contact_nimage', 11, ...
                        'threshold',      dataThreshold * 100, ...
                        'surfsmooth',     30, ...
                        'Comment',        [res_cond_name '_' orientation]);

                    % Save the report to a temporary file
                    tempReportFile = bst_report('Save', sFiles_snap);
                    
                    % Export the image from the report
                    if ~isempty(tempReportFile)
                        ReportMat = load(tempReportFile);
                        iImages = find(strcmpi(ReportMat.Reports(:,1), 'image'));
                        if ~isempty(iImages)
                            imgRgb = ReportMat.Reports{iImages(1), 4};
                            out_image(outputFileName, imgRgb);
                        end
                        delete(tempReportFile);
                    end
                catch ME
                    disp(['ERROR generating source screenshot: ' ME.message]);
                end
            end
        else % 2D Sensor screenshots
            outputDir = fullfile(baseOutputDir, 'sensor');
            if ~exist(outputDir, 'dir'), mkdir(outputDir); end

            try
                outputFileName = fullfile(outputDir, [res_cond_name, '_2D_topo.png']);
                
                % Start a new report
                bst_report('Start', sFile);

                % Call the snapshot process
                sFiles_snap = bst_process('CallProcess', 'process_snapshot', sFile, [], ...
                    'type',           'topo_contact', ...
                    'contact_time',   [-0.05, 0.05], ...
                    'contact_nimage', 11, ...
                    'Comment',        [res_cond_name '_2D_topo']);

                % Save the report to a temporary file
                tempReportFile = bst_report('Save', sFiles_snap);
                
                % Export the image from the report
                if ~isempty(tempReportFile)
                    ReportMat = load(tempReportFile);
                    iImages = find(strcmpi(ReportMat.Reports(:,1), 'image'));
                    if ~isempty(iImages)
                        imgRgb = ReportMat.Reports{iImages(1), 4};
                        out_image(outputFileName, imgRgb);
                    end
                    delete(tempReportFile);
                end
            catch ME
                disp(['ERROR generating sensor screenshot: ' ME.message]);
            end
        end
    end
    % Restore default colormap behavior
    bst_colormaps('SetMaxMode', colormap_type, 'global');
end


% --- HELPER FUNCTION FOR SINGLE SCREENSHOTS ---
function screenshot_single_result(sFile, baseOutputDir)
    res_cond_name = sFile(1).Condition;
    
    % Prompt user for percentage bounds
    user_bound = [];
    while isempty(user_bound) || user_bound <= 0
        try
            boundStr = input('Enter percentage bound (e.g., 50 for -50% to +50%): ', 's');
            if isempty(boundStr)
                user_bound = 50; % Default
                disp('Using default bound: 50%');
                break;
            end
            user_bound = str2double(boundStr);
            if isnan(user_bound) || user_bound <= 0
                disp('Please enter a positive number.');
                user_bound = [];
            end
        catch
            disp('Invalid input. Please enter a positive number.');
            user_bound = [];
        end
    end
    
    % Generate custom contact sheet
    generate_custom_contact_sheet(sFile, baseOutputDir, res_cond_name, user_bound);
end

% --- STAGE AVERAGE CONTACT SHEET GENERATOR (DEFAULT COLORMAP) ---
function generate_stage_average_contact_sheet(sFile, baseOutputDir, base_filename)
    orientations = {'top', 'bottom', 'left_intern', 'right_intern'};
    
    % EXPLICITLY restore default source colormap for stage averages
    bst_colormaps('RestoreDefaults', 'source');
    
    try
        % Generate contact sheet for each orientation using default Brainstorm colormap
        for iOrient = 1:numel(orientations)
            orientation = orientations{iOrient};
            
            try
                % Create output directory
                outputDir = fullfile(baseOutputDir, 'contact_sheets', orientation);
                if ~exist(outputDir, 'dir')
                    mkdir(outputDir);
                end
                
                outputFileName = fullfile(outputDir, [base_filename, '_', orientation, '_contact_sheet.png']);
                
                % Create the contact sheet using Brainstorm's native function
                % Using default source colormap behavior (royal_gramma, absolute values, global scaling)
                create_native_contact_sheet(sFile, orientation, outputFileName);
                
                disp(['Saved stage average contact sheet for ' orientation ' to: ' outputFileName]);
                
            catch ME
                disp(['ERROR generating stage average contact sheet for orientation ' orientation ': ' ME.message]);
            end
        end
        
    catch ME_main
        disp(['ERROR during stage average contact sheet generation: ' ME_main.message]);
    end
end

% --- CUSTOM CONTACT SHEET GENERATOR (USING VIEW_CONTACTSHEET) ---
function generate_custom_contact_sheet(sFile, baseOutputDir, base_filename, user_bound)
    orientations = {'top', 'bottom', 'left_intern', 'right_intern'};
    
    % Get the original source colormap to restore it later
    sOldColormap = bst_colormaps('GetColormap', 'source');
    
    % Set up custom diverging colormap (cmap_rbw) with user-defined bounds
    sTempColormap = sOldColormap;
    sTempColormap.Name = 'cmap_rbw';
    sTempColormap.CMap = cmap_rbw(256);  % Diverging colormap
    sTempColormap.isAbsoluteValues = 0;  % Not absolute values for diverging
    sTempColormap.MaxMode = 'custom';
    sTempColormap.MinValue = -user_bound;
    sTempColormap.MaxValue = user_bound;
    sTempColormap.DisplayColorbar = 1;   % Ensure colorbar is visible
    
    % Apply the custom colormap
    bst_colormaps('SetColormap', 'source', sTempColormap);
    
    try
        % Generate contact sheet for each orientation
        for iOrient = 1:numel(orientations)
            orientation = orientations{iOrient};
            
            try
                % Create output directory
                outputDir = fullfile(baseOutputDir, 'contact_sheets', orientation);
                if ~exist(outputDir, 'dir')
                    mkdir(outputDir);
                end
                
                outputFileName = fullfile(outputDir, [base_filename, '_', orientation, '_contact_sheet.png']);
                
                % Create the contact sheet using Brainstorm's native function
                create_native_contact_sheet(sFile, orientation, outputFileName);
                
                disp(['Saved contact sheet for ' orientation ' to: ' outputFileName]);
                
            catch ME
                disp(['ERROR generating contact sheet for orientation ' orientation ': ' ME.message]);
            end
        end
        
    catch ME_main
        disp(['ERROR during contact sheet generation: ' ME_main.message]);
    end
    
    % ALWAYS restore the original colormap settings
    bst_colormaps('SetColormap', 'source', sOldColormap);
    disp('Restored original colormap settings.');
end

% --- CUSTOM CONTACT SHEET GENERATOR WITH USER-SPECIFIED NAME ---
function generate_custom_contact_sheet_with_name(sFile, baseOutputDir, custom_name, user_bound)
    orientations = {'top', 'bottom', 'left_intern', 'right_intern'};
    
    % Get the original source colormap to restore it later
    sOldColormap = bst_colormaps('GetColormap', 'source');
    
    % Set up custom diverging colormap (cmap_rbw) with user-defined bounds
    sTempColormap = sOldColormap;
    sTempColormap.Name = 'cmap_rbw';
    sTempColormap.CMap = cmap_rbw(256);  % Diverging colormap
    sTempColormap.isAbsoluteValues = 0;  % Not absolute values for diverging
    sTempColormap.MaxMode = 'custom';
    sTempColormap.MinValue = -user_bound;
    sTempColormap.MaxValue = user_bound;
    sTempColormap.DisplayColorbar = 1;   % Ensure colorbar is visible
    
    % Apply the custom colormap
    bst_colormaps('SetColormap', 'source', sTempColormap);
    
    try
        % Generate contact sheet for each orientation with custom naming
        for iOrient = 1:numel(orientations)
            orientation = orientations{iOrient};
            
            try
                % Create output filename with custom name and orientation
                outputFileName = fullfile(baseOutputDir, [custom_name, '_', orientation, '.png']);
                
                % Create the contact sheet using Brainstorm's native function
                create_native_contact_sheet(sFile, orientation, outputFileName);
                
                disp(['Saved contact sheet for ' orientation ' to: ' outputFileName]);
                
            catch ME
                disp(['ERROR generating contact sheet for orientation ' orientation ': ' ME.message]);
            end
        end
        
    catch ME_main
        disp(['ERROR during contact sheet generation: ' ME_main.message]);
    end
    
    % ALWAYS restore the original colormap settings
    bst_colormaps('SetColormap', 'source', sOldColormap);
    disp('Restored original colormap settings.');
end

% --- SENSOR STAGE AVERAGE CONTACT SHEET GENERATOR (DEFAULT COLORMAP) ---
function generate_sensor_stage_average_contact_sheet(sFile, baseOutputDir, base_filename)
    try
        % Create output directory for sensor
        outputDir = fullfile(baseOutputDir, 'sensor');
        if ~exist(outputDir, 'dir')
            mkdir(outputDir);
        end
        
        outputFileName = fullfile(outputDir, [base_filename, '_2D_topo_contact_sheet.png']);
        
        % Create the sensor contact sheet using Brainstorm's native function
        % NO colormap modification - let Brainstorm use default EEG behavior
        create_native_sensor_contact_sheet(sFile, outputFileName);
        
        disp(['Saved sensor stage average contact sheet to: ' outputFileName]);
        
    catch ME
        disp(['ERROR during sensor stage average contact sheet generation: ' ME.message]);
    end
end

% --- CUSTOM SENSOR CONTACT SHEET GENERATOR ---
function generate_custom_sensor_contact_sheet(sFile, baseOutputDir, base_filename, user_bound)
    % Get the original EEG colormap to restore it later
    sOldColormap = bst_colormaps('GetColormap', 'eeg');
    
    % Set up custom diverging colormap (cmap_rbw) with user-defined bounds
    sTempColormap = sOldColormap;
    sTempColormap.Name = 'cmap_rbw';
    sTempColormap.CMap = cmap_rbw(256);  % Diverging colormap
    sTempColormap.isAbsoluteValues = 0;  % Not absolute values for diverging
    sTempColormap.MaxMode = 'custom';
    sTempColormap.MinValue = -user_bound;
    sTempColormap.MaxValue = user_bound;
    sTempColormap.DisplayColorbar = 1;   % Ensure colorbar is visible
    
    % Apply the custom colormap
    bst_colormaps('SetColormap', 'eeg', sTempColormap);
    
    try
        % Create output directory for sensor
        outputDir = fullfile(baseOutputDir, 'sensor');
        if ~exist(outputDir, 'dir')
            mkdir(outputDir);
        end
        
        outputFileName = fullfile(outputDir, [base_filename, '_2D_topo_contact_sheet.png']);
        
        % Create the sensor contact sheet using Brainstorm's native function
        create_native_sensor_contact_sheet(sFile, outputFileName);
        
        disp(['Saved sensor contact sheet to: ' outputFileName]);
        
    catch ME
        disp(['ERROR during sensor contact sheet generation: ' ME.message]);
    end
    
    % ALWAYS restore the original colormap settings
    bst_colormaps('SetColormap', 'eeg', sOldColormap);
    disp('Restored original EEG colormap settings.');
end

% --- CREATE SENSOR CONTACT SHEET USING BRAINSTORM'S NATIVE VIEW_CONTACTSHEET ---
function create_native_sensor_contact_sheet(sFile, outputFileName)
    % Contact sheet parameters (same as used in process_snapshot)
    contact_time = [-0.05, 0.05];  % From -50ms to +50ms 
    contact_nimage = 11;           % 11 images
    
    hFig = [];
    hContactFig = [];
    
    try
        % Create 2D topography visualization figure
        hFig = view_topography(sFile(1).FileName, 'EEG', [], 'NewFigure');
        if isempty(hFig)
            error('Could not create 2D topography figure');
        end
        
        % Set figure size for better quality
        set(hFig, 'Position', [200, 200, 200, 220]);
        
        % Wait for rendering
        drawnow;
        pause(0.5);
        
        % Create contact sheet using Brainstorm's native function
        hContactFig = view_contactsheet(hFig, 'time', 'fig', [], contact_nimage, contact_time);
        
        % Save the contact sheet image
        if ~isempty(hContactFig)
            % Get the image from the contact sheet figure
            contact_img = out_figure_image(hContactFig);
            if ~isempty(contact_img)
                out_image(outputFileName, contact_img);
            else
                error('Failed to capture sensor contact sheet image');
            end
        else
            error('Failed to create sensor contact sheet figure');
        end
        
    catch ME
        rethrow(ME);
    end
    
    % Cleanup figures
    try
        if ~isempty(hContactFig) && ishandle(hContactFig)
            close(hContactFig);
        end
    catch
        % Ignore cleanup errors
    end
    
    try
        if ~isempty(hFig) && ishandle(hFig)
            close(hFig);
        end
    catch
        % Ignore cleanup errors
    end
end

% --- CREATE CONTACT SHEET USING BRAINSTORM'S NATIVE VIEW_CONTACTSHEET ---
function create_native_contact_sheet(sFile, orientation, outputFileName)
    % Contact sheet parameters (same as used in process_snapshot)
    contact_time = [-0.05, 0.05];  % From -50ms to +50ms 
    contact_nimage = 11;           % 11 images
    
    hFig = [];
    hContactFig = [];
    
    try
        % Create source visualization figure
        hFig = view_surface_data([], sFile(1).FileName, [], 'NewFigure');
        if isempty(hFig)
            error('Could not create source visualization figure');
        end
        
        % Set surface properties (same as process_snapshot)
        iSurf = 1;
        panel_surface('SetDataThreshold', hFig, iSurf, 0);     % No threshold
        panel_surface('SetSurfaceSmooth', hFig, iSurf, 0.3, 0); % 30% smoothing
        
        % Set orientation
        figure_3d('SetStandardView', hFig, orientation);
        
        % Hide colorbar temporarily (view_contactsheet will show it on final image)
        bst_colormaps('SetColorbarVisible', hFig, 0);
        
        % Set figure size for better quality
        set(hFig, 'Position', [200, 200, 200, 220]);
        
        % Wait for rendering
        drawnow;
        pause(0.5);
        
        % Create contact sheet using Brainstorm's native function
        % This mimics exactly what bst_report does for 'sources_contact'
        hContactFig = view_contactsheet(hFig, 'time', 'fig', [], contact_nimage, contact_time);
        
        % Save the contact sheet image
        if ~isempty(hContactFig)
            % Get the image from the contact sheet figure
            contact_img = out_figure_image(hContactFig);
            if ~isempty(contact_img)
                out_image(outputFileName, contact_img);
            else
                error('Failed to capture contact sheet image');
            end
        else
            error('Failed to create contact sheet figure');
        end
        
    catch ME
        rethrow(ME);
    end
    
    % Cleanup figures
    try
        if ~isempty(hContactFig) && ishandle(hContactFig)
            close(hContactFig);
        end
    catch
        % Ignore cleanup errors
    end
    
    try
        if ~isempty(hFig) && ishandle(hFig)
            close(hFig);
        end
    catch
        % Ignore cleanup errors
    end
end

% --- CREATE CONTACT SHEET FROM INDIVIDUAL IMAGES ---
function contact_sheet = create_contact_sheet(images, labels)
    if isempty(images)
        contact_sheet = [];
        return;
    end
    
    % Determine grid layout (2x2 for 4 orientations)
    n_images = length(images);
    if n_images <= 2
        rows = 1;
        cols = n_images;
    elseif n_images <= 4
        rows = 2;
        cols = 2;
    else
        rows = 2;
        cols = ceil(n_images / 2);
    end
    
    % Get dimensions of first image
    sample_img = images{1};
    img_height = size(sample_img, 1);
    img_width = size(sample_img, 2);
    
    % Add padding between images
    padding = 10;
    label_height = 30; % Space for orientation labels
    
    % Calculate contact sheet dimensions
    total_width = cols * img_width + (cols - 1) * padding;
    total_height = rows * (img_height + label_height) + (rows - 1) * padding;
    
    % Create white background
    contact_sheet = ones(total_height, total_width, 3);
    
    % Place images in grid
    for i = 1:n_images
        % Calculate grid position
        row = ceil(i / cols);
        col = mod(i - 1, cols) + 1;
        
        % Calculate pixel positions
        start_y = (row - 1) * (img_height + label_height + padding) + 1;
        end_y = start_y + img_height - 1;
        start_x = (col - 1) * (img_width + padding) + 1;
        end_x = start_x + img_width - 1;
        
        % Ensure the image fits within bounds
        if end_y <= total_height && end_x <= total_width
            % Resize image if necessary to match expected dimensions
            current_img = images{i};
            if size(current_img, 1) ~= img_height || size(current_img, 2) ~= img_width
                current_img = imresize(current_img, [img_height, img_width]);
            end
            
            % Place image
            contact_sheet(start_y:end_y, start_x:end_x, :) = current_img;
            
            % Add label below image (simple text overlay would require additional functions)
            % For now, we'll skip text labels but maintain space for them
        end
    end
    
    % Convert to uint8 if needed
    if max(contact_sheet(:)) <= 1
        contact_sheet = uint8(contact_sheet * 255);
    end
end

function ensure_closed(h)
    if ~isempty(h) && ishandle(h)
        close(h);
    end
end

% --- HELPER FUNCTION TO WRITE CUMULATIVE LOG ---
function writeCumulativeLog(logName, logMessages)
    try
        fid = fopen(logName, 'w');
        if fid > 0
            for i = 1:length(logMessages)
                fprintf(fid, '%s\n', logMessages{i});
            end
            fclose(fid);
        end
    catch ME
        disp(['Warning: Could not write to log file: ' ME.message]);
    end
end
