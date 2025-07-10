function main()
    % Get directory of this script
    scriptDir = fileparts(mfilename('fullpath'));
    % Add it (and subfolders, if any) to MATLAB path
    addpath(scriptDir);

    % Prompt for and add Brainstorm path
    bstPath = '';
    while isempty(bstPath) || ~exist(bstPath, 'dir')
        bstPath = input('Enter the path to your local Brainstorm code folder (e.g., /Users/wyh/brainstorm3): ', 's');
        if isempty(bstPath)
             disp('Path cannot be empty.');
        elseif ~exist(bstPath, 'dir')
             disp(['Directory not found: ', bstPath]);
             bstPath = ''; % Reset to loop again
        end
    end
    addpath(bstPath);
    disp(['Added Brainstorm path: ', bstPath]);
% MAIN: Single-pass pipeline that imports noise, wave epochs, sets up noise cov,
%       BEM/head model, then runs sLORETA for each subject-night separately.
%
% LOGIC (overview):
%   1) Gather subjects from parseStrengthenPaths().
%   2) Allow user to select which subjects/nights to process.
%   3) For each selected subject:
%       - Import Anatomy
%       - For each selected Night:
%           * Import the noise EEG => condition=NightX_noise
%           * For each wave .set => import => condition=NightX_<stage>, Overwrite channels
%           * Compute noise covariance using NightX_noise, Copy file, Reload study
%           * Compute Head model (once per subject, first stage condition), Capture path
%           * Copy Head Model file if needed, Reload study
%           * run sLORETA specifically for each “NightX_<stage>” condition
%           * Screenshot + CSV outputs for each stage condition
%
% NOTE: Each night will now have multiple conditions based on stage:
%       Subject_001
%         -> Night1_noise
%         -> Night1_pre-stim
%         -> Night1_stim
%         -> Night1_post-stim
%         -> Night2_noise
%         -> Night2_pre-stim
%         -> Night2_stim
%         -> Night2_post-stim
%       etc.

    % (1) Setup cumulative logging - Initial definition, path updated later
    logName = 'recon_run.log';
    logMessages = {}; % Initialize cell array for messages

    % Helper function to add message and write log
    function addLog(msg)
        timestampStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        fullMsg = sprintf('[%s] %s', timestampStr, msg);
        disp(fullMsg); % Display in command window
        logMessages{end+1} = fullMsg; % Append to cell array
        % Check if logName has been updated to a full path before writing
        if contains(logName, filesep) % Basic check if it looks like a full path
             writeCumulativeLog(logName, logMessages); % Overwrite log file
        else
             % Write to current directory if logName wasn't updated (shouldn't happen in normal flow)
             writeCumulativeLog(fullfile(pwd, logName), logMessages);
        end
    end

    addLog('=== Pipeline Start ===');

    % Ensure Brainstorm is running (in nogui mode if not already)
    if ~brainstorm('status')
        addLog('Brainstorm not running. Starting in nogui mode...');
        brainstorm nogui;
        pause(5); % Give Brainstorm a moment to initialize
        addLog('Brainstorm started.');
    else
        addLog('Brainstorm already running.');
    end

    % === Protocol Selection/Creation ===
    protocolNames = {};
    numExisting = 0;
    DbDir = bst_get('BrainstormDbDir');
    if isempty(DbDir) || ~exist(DbDir, 'dir')
        addLog('ERROR: Brainstorm database directory not found or not set. Exiting.');
        return;
    end
    addLog(['Scanning Brainstorm DB directory for protocol folders: ', DbDir]);

    % List immediate subdirectories
    dirContents = dir(DbDir);
    subDirs = dirContents([dirContents.isdir]); % Get only directories
    subDirs = subDirs(~ismember({subDirs.name},{'.','..'})); % Remove '.' and '..'

    if ~isempty(subDirs)
        validProtocolNames = {};
        for iDir = 1:length(subDirs)
            protocolFolderName = subDirs(iDir).name;
            % Correct path: Look inside the 'data' subdirectory
            protocolMatPath = fullfile(DbDir, protocolFolderName, 'data', 'protocol.mat');
            if exist(protocolMatPath, 'file')
                protocolName = ''; % Initialize
                try
                    matData = load(protocolMatPath, 'ProtocolInfo'); % Load only ProtocolInfo variable
                    % Check standard location
                    if isfield(matData, 'ProtocolInfo') && isstruct(matData.ProtocolInfo) && ...
                       isfield(matData.ProtocolInfo, 'Comment') && ischar(matData.ProtocolInfo.Comment) && ~isempty(matData.ProtocolInfo.Comment)
                        protocolName = matData.ProtocolInfo.Comment;
                    end
                    % Removed check for top-level 'Comment'

                    % Add if found and not duplicate
                    if ~isempty(protocolName) && ~ismember(protocolName, validProtocolNames)
                        validProtocolNames{end+1} = protocolName; %#ok<AGROW>
                    elseif isempty(protocolName)
                        addLog(sprintf('Warning: Could not extract protocol name from %s', protocolMatPath));
                    end
                catch ME_load
                    addLog(sprintf('Warning: Could not load or read protocol info from %s: %s', protocolMatPath, ME_load.message));
                end
            else
                 addLog(sprintf('Note: No protocol.mat found in directory: %s', protocolFolderName));
            end
        end
        if ~isempty(validProtocolNames)
            protocolNames = validProtocolNames;
            numExisting = numel(protocolNames);
        end
    end

    disp(' '); % Add a blank line for readability
    disp('=== Available Brainstorm Protocols ===');
    if numExisting == 0
        disp('No existing protocols found.');
    else
        % Sort names for consistent display order
        protocolNames = sort(protocolNames);
        for i = 1:numExisting
            disp([num2str(i) ': ' protocolNames{i}]);
        end

    end
    disp([num2str(numExisting + 1) ': Create New Protocol']);
    disp(' '); % Add a blank line

    protocolActivated = false;
    while ~protocolActivated
        try
            choiceStr = input(['Select protocol number (1-' num2str(numExisting) ') or ' num2str(numExisting + 1) ' to create new: '], 's');
            choiceNum = str2double(choiceStr);

            if isnan(choiceNum) || choiceNum < 1 || choiceNum > (numExisting + 1) || floor(choiceNum) ~= choiceNum
                disp('Invalid input. Please enter a valid number from the list.');
            elseif choiceNum <= numExisting % Existing protocol selected
                selectedProtocolName = protocolNames{choiceNum};
                iProtocol = bst_get('Protocol', selectedProtocolName);
                if isempty(iProtocol)
                    addLog(['ERROR: Could not get index for protocol: ' selectedProtocolName '. Please ensure Brainstorm is fully initialized.']);
                    % Optional: could try reloading DB here? db_reload_database('update'); pause(2); iProtocol = bst_get('Protocol', selectedProtocolName);
                    if isempty(iProtocol)
                        addLog('Exiting.'); return;
                    end
                end
                gui_brainstorm('SetCurrentProtocol', iProtocol);
                addLog(['Selected existing protocol: ', selectedProtocolName]);
                protocolActivated = true;
            else % Create new protocol
                newProtocolName = '';
                while isempty(newProtocolName)
                    newProtocolName = strtrim(input('Enter name for the new protocol: ', 's'));
                    if isempty(newProtocolName)
                        disp('Protocol name cannot be empty.');
                    % Check if name already exists (case-insensitive)
                    elseif numExisting > 0 && any(strcmpi(newProtocolName, protocolNames))
                         disp(['Protocol "', newProtocolName, '" already exists. Choose a different name.']);
                         newProtocolName = ''; % Force re-entry
                    end
                end
                addLog(['Creating new protocol: ', newProtocolName]);
                % Use gui_brainstorm('CreateProtocol', ProtocolName, UseDefaultAnat, UseDefaultChannel)
                newProtocolIndex = gui_brainstorm('CreateProtocol', newProtocolName, 0, 0);

                if ~isempty(newProtocolIndex) && (newProtocolIndex > 0) % Check if index is valid
                     % gui_brainstorm should already set it active, but set again just in case
                     bst_set('iProtocol', newProtocolIndex);
                     addLog(['New protocol "', newProtocolName, '" created and activated.']);
                     protocolActivated = true; % Mark selection as done
                else
                     addLog(['ERROR: Failed to create or activate protocol "', newProtocolName, '". Exiting.']);
                     return; % Exit if creation failed
                end
            end
        catch ME
            addLog(['Error processing input: ', ME.message, '. Please try again.']);
            % Loop continues
        end
    end
    % === End Protocol Selection/Creation ===


    % (2) Prompt user for STRENGTHEN path
    userDir = input('Enter the path to STRENGTHEN folder (containing Assets/, Structural/, EEG_data/): ','s');
    if isempty(userDir)
        subjects = parseStrengthenPaths(); % default path is handled inside parseStrengthenPaths if needed
        % Re-get userDir if default was used inside parseStrengthenPaths
        if isempty(userDir) && ~isempty(subjects) && isfield(subjects(1), 'AnatDir') && ~isempty(subjects(1).AnatDir)
             % Infer userDir from the first subject's AnatDir path
             [subjParent, ~] = fileparts(subjects(1).AnatDir);
             [userDir, ~] = fileparts(subjParent);
             addLog(sprintf('Inferred STRENGTHEN directory: %s', userDir));
        end
    else
        subjects = parseStrengthenPaths(userDir);
    end
    addLog('Parsed STRENGTHEN paths.');

    % Define log file path using userDir AFTER it's determined
    if ~isempty(userDir) && exist(userDir, 'dir')
        logName = fullfile(userDir, 'recon_run.log');
        addLog(sprintf('Logging to: %s', logName));
    else
        addLog('WARNING: STRENGTHEN directory not valid or not found. Logging to script directory.');
        logName = fullfile(scriptDir, 'recon_run.log'); % Fallback
    end


    % (2.5) Allow user to select which subjects and nights to process
    [selectedSubjects, selectedNights] = selectSubjectsNights(subjects);
    addLog('User selected subjects/nights.');

    % (2.6) Prompt user for bad channels for each selected subject/night
    badChannelMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for subIdx = 1:numel(selectedSubjects)
        iSubj = selectedSubjects(subIdx);
        SubjName = subjects(iSubj).SubjectName;
        selectedNightsForSubj = selectedNights{iSubj};
        for nightIdx = 1:numel(selectedNightsForSubj)
            iN = selectedNightsForSubj(nightIdx);
            NightName = subjects(iSubj).Nights(iN).NightName;
            
            validInput = false;
            while ~validInput
                prompt = sprintf('Enter bad channels for %s - %s (comma-separated, format E001,E002) or press Enter for none: ', SubjName, NightName);
                badChannelsStr = input(prompt, 's');

                if isempty(badChannelsStr)
                    addLog(sprintf('No bad channels entered for %s - %s.', SubjName, NightName));
                    validInput = true;
                    continue;
                end

                % Split the string by commas and remove any whitespace
                badChannels = strtrim(strsplit(badChannelsStr, ','));
                % Filter out any empty elements that might result from trailing commas
                badChannels = badChannels(~cellfun('isempty', badChannels));

                % Validate format of each channel name
                isInvalid = cellfun(@(c) isempty(regexp(c, '^E\d{3}$', 'once')), badChannels);

                if any(isInvalid)
                    invalidNames = strjoin(badChannels(isInvalid), ', ');
                    disp(['ERROR: The following channel names are invalid: ', invalidNames]);
                    disp('Please use the format Exxx (e.g., E001, E023).');
                    % Loop will continue
                else
                    mapKey = [SubjName '_' NightName];
                    badChannelMap(mapKey) = badChannels;
                    addLog(sprintf('Stored %d valid bad channels for %s.', numel(badChannels), mapKey));
                    validInput = true;
                end
            end
        end
    end


    % If no subjects were selected, exit
    if isempty(selectedSubjects)
        addLog('No subjects selected. Exiting.');
        return;
    end

    % Loop over selected subjects
    for subIdx = 1:numel(selectedSubjects)
        iSubj = selectedSubjects(subIdx);
        SubjName = subjects(iSubj).SubjectName;
        AnatDir  = subjects(iSubj).AnatDir;
        capturedHeadModelFullPath = ''; % Initialize path for head model copying (using full path now)
        didHeadModel = false; % Initialize for head model computation
        firstStageCondForSubject = ''; % Capture the condition of the first file processed for HM

        addLog(sprintf('Starting Subject %d/%d: %s', subIdx, numel(selectedSubjects), SubjName));

        % Import anatomy for this subject
        try
            importAnatomy(SubjName, AnatDir);
            addLog(['1) Anatomy imported => ', SubjName]);
        catch ME_anat
             addLog(sprintf('ERROR importing anatomy for %s: %s. Skipping subject.', SubjName, ME_anat.message));
             continue;
        end

        if ~isfield(subjects(iSubj), 'Nights') || isempty(subjects(iSubj).Nights)
            addLog(sprintf('WARNING: No nights found for subject=%s. Skipping subject.', SubjName));
            continue;
        end

        % BEM surfaces generated once per subject:
        try
            generateBEM(SubjName);
            addLog('   => BEM surfaces generated (once per subj)');
        catch ME_bem
            addLog(sprintf('ERROR generating BEM for %s: %s.', SubjName, ME_bem.message));
            % Decide whether to continue or skip subject based on BEM failure
            addLog('Continuing without BEM generation for now...'); % Or 'Skipping subject due to BEM error.' and continue;
        end

        % For each selected night
        selectedNightsForSubj = selectedNights{iSubj};
        if isempty(selectedNightsForSubj)
            addLog(sprintf('WARNING: No nights selected for subject=%s. Skipping subject nights.', SubjName));
            continue; % Skip to next subject if no nights selected for this one
        end

        for nightIdx = 1:numel(selectedNightsForSubj)
            iN = selectedNightsForSubj(nightIdx);
            NightName    = subjects(iSubj).Nights(iN).NightName;
            mainEEGFiles = subjects(iSubj).Nights(iN).MainEEGFiles;
            noiseEEGFile = subjects(iSubj).Nights(iN).NoiseEEGFile;
            addLog(sprintf('Starting Night %d/%d: %s', nightIdx, numel(selectedNightsForSubj), NightName));


            if isempty(mainEEGFiles)
                addLog(sprintf('WARNING: No mainEEGFiles for %s / %s. Skipping night.', SubjName, NightName));
                continue; % Skip to the next night
            end

            % Build SourceRecon folder (just for external .png/.csv export):
            sourceReconDir = ''; % Initialize
            try
                firstMain       = mainEEGFiles{1};
                [mainEEGDir, ~] = fileparts(firstMain);
                slowWaveParent  = fileparts(mainEEGDir);
                nightOutputDir  = fileparts(slowWaveParent);
                sourceReconDir  = fullfile(nightOutputDir, 'SourceRecon');
                if ~exist(sourceReconDir, 'dir')
                    mkdir(sourceReconDir);
                    addLog(sprintf('Created SourceRecon directory: %s', sourceReconDir));
                end
            catch ME_dir
                 addLog(sprintf('ERROR creating SourceRecon directory for %s/%s: %s. Skipping night.', SubjName, NightName, ME_dir.message));
                 continue; % Skip this night if output dir fails
            end

            addLog('--------------------------------------------------');
            addLog(sprintf('Processing Subject=%s, Night=%s', SubjName, NightName));
            addLog(sprintf('NoiseEEG=%s', noiseEEGFile));
            addLog(sprintf('SourceRecon=%s', sourceReconDir));

            % (B) Import noise EEG => condition = [NightName, '_noise']
            try
                condNoise = [NightName, '_noise'];
                importNoiseEEG(SubjName, noiseEEGFile, condNoise); % Import entire duration
                addLog(['   => Noise EEG imported => ', noiseEEGFile]);

                % Set bad channels for the noise data
                mapKey = [SubjName '_' NightName];
                if isKey(badChannelMap, mapKey)
                    set_bad_channel(SubjName, condNoise, badChannelMap(mapKey), @addLog);
                end
            catch ME_noiseImp
                 addLog(sprintf('ERROR importing noise EEG for %s/%s: %s.', SubjName, NightName, ME_noiseImp.message));
                 % Decide whether to continue night processing
            end

            % (C) For each wave .set => import => condition=[NightName, '_<stage>']
            waveFileMap = containers.Map(); % Create a storage for mapping wave files to their imported results
            processedStageConditions = {}; % Collect unique stage conditions processed this night

            for iFile = 1:numel(mainEEGFiles)
                thisMain = mainEEGFiles{iFile};
                [~, slowBase] = fileparts(thisMain);
                addLog(sprintf('Processing waveFile %d/%d: %s', iFile, numel(mainEEGFiles), thisMain));

                % Extract stage from filename (e.g., 'proto1_post-stim_sw1_E2' -> 'post-stim')
                parts = strsplit(slowBase, '_');
                if numel(parts) < 2
                    addLog(sprintf('WARNING: Could not parse stage from filename: %s. Skipping.', slowBase));
                    continue; % Skip this file
                end
                stage = parts{2};
                condStage = [NightName '_' stage];

                % Add to list of processed stage conditions if new
                if ~ismember(condStage, processedStageConditions)
                    processedStageConditions{end+1} = condStage; %#ok<AGROW>
                end
                % Capture first stage condition for head model computation
                if isempty(firstStageCondForSubject)
                    firstStageCondForSubject = condStage;
                end


                try
                    [nImported, importedFiles] = importMainEEG(SubjName, thisMain, condStage, [-0.05, 0.05]);
                    addLog(['   => Imported [', num2str(nImported), '] epoch(s) as "', condStage, '".']);

                    % Store mapping between imported files and original wave name
                    if nImported > 0 && ~isempty(importedFiles)
                        for i = 1:numel(importedFiles)
                            waveFileMap(importedFiles{i}) = slowBase;
                        end
                    end
                catch ME_mainImp
                    addLog(sprintf('ERROR importing main EEG %s: %s.', thisMain, ME_mainImp.message));
                    % Continue to next file
                    continue;
                end

                % Overwrite channel if we can find it:
                newChanFile = '';
                try
                    negPeakChanFile = getNegPeakChannelFile(SubjName, condStage);
                    if ~isempty(negPeakChanFile)
                        [nChUsed, newChanFile] = OverwriteChannel(SubjName, negPeakChanFile, userDir);
                        addLog(['   => Overwrote channels => ', num2str(nChUsed), ' matched']);
                    else
                        addLog('WARNING:    => No channel file found => skipping OverwriteChannel.');
                    end
                catch ME_overwrite
                     addLog(sprintf('ERROR overwriting channels for %s: %s.', thisMain, ME_overwrite.message));
                end

                % Project electrodes to scalp surface
                try
                    if ~isempty(newChanFile)
                        project_electrodes_to_scalp(SubjName, condStage, newChanFile, @addLog);
                        addLog('   => Projected electrodes to scalp surface.');
                    else
                        addLog('WARNING:    => No new channel file from OverwriteChannel => skipping projection.');
                    end
                catch ME_project
                    addLog(sprintf('ERROR projecting electrodes for %s: %s.', thisMain, ME_project.message));
                end

                % Set bad channels for the slow wave data
                mapKey = [SubjName '_' NightName];
                if isKey(badChannelMap, mapKey)
                    set_bad_channel(SubjName, condStage, badChannelMap(mapKey), @addLog);
                end
            end % End mainEEGFiles loop

            % (D) Compute noise cov for this night => condition=[NightName,'_noise']
            % This is done once per night, using the noise file.
            try
                computeNoiseCov(SubjName, condNoise); % Use entire duration
                addLog(['   => Noise cov computed => ', noiseEEGFile]);
            catch ME_noiseCov
                 addLog(sprintf('ERROR computing noise cov for %s/%s: %s.', SubjName, NightName, ME_noiseCov.message));
                 % Decide whether to continue
            end

            % (E) Head-model computed once per subject:
            % This block needs to be moved here, outside the night loop, and use firstStageCondForSubject
            if ~didHeadModel && ~isempty(firstStageCondForSubject)
                 try
                     [successHM, capturedHeadModelFullPath] = computeHeadModel(SubjName, firstStageCondForSubject, @addLog);
                     if successHM
                         addLog(['   => Head-model computed (once) for subject=', SubjName, ' using condition=', firstStageCondForSubject]);
                         didHeadModel = true;
                         if ~isempty(capturedHeadModelFullPath)
                             addLog(sprintf('   => Captured head model full path: %s', capturedHeadModelFullPath));
                         else
                             addLog(sprintf('WARNING: Could not resolve full path for head model: %s', capturedHeadModelFullPath));
                         end
                     else
                         addLog(sprintf('ERROR: Head-model computation failed for %s using condition=%s.', SubjName, firstStageCondForSubject));
                     end
                 catch ME_headModel
                     addLog(sprintf('ERROR computing head model for %s: %s.', SubjName, ME_headModel.message));
                     % Decide whether to continue
                 end
            end

            % --- Operations that need to run for EACH stage condition processed this night ---
            for iStageCond = 1:numel(processedStageConditions)
                currentStageCond = processedStageConditions{iStageCond};
                addLog(sprintf('Processing Stage Condition: %s', currentStageCond));

                % Explicitly copy noisecov_full.mat and reload study (Copy + Reload Strategy)
                try
                    % Get study info for noise condition
                    [sStudyNoise, iStudyNoise] = bst_get('StudyWithCondition', [SubjName '/' condNoise]);

                    % Check if NoiseCov structure and FileName exist
                    if ~isempty(sStudyNoise) && isfield(sStudyNoise, 'NoiseCov') && ~isempty(sStudyNoise.NoiseCov) && isfield(sStudyNoise.NoiseCov(1), 'FileName') && ~isempty(sStudyNoise.NoiseCov(1).FileName)

                        sourceNoiseCovRelativePath = sStudyNoise.NoiseCov(1).FileName; % Get RELATIVE path from DB entry
                        sourceNoiseCovFullPath = file_fullpath(sourceNoiseCovRelativePath); % Convert source to FULL path

                        % Check if the source file actually exists on disk (using the FULL path)
                        if ~isempty(sourceNoiseCovFullPath) && exist(sourceNoiseCovFullPath, 'file')
                            % Get destination study info for the current stage condition
                            [sStudyStage, iStudyStage] = bst_get('StudyWithCondition', [SubjName '/' currentStageCond]);
                            if ~isempty(sStudyStage) && isfield(sStudyStage, 'FileName') && ~isempty(sStudyStage.FileName)
                                % Get FULL path to destination study file, then get folder path
                                destStudyFullPath = file_fullpath(sStudyStage.FileName);
                                destStageFolderFullPath = fileparts(destStudyFullPath);
                                destNoiseCovFullPath = fullfile(destStageFolderFullPath, 'noisecov_full.mat');

                                % Perform the copy using FULL source and destination paths
                                copyfile(sourceNoiseCovFullPath, destNoiseCovFullPath);
                                addLog(sprintf('   => Copied noisecov_full.mat from %s to %s', condNoise, currentStageCond));

                                % Reload the destination study for Brainstorm to recognize the copied file
                                db_reload_studies(iStudyStage);
                                addLog(sprintf('   => Reloaded study: %s', currentStageCond));
                            else
                                addLog(sprintf('WARNING: Could not find destination study %s to copy NoiseCov.', currentStageCond));
                            end
                        else
                            addLog(sprintf('WARNING: Source noisecov_full.mat (%s / %s) reported by DB does not exist on disk or path invalid!', sourceNoiseCovRelativePath, sourceNoiseCovFullPath));
                        end
                    else
                        addLog(sprintf('WARNING: Could not find NoiseCov entry in database for %s after computation.', condNoise));
                    end
                catch ME_copyReloadNoise
                    addLog(sprintf('ERROR copying/reloading noise cov for %s: %s.', currentStageCond, ME_copyReloadNoise.message));
                end

                % Copy Head Model file before running sLORETA
                % This logic needs to check if the head model was computed (didHeadModel)
                % and if the captured path is valid.
                try
                    if didHeadModel && ~isempty(capturedHeadModelFullPath) && exist(capturedHeadModelFullPath, 'file')
                        % Get current study info for the current stage condition
                        [sStudyStage, iStudyStage] = bst_get('StudyWithCondition', [SubjName '/' currentStageCond]);
                        if ~isempty(sStudyStage) && isfield(sStudyStage, 'FileName') && ~isempty(sStudyStage.FileName)
                            % Get FULL path to destination study file, then get folder path
                            destStudyFullPath = file_fullpath(sStudyStage.FileName);
                            destStageFolderFullPath = fileparts(destStudyFullPath);
                            targetHeadModelPath = fullfile(destStageFolderFullPath, 'headmodel_surf_openmeeg.mat');

                            % Avoid copying onto itself (compare full paths)
                            if ~strcmpi(capturedHeadModelFullPath, targetHeadModelPath) % Use strcmpi for case-insensitivity
                                copyfile(capturedHeadModelFullPath, targetHeadModelPath);
                                addLog(sprintf('   => Copied head model from %s to %s', firstStageCondForSubject, currentStageCond));
                                % Reload the destination study
                                db_reload_studies(iStudyStage);
                                addLog(sprintf('   => Reloaded study: %s', currentStageCond));
                            end
                        else
                            addLog(sprintf('WARNING: Could not find study %s to copy head model into.', currentStageCond));
                        end
                    elseif didHeadModel % Head model was computed but path is invalid
                         addLog(sprintf('WARNING: Source head model path not valid or file not found (%s). Cannot copy head model for %s.', capturedHeadModelFullPath, currentStageCond));
                    else % Head model was not computed for this subject
                         addLog(sprintf('WARNING: Head model was not computed for subject %s. Skipping head model copy for %s.', SubjName, currentStageCond));
                    end
                catch ME_copyReloadHM_preSLORETA
                    addLog(sprintf('ERROR copying/reloading head model for %s: %s', currentStageCond, ME_copyReloadHM_preSLORETA.message));
                end


                % (F) Now run sLORETA for condition=currentStageCond
                try
                    runSLORETA(SubjName, currentStageCond);
                    addLog(['(Night) sLORETA done for subject=', SubjName, ' condition=', currentStageCond]);
                catch ME_sloreta
                     addLog(sprintf('ERROR running sLORETA for %s/%s: %s.', SubjName, currentStageCond, ME_sloreta.message));
                     % Decide whether to continue
                end

                % (G) Save screenshots and export CSV for sLORETA results
                addLog('(Night) Starting export of screenshots and CSV...');
                oldDir = pwd;
                try
                    if isempty(sourceReconDir) || ~exist(sourceReconDir, 'dir')
                       error('SourceRecon directory is not valid, cannot save outputs.');
                    end
                    cd(sourceReconDir);

                    % Need to get the stage name from currentStageCond for baseName
                    stageParts = strsplit(currentStageCond, '_');
                    if numel(stageParts) < 2
                         stageForBaseName = 'unknownStage';
                         addLog(sprintf('WARNING: Could not parse stage from condition name: %s', currentStageCond));
                    else
                         stageForBaseName = strjoin(stageParts(2:end), '_'); % Join parts after NightName
                    end
                    baseName = [SubjName,'_',NightName,'_',stageForBaseName];  % For screenshot naming

                    % Screenshot channels + noise
                    try
                        screenshotChannels3D_SubjCond(SubjName, currentStageCond, baseName);
                        addLog('   => Channels screenshot saved.');
                    catch ME_scrChan
                        addLog(sprintf('ERROR saving channel screenshot: %s', ME_scrChan.message));
                    end
                    try
                        screenshotAllNoiseCov(SubjName, currentStageCond, 'EEG', baseName);
                        addLog('   => Noise covariance screenshot saved.');
                    catch ME_scrNoise
                        addLog(sprintf('ERROR saving noise cov screenshot: %s', ME_scrNoise.message));
                    end

                    % Retrieve sLORETA results for currentStageCond
                    sResults = []; % Initialize
                    try
                        sResults = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                        'subjectname',   SubjName, ...
                            'condition',     currentStageCond, ...
                            'tag',           'sLORETA', ...
                            'includebad',    0, ...
                            'outprocesstab', 'process1'); % Using process1 might be slow if many results
                        if isempty(sResults)
                            addLog(sprintf('WARNING: No sLORETA results found for condition %s to export.', currentStageCond));
                        end
                    catch ME_getResults
                         addLog(sprintf('ERROR retrieving sLORETA results for %s: %s', currentStageCond, ME_getResults.message));
                    end

                    if ~isempty(sResults)
                        % Create a mapping from result files to their corresponding data files
                        resDataMap = containers.Map();
                        try
                            for iRes = 1:numel(sResults)
                                thisResFile = sResults(iRes).FileName;
                                resInfo = in_bst_results(thisResFile, 0);
                                if ~isempty(resInfo) && isfield(resInfo, 'DataFile') && ~isempty(resInfo.DataFile)
                                    resDataMap(thisResFile) = resInfo.DataFile;
                                end
                            end
                        catch ME_map
                             addLog(sprintf('ERROR mapping results to data files for %s: %s', currentStageCond, ME_map.message));
                        end

                        for iRes = 1:numel(sResults)
                            thisResFile = sResults(iRes).FileName;
                            [~,resBase,~] = fileparts(thisResFile);

                            % Find original wave name for this result
                            originalWaveName = '';
                            try
                                if isKey(resDataMap, thisResFile)
                                    dataFile = resDataMap(thisResFile); % Use the key from the map
                                    if isKey(waveFileMap, dataFile)
                                        originalWaveName = waveFileMap(dataFile);
                                    end
                                end
                            catch ME_findName
                                 addLog(sprintf('ERROR finding original wave name for result %s: %s', resBase, ME_findName.message));
                            end

                            % If we found the original wave name, use it in the output filenames
                            if ~isempty(originalWaveName)
                                % Default data threshold for source visualization
                                % (values below this threshold will be transparent)
                                defaultDataThreshold = 0.3; 

                                outCsv = [originalWaveName, '_scouts.csv'];
                                wavePNG = [originalWaveName, '_Source.png'];
                                try
                                    scoutExportCSV_specificResult(thisResFile, outCsv);
                                    addLog(['(Night) CSV => ', outCsv]);
                                catch ME_csv
                                    addLog(sprintf('ERROR exporting CSV %s: %s', outCsv, ME_csv.message));
                                end
                                try
                                    screenshotSourceColormap_specificResult(thisResFile, wavePNG, defaultDataThreshold);
                                    addLog(['(Night) Screenshot => ', wavePNG]);
                                catch ME_png
                                    addLog(sprintf('ERROR saving screenshot %s: %s', wavePNG, ME_png.message));
                                end
                                try
                                    screenshotSourceMollweide_specificResult(thisResFile, [originalWaveName, '_Mollweide.png'], defaultDataThreshold);
                                    addLog(['(Night) Mollweide Screenshot => ', [originalWaveName, '_Mollweide.png']]);
                                catch ME_mollweide_png
                                    addLog(sprintf('ERROR saving Mollweide screenshot %s: %s', [originalWaveName, '_Mollweide.png'], ME_mollweide_png.message));
                                end
                                try
                                    sensorCapPng = strcat(originalWaveName, '_SensorCap.png');
                                    screenshotSensorCap_specificResult(dataFile, sensorCapPng);
                                    addLog(['(Night) Sensor Cap Screenshot => ', sensorCapPng]);
                                catch ME_sensorcap_png
                                    addLog(sprintf('ERROR saving Sensor Cap screenshot %s: %s', sensorCapPng, ME_sensorcap_png.message));
                                end
                            else
                                % Fallback to the original naming if mapping fails
                                outCsv = [resBase, '_scouts.csv'];
                                wavePNG = [resBase, '_Source.png'];
                                 try
                                    scoutExportCSV_specificResult(thisResFile, outCsv);
                                    addLog(['(Night) CSV => ', outCsv, ' (no wave mapping found)']);
                                catch ME_csv
                                    addLog(sprintf('ERROR exporting CSV %s: %s', outCsv, ME_csv.message));
                                end
                                try
                                    screenshotSourceColormap_specificResult(thisResFile, wavePNG, defaultDataThreshold);
                                    addLog(['(Night) Screenshot => ', wavePNG, ' (no wave mapping found)']);
                                catch ME_png
                                    addLog(sprintf('ERROR saving screenshot %s: %s', wavePNG, ME_png.message));
                                end
                                try
                                    screenshotSourceMollweide_specificResult(thisResFile, [resBase, '_Mollweide.png'], defaultDataThreshold);
                                    addLog(['(Night) Mollweide Screenshot => ', [resBase, '_Mollweide.png'], ' (no wave mapping found)']);
                                catch ME_mollweide_png
                                    addLog(sprintf('ERROR saving Mollweide screenshot %s: %s', [resBase, '_Mollweide.png'], ME_mollweide_png.message));
                                end
                                try
                                    sensorCapPng = strcat(resBase, '_SensorCap.png');
                                    screenshotSensorCap_specificResult(dataFile, sensorCapPng);
                                    addLog(['(Night) Sensor Cap Screenshot => ', sensorCapPng, ' (no wave mapping found)']);
                                catch ME_sensorcap_png
                                    addLog(sprintf('ERROR saving Sensor Cap screenshot %s: %s', sensorCapPng, ME_sensorcap_png.message));
                                end
                            end
                        end % End export loop over sResults
                        addLog(['(Night) Finished attempting CSV + PNG exports for condition => ', currentStageCond]);
                    end % End if ~isempty(sResults)
                catch ME_export
                    addLog(sprintf('ERROR during export section for condition=%s: %s', currentStageCond, ME_export.message));
                end
                cd(oldDir); % Change back directory regardless of errors in 'try' block

            end % End stage condition loop

            addLog(['DONE with subject=', SubjName, ' night=', NightName,'-------------------------------']);
        end % End NIGHT LOOP (nightIdx)
    end % End SUBJECT LOOP (subIdx)

    % 4) Final log message
    addLog('=== Pipeline End ===');
    % Log file is already saved cumulatively in the working directory.
    % No final move needed.
    disp(['Cumulative log saved to: ', logName]);

end
