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

    % Ensure Brainstorm is running
    if ~brainstorm('status')
        addLog('Brainstorm not running. Starting in nogui mode...');
        brainstorm nogui;
        pause(5);
        addLog('Brainstorm started.');
    else
        addLog('Brainstorm already running.');
    end

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

    % --- Assign subjects to groups if multiple are selected ---
    activeSubjects = {};
    shamSubjects = {};
    if numel(SubjectNames) > 1
        disp(' ');
        disp('--- Assign Subjects to Treatment Groups ---');
        disp('The following subjects were selected for processing:');
        for i = 1:numel(SubjectNames)
            disp([num2str(i) ': ' SubjectNames{i}]);
        end
        
        activeIndices = [];
        while isempty(activeIndices)
            try
                choiceStr = input('Enter numbers for ACTIVE group subjects (e.g., 1,3): ', 's');
                if isempty(choiceStr)
                    error('Input cannot be empty.');
                end
                activeIndices = str2num(choiceStr); %#ok<ST2NM>
                if any(activeIndices < 1) || any(activeIndices > numel(SubjectNames)) || any(floor(activeIndices) ~= activeIndices)
                    disp('Invalid selection. Please enter valid numbers from the list.');
                    activeIndices = [];
                end
            catch ME
                disp(['Invalid input format: ' ME.message]);
                activeIndices = [];
            end
        end
        
        allIndices = 1:numel(SubjectNames);
        shamIndices = setdiff(allIndices, activeIndices);
        
        activeSubjects = SubjectNames(activeIndices);
        shamSubjects = SubjectNames(shamIndices);
        
        addLog(sprintf('Active Group: %s', strjoin(activeSubjects, ', ')));
        addLog(sprintf('Sham Group: %s', strjoin(shamSubjects, ', ')));
    end


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

    % --- Screenshot Loop ---
    addLog('--- Generating all screenshots with hardcoded colormaps for comparisons ---');
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
            baseOutputDir = fullfile(strengthenDir, 'contact_sheet_stages_comparison', SubjName, NightName);
            
            if do_source
                addLog('... generating source screenshots');
                orientations = {'top', 'bottom', 'left_intern', 'right_intern'};
                
                source_stage_results = {};
            for iStage = 1:numel(stages)
                sResult = bst_process('CallProcess', 'process_select_files_results', [], [], 'subjectname', SubjName, 'condition', [NightName, '_', stages{iStage}], 'tag', [stages{iStage}, '_avg']);
                if ~isempty(sResult), source_stage_results{end+1} = sResult; end
            end
            source_comparison_results = {};
            for iComp = 1:numel(comparisons)
                sResult = bst_process('CallProcess', 'process_select_files_results', [], [], 'subjectname', SubjName, 'condition', comparisons{iComp}{3});
                if ~isempty(sResult), source_comparison_results{end+1} = sResult; end
            end

            process_screenshot_group(source_stage_results, 'source', 'source', baseOutputDir, SubjName, NightName, orientations, @(s) s.ImageGridAmp, true, [], 0.3, []);
            process_screenshot_group(source_comparison_results, 'source', 'source', baseOutputDir, SubjName, NightName, orientations, @(s) s.ImageGridAmp, true, '%', 0, 300);
            end

            if do_sensor
                addLog('... generating sensor screenshots');
                sensor_stage_results = {};
            for iStage = 1:numel(stages)
                sResult = bst_process('CallProcess', 'process_select_files_data', [], [], 'subjectname', SubjName, 'condition', [NightName, '_', stages{iStage}], 'tag', [stages{iStage}, '_sensor_avg']);
                if ~isempty(sResult), sensor_stage_results{end+1} = sResult; end
            end
            sensor_comparison_files = {};
            for iComp = 1:numel(comparisons)
                sResult = bst_process('CallProcess', 'process_select_files_data', [], [], 'subjectname', SubjName, 'condition', [comparisons{iComp}{3}, '_sensor']);
                if ~isempty(sResult), sensor_comparison_files{end+1} = sResult; end
            end

            process_screenshot_group(sensor_stage_results, 'sensor', 'eeg', baseOutputDir, SubjName, NightName, [], @(s) s.F, false, [], []);
            process_screenshot_group(sensor_comparison_files, 'sensor', 'eeg', baseOutputDir, SubjName, NightName, [], @(s) s.F, false, '%', [], 300);
            end
        end
    end

    % --- Group-Level Analysis ---
    if numel(SubjectNames) > 1 && (~isempty(activeSubjects) || ~isempty(shamSubjects))
        addLog('--- Starting Group-Level Analysis ---');
        groups = {'Active', 'Sham'};
        groupSubjects = {activeSubjects, shamSubjects};
        
        % Define file types to average
        % {is_source, id_type ('tag' or 'cond'), id_string, new_comment}
        files_to_average = { ...
            {true,  'tag',  'pre-stim_avg',         'pre-stim_avg_GROUP'}, ...
            {true,  'tag',  'stim_avg',             'stim_avg_GROUP'}, ...
            {true,  'tag',  'post-stim_avg',        'post-stim_avg_GROUP'}, ...
            {true,  'cond', 'Stim_vs_Pre',          'Stim_vs_Pre_GROUP'}, ...
            {true,  'cond', 'Post_vs_Stim',         'Post_vs_Stim_GROUP'}, ...
            {true,  'cond', 'Post_vs_Pre',          'Post_vs_Pre_GROUP'}, ...
            {false, 'tag',  'pre-stim_sensor_avg',  'pre-stim_sensor_avg_GROUP'}, ...
            {false, 'tag',  'stim_sensor_avg',      'stim_sensor_avg_GROUP'}, ...
            {false, 'tag',  'post-stim_sensor_avg', 'post-stim_sensor_avg_GROUP'}, ...
            {false, 'cond', 'Stim_vs_Pre_sensor',   'Stim_vs_Pre_sensor_GROUP'}, ...
            {false, 'cond', 'Post_vs_Stim_sensor',  'Post_vs_Stim_sensor_GROUP'}, ...
            {false, 'cond', 'Post_vs_Pre_sensor',   'Post_vs_Pre_sensor_GROUP'} ...
        };

        for iGroup = 1:numel(groups)
            groupName = groups{iGroup};
            subjectsInGroup = groupSubjects{iGroup};
            groupSubjectName = ['Group_', groupName];
            
            if isempty(subjectsInGroup), continue; end
            addLog(sprintf('--- Averaging results for group: %s ---', groupName));

            for iType = 1:numel(files_to_average)
                is_source = files_to_average{iType}{1};
                id_type   = files_to_average{iType}{2};
                id_string = files_to_average{iType}{3};
                new_cond  = files_to_average{iType}{4};
                
                sFilesInGroup = [];
                for iSubj = 1:numel(subjectsInGroup)
                    subj = subjectsInGroup{iSubj};
                    if is_source
                        sFile = bst_process('CallProcess', 'process_select_files_results', [], [], 'subjectname', subj, id_type, id_string);
                    else % sensor
                        sFile = bst_process('CallProcess', 'process_select_files_data', [], [], 'subjectname', subj, id_type, id_string);
                    end
                    if ~isempty(sFile), sFilesInGroup = [sFilesInGroup, sFile]; end
                end
                
                if numel(sFilesInGroup) < numel(subjectsInGroup)
                    addLog(sprintf('WARNING: Found %d/%d files for "%s" in group %s. Averaging may be incomplete.', numel(sFilesInGroup), numel(subjectsInGroup), id_string, groupName));
                end
                if isempty(sFilesInGroup), continue; end
                
                sAvg = bst_process('CallProcess', 'process_average', {sFilesInGroup.FileName}, [], 'avgtype', 1, 'avg_func', 1, 'weighted', 0, 'matchrows', 1);
                bst_process('CallProcess', 'process_set_comment', sAvg, [], 'comment', new_cond);
                bst_process('CallProcess', 'process_movefile', sAvg, [], 'subjectname', groupSubjectName);
                addLog(sprintf('Averaged "%s" for group %s and saved to subject %s', id_string, groupName, groupSubjectName));
            end
        end
        
        % --- Screenshotting for Group Averages ---
        addLog('--- Generating screenshots for Group Averages ---');
        for iGroup = 1:numel(groups)
            groupName = groups{iGroup};
            groupSubjectName = ['Group_', groupName];
            if isempty(groupSubjects{iGroup}), continue; end
            
            baseOutputDir = fullfile(strengthenDir, 'contact_sheet_stages_comparison', groupSubjectName);
            
            % Screenshot source group results if they were processed
            if do_source
                addLog(sprintf('... generating source screenshots for group: %s', groupName));
                orientations = {'top', 'bottom', 'left_intern', 'right_intern'};
                
                sGroupStage = bst_process('CallProcess', 'process_select_files_results', [], [], 'subjectname', groupSubjectName, 'tag', '_avg_GROUP');
                sGroupComp = bst_process('CallProcess', 'process_select_files_results', [], [], 'subjectname', groupSubjectName, 'tag', '_vs_Pre_GROUP');
                
                process_screenshot_group(sGroupStage, 'source', 'source', baseOutputDir, groupSubjectName, '', orientations, @(s) s.ImageGridAmp, true, [], 0.3, []);
                process_screenshot_group(sGroupComp, 'source', 'source', baseOutputDir, groupSubjectName, '', orientations, @(s) s.ImageGridAmp, true, '%', 0, 300);
            end
            
            % Screenshot sensor group results if they were processed
            if do_sensor
                addLog(sprintf('... generating sensor screenshots for group: %s', groupName));
                
                sGroupStage = bst_process('CallProcess', 'process_select_files_data', [], [], 'subjectname', groupSubjectName, 'tag', '_sensor_avg_GROUP');
                sGroupComp = bst_process('CallProcess', 'process_select_files_data', [], [], 'subjectname', groupSubjectName, 'tag', '_sensor_GROUP');

                process_screenshot_group(sGroupStage, 'sensor', 'eeg', baseOutputDir, groupSubjectName, '', [], @(s) s.F, false, [], []);
                process_screenshot_group(sGroupComp, 'sensor', 'eeg', baseOutputDir, groupSubjectName, '', [], @(s) s.F, false, '%', [], 300);
            end
        end
    end

    addLog('=== Comparison Pipeline End ===');
    disp(['Cumulative log saved to: ', logName]);
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
                    hFig = script_view_sources(sFile(1).FileName, 'cortex');
                    
                    % Force colormap settings on the newly created figure
                    if use_abs
                        bst_colormaps('SetMaxCustom', colormap_type, display_units, 0, gMax);
                    else
                        bst_colormaps('SetMaxCustom', colormap_type, display_units, -symMax, symMax);
                    end
                    bst_colormaps('FireColormapChanged', colormap_type);
                    
                    % Set the data threshold (amplitude percentage)
                    panel_surface('SetDataThreshold', hFig, 1, dataThreshold);

                    figure_3d('SetStandardView', hFig, orientation);
                    hContactFig = view_contactsheet(hFig, 'time', 'fig', [], 11, [-0.05, 0.05]);
                    img = get(findobj(hContactFig, 'Type', 'image'), 'CData');
                    out_image(outputFileName, img);
                    close(hContactFig); close(hFig);
                catch ME
                    disp(['ERROR generating source screenshot: ' ME.message]);
                    if exist('hFig', 'var') && ishandle(hFig), close(hFig); end
                    if exist('hContactFig', 'var') && ishandle(hContactFig), close(hContactFig); end
                end
            end
        else % 2D Sensor screenshots
            outputDir = fullfile(baseOutputDir, 'sensor');
            if ~exist(outputDir, 'dir'), mkdir(outputDir); end

            try
                outputFileName = fullfile(outputDir, [res_cond_name, '_2D_topo.png']);
                hFig = view_topography(sFile(1).FileName, 'EEG', '2DSensorCap');

                % Force colormap settings on the newly created figure
                if use_abs
                    bst_colormaps('SetMaxCustom', colormap_type, display_units, 0, gMax);
                else
                    bst_colormaps('SetMaxCustom', colormap_type, display_units, -symMax, symMax);
                end
                bst_colormaps('FireColormapChanged', colormap_type);

                hContactFig = view_contactsheet(hFig, 'time', 'fig', [], 11, [-0.05, 0.05]);
                img = get(findobj(hContactFig, 'Type', 'image'), 'CData');
                out_image(outputFileName, img);
                close(hContactFig); close(hFig);
            catch ME
                disp(['ERROR generating sensor screenshot: ' ME.message]);
                if exist('hFig', 'var') && ishandle(hFig), close(hFig); end
                if exist('hContactFig', 'var') && ishandle(hContactFig), close(hContactFig); end
            end
        end
    end
    % Restore default colormap behavior
    bst_colormaps('SetMaxMode', colormap_type, 'global');
end
