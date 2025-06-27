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
                    'matlab', ['Data = (DataA.^2 - DataB.^2) ./ (DataB.^2);' 10 'Condition = ''' comp_name ''';']);
                
                comparison_results{iComp} = sNewResult; % Store the handle
                if ~isempty(sNewResult)
                    addLog(sprintf('   => Created comparison condition: %s', comp_name));
                else
                    addLog(sprintf('   ERROR: Failed to create comparison condition: %s', comp_name));
                end
            end
            
            % --- Step 3: Take Screenshots ---
            addLog('Step 3: Generating contact sheet screenshots...');
            orientations = {'top', 'bottom', 'left_intern', 'right_intern'};
            
            % Create a combined list of all result files to screenshot
            all_results_to_screenshot = {};
            
            % Add averaged files
            for iStage = 1:numel(stages)
                sResult = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                    'subjectname', SubjName, ...
                    'condition',   [NightName, '_', stages{iStage}], ...
                    'tag',         [stages{iStage}, '_avg']);
                if ~isempty(sResult)
                    all_results_to_screenshot{end+1} = sResult;
                end
            end
            
            % Add comparison files that were successfully created
            for iComp = 1:numel(comparison_results)
                if ~isempty(comparison_results{iComp})
                    all_results_to_screenshot{end+1} = comparison_results{iComp};
                end
            end

            % Loop through all results and screenshot from all angles
            for iRes = 1:numel(all_results_to_screenshot)
                sResult = all_results_to_screenshot{iRes};
                res_cond_name = sResult(1).Condition; % e.g., 'Night1_pre-stim' or 'Stim_vs_Pre'
                
                % Create specific output directory for this source result
                outputDir = fullfile(baseOutputDir, 'source', res_cond_name);
                if ~exist(outputDir, 'dir'), mkdir(outputDir); end

                for iOrient = 1:numel(orientations)
                    orientation = orientations{iOrient};
                    
                    try
                        % Construct a simpler filename, as the folder is now descriptive
                        outputFileName = fullfile(outputDir, [SubjName, '_', NightName, '_', orientation, '.png']);
                        addLog(sprintf('Screenshotting source %s (%s) to %s', res_cond_name, orientation, outputFileName));
                        
                        % Display sources
                        hFig = script_view_sources(sResult(1).FileName, 'cortex');
                        
                        % Set camera orientation
                        figure_3d('SetStandardView', hFig, orientation);
                        
                        % Create contact sheet
                        hContactFig = view_contactsheet(hFig, 'time', 'fig', [], 11, [-0.05, 0.05]);
                        
                        % Get image data and save
                        img = get(findobj(hContactFig, 'Type', 'image'), 'CData');
                        out_image(outputFileName, img);
                        
                        % Close figures
                        close(hContactFig);
                        close(hFig);
                        addLog('   => Screenshot saved.');
                        
                    catch ME_screenshot
                        addLog(sprintf('ERROR generating screenshot for %s (%s): %s', res_cond_name, orientation, ME_screenshot.message));
                        if exist('hFig', 'var') && ishandle(hFig), close(hFig); end
                        if exist('hContactFig', 'var') && ishandle(hContactFig), close(hContactFig); end
                    end
                end
            end

            % =================================================================================
            % === SENSOR SPACE (2D TOPOGRAPHY) ANALYSIS
            % =================================================================================
            addLog('--- Starting Sensor Space (2D Topography) Analysis ---');

            % --- Step 4: Average raw data for each stage ---
            addLog('Step 4: Averaging raw sensor data...');
            for iStage = 1:numel(stages)
                stage = stages{iStage};
                condition = [NightName, '_', stage];
                avg_tag = [stage, '_sensor_avg'];
                
                addLog(sprintf('Averaging sensor data for stage: %s', stage));
                
                % Select all DATA files in the condition
                sFiles_select = bst_process('CallProcess', 'process_select_files_data', [], [], ...
                    'subjectname', SubjName, ...
                    'condition',   condition);
                
                if isempty(sFiles_select)
                    addLog(sprintf('WARNING: No data files found for %s. Skipping sensor averaging.', condition));
                    continue;
                end

                % Average (arithmetic mean)
                sFiles_avg = bst_process('CallProcess', 'process_average', sFiles_select, [], ...
                    'avgtype',    1, ...  % Everything
                    'avg_func',   1, ...  % Arithmetic average: mean(x)
                    'weighted',   0);
                
                % Add tag
                bst_process('CallProcess', 'process_add_tag', sFiles_avg, [], ...
                    'tag',      avg_tag, ...
                    'output',   'name');
                    
                addLog(sprintf('   => Created sensor average file with tag: %s', avg_tag));
            end

            % --- Step 5: Perform Sensor Space Comparisons ---
            addLog('Step 5: Performing sensor space relative difference comparisons...');
            sensor_comparison_results = {};
            for iComp = 1:numel(comparisons)
                comp_pair = comparisons{iComp};
                stageA_name = comp_pair{1};
                stageB_name = comp_pair{2};
                comp_name_base = comp_pair{3};
                comp_name_sensor = [comp_name_base, '_sensor'];
                
                condA = [NightName, '_', stageA_name];
                condB = [NightName, '_', stageB_name];
                tagA = [stageA_name, '_sensor_avg'];
                tagB = [stageB_name, '_sensor_avg'];
                
                addLog(sprintf('Comparing (sensor): %s', comp_name_sensor));

                % Select File A & B (averaged data files)
                sFileA_struct = bst_process('CallProcess', 'process_select_files_data', [], [], ...
                    'subjectname', SubjName, 'condition', condA, 'tag', tagA);
                sFileB_struct = bst_process('CallProcess', 'process_select_files_data', [], [], ...
                    'subjectname', SubjName, 'condition', condB, 'tag', tagB);
                    
                if isempty(sFileA_struct) || isempty(sFileB_struct)
                    addLog(sprintf('WARNING: Could not find one or both sensor avg files for comparison %s. Skipping.', comp_name_sensor));
                    sensor_comparison_results{iComp} = [];
                    continue;
                end
                
                sFileA_cell = {sFileA_struct(1).FileName};
                sFileB_cell = {sFileB_struct(1).FileName};

                % Run comparison: (A-B)/B
                sNewResult = bst_process('CallProcess', 'process_matlab_eval2', sFileA_cell, sFileB_cell, ...
                    'matlab', ['Data = (DataA - DataB) ./ DataB;' 10 'Condition = ''' comp_name_sensor ''';']);
                
                sensor_comparison_results{iComp} = sNewResult;
                if ~isempty(sNewResult)
                    addLog(sprintf('   => Created sensor comparison condition: %s', comp_name_sensor));
                else
                    addLog(sprintf('   ERROR: Failed to create sensor comparison condition: %s', comp_name_sensor));
                end
            end

            % --- Step 6: Take 2D Topography Screenshots ---
            addLog('Step 6: Generating 2D topography contact sheets...');
            
            % Create a list of all sensor data files to screenshot
            all_sensor_files_to_screenshot = {};
            
            % Add averaged sensor data files
            for iStage = 1:numel(stages)
                sResult = bst_process('CallProcess', 'process_select_files_data', [], [], ...
                    'subjectname', SubjName, ...
                    'condition',   [NightName, '_', stages{iStage}], ...
                    'tag',         [stages{iStage}, '_sensor_avg']);
                if ~isempty(sResult)
                    all_sensor_files_to_screenshot{end+1} = sResult;
                end
            end
            
            % Add sensor comparison files
            for iComp = 1:numel(sensor_comparison_results)
                if ~isempty(sensor_comparison_results{iComp})
                    all_sensor_files_to_screenshot{end+1} = sensor_comparison_results{iComp};
                end
            end

            % Loop through all files and generate 2D contact sheets
            for iRes = 1:numel(all_sensor_files_to_screenshot)
                sFile = all_sensor_files_to_screenshot{iRes};
                file_cond_name = sFile(1).Condition;
                
                % Create specific output directory for this sensor result
                outputDir = fullfile(baseOutputDir, 'sensor', file_cond_name);
                if ~exist(outputDir, 'dir'), mkdir(outputDir); end

                try
                    % Construct a simpler filename
                    outputFileName = fullfile(outputDir, [SubjName, '_', NightName, '_2D_topo.png']);
                    addLog(sprintf('Screenshotting 2D topography for %s to %s', file_cond_name, outputFileName));
                    
                    % Create the initial topography figure
                    hFig = view_topography(sFile(1).FileName, 'EEG', '2DSensorCap');
                    if isempty(hFig)
                        addLog(sprintf('ERROR: Could not create topography figure for %s.', file_cond_name));
                        continue;
                    end
                    
                    % Create contact sheet figure
                    hContactFig = view_contactsheet(hFig, 'time', 'fig', [], 11, [-0.05, 0.05]);
                    
                    % Get the image definition (RGB) from the figure and save
                    img = get(findobj(hContactFig, 'Type', 'image'), 'CData');
                    out_image(outputFileName, img);
                    
                    % Close figures
                    close(hContactFig);
                    close(hFig);
                    addLog('   => Screenshot saved.');
                    
                catch ME_screenshot
                    addLog(sprintf('ERROR generating 2D topography screenshot for %s: %s', file_cond_name, ME_screenshot.message));
                    if exist('hFig', 'var') && ishandle(hFig), close(hFig); end
                    if exist('hContactFig', 'var') && ishandle(hContactFig), close(hContactFig); end
                end
            end
        end % End night loop
    end % End subject loop

    addLog('=== Comparison Pipeline End ===');
    disp(['Cumulative log saved to: ', logName]);
end
