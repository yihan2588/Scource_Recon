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
%           * For each wave .set => import => condition=NightX_NegPeak, Overwrite channels
%           * Compute noise covariance using NightX_noise, Copy file, Reload study
%           * Compute Head model (once per subject, first night), Capture path
%           * Copy Head Model file if needed (for nights > 1), Reload study
%           * run sLORETA specifically for “NightX_NegPeak” condition
%           * Screenshot + CSV outputs
%
% NOTE: Each night is its own condition. So you will see in Brainstorm:
%       Subject_001
%         -> Night1_noise
%         -> Night1_NegPeak
%         -> Night2_noise
%         -> Night2_NegPeak
%       etc.

    % (1) Setup cumulative logging - Initial definition, path updated later
    logName = 'pipeline_status.log';
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
        logName = fullfile(userDir, 'pipeline_status.log');
        addLog(sprintf('Logging to: %s', logName));
    else
        addLog('WARNING: STRENGTHEN directory not valid or not found. Logging to script directory.');
        logName = fullfile(scriptDir, 'pipeline_status.log'); % Fallback
    end


    % (2.5) Allow user to select which subjects and nights to process
    [selectedSubjects, selectedNights] = selectSubjectsNights(subjects);
    addLog('User selected subjects/nights.');

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

        % We'll do only one head model per subject, referencing the "Night1_NegPeak"
        % or we do "NightX_NegPeak" for the first night. Up to you, but we'll do it for the first night encountered.
        didHeadModel = false;

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
            catch ME_noiseImp
                 addLog(sprintf('ERROR importing noise EEG for %s/%s: %s.', SubjName, NightName, ME_noiseImp.message));
                 % Decide whether to continue night processing
            end

            % (C) For each wave .set => import => condition=[NightName, '_NegPeak']
            waveFileMap = containers.Map(); % Create a storage for mapping wave files to their imported results
            condPeak = [NightName, '_NegPeak']; % Define condition name once

            for iFile = 1:numel(mainEEGFiles)
                thisMain = mainEEGFiles{iFile};
                [~, slowBase] = fileparts(thisMain);
                addLog(sprintf('Processing waveFile %d/%d: %s', iFile, numel(mainEEGFiles), thisMain));

                try
                    [nImported, importedFiles] = importMainEEG(SubjName, thisMain, NightName, [-0.05, 0.05]);
                    addLog(['   => Imported [', num2str(nImported), '] epoch(s) as "', condPeak, '".']);

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
                try
                    negPeakChanFile = getNegPeakChannelFile(SubjName, condPeak);
                    if ~isempty(negPeakChanFile)
                        [nChUsed, ~] = OverwriteChannel(SubjName, negPeakChanFile, userDir);
                        addLog(['   => Overwrote channels => ', num2str(nChUsed), ' matched']);
                    else
                        addLog('WARNING:    => No channel file found => skipping OverwriteChannel.');
                    end
                catch ME_overwrite
                     addLog(sprintf('ERROR overwriting channels for %s: %s.', thisMain, ME_overwrite.message));
                end
            end % End mainEEGFiles loop

            % (D) Compute noise cov for this night => condition=[NightName,'_noise']
            try
                computeNoiseCov(SubjName, condNoise); % Use entire duration
                addLog(['   => Noise cov computed => ', noiseEEGFile]);
            catch ME_noiseCov
                 addLog(sprintf('ERROR computing noise cov for %s/%s: %s.', SubjName, NightName, ME_noiseCov.message));
                 % Decide whether to continue
            end

            % Explicitly copy noisecov_full.mat and reload study (Copy + Reload Strategy)
            try
                % Get study info for noise condition AGAIN after computation
                [sStudyNoise, iStudyNoise] = bst_get('StudyWithCondition', [SubjName '/' condNoise]);

                % Check if NoiseCov structure and FileName exist
                if ~isempty(sStudyNoise) && isfield(sStudyNoise, 'NoiseCov') && ~isempty(sStudyNoise.NoiseCov) && isfield(sStudyNoise.NoiseCov(1), 'FileName') && ~isempty(sStudyNoise.NoiseCov(1).FileName)

                    sourceNoiseCovRelativePath = sStudyNoise.NoiseCov(1).FileName; % Get RELATIVE path from DB entry
                    sourceNoiseCovFullPath = file_fullpath(sourceNoiseCovRelativePath); % Convert source to FULL path

                    % Check if the source file actually exists on disk (using the FULL path)
                    if ~isempty(sourceNoiseCovFullPath) && exist(sourceNoiseCovFullPath, 'file')
                        % Get destination study info
                        [sStudyPeak, iStudyPeak] = bst_get('StudyWithCondition', [SubjName '/' condPeak]);
                        if ~isempty(sStudyPeak) && isfield(sStudyPeak, 'FileName') && ~isempty(sStudyPeak.FileName)
                            % Get FULL path to destination study file, then get folder path
                            destStudyFullPath = file_fullpath(sStudyPeak.FileName);
                            destPeakFolderFullPath = fileparts(destStudyFullPath);
                            destNoiseCovFullPath = fullfile(destPeakFolderFullPath, 'noisecov_full.mat');

                            % Perform the copy using FULL source and destination paths
                            copyfile(sourceNoiseCovFullPath, destNoiseCovFullPath);
                            addLog(sprintf('   => Copied noisecov_full.mat from %s to %s', condNoise, condPeak));

                            % Reload the destination study for Brainstorm to recognize the copied file
                            db_reload_studies(iStudyPeak);
                            addLog(sprintf('   => Reloaded study: %s', condPeak));
                        else
                            addLog(sprintf('WARNING: Could not find destination study %s to copy NoiseCov.', condPeak));
                        end
                    else
                        addLog(sprintf('WARNING: Source noisecov_full.mat (%s / %s) reported by DB does not exist on disk or path invalid!', sourceNoiseCovRelativePath, sourceNoiseCovFullPath));
                    end
                else
                    addLog(sprintf('WARNING: Could not find NoiseCov entry in database for %s after computation.', condNoise));
                end
            catch ME_copyReloadNoise
                addLog(sprintf('ERROR copying/reloading noise cov for %s/%s: %s.', SubjName, NightName, ME_copyReloadNoise.message));
            end

            % (E) Head-model computed once per subject or per night. We'll do once per subject if not done.
            if ~didHeadModel
                try
                    computeHeadModel(SubjName, condPeak);
                    addLog(['   => Head-model computed (once) for condition=', condPeak]);
                    didHeadModel = true;
                    % Capture the FULL path of the computed head model for later copying
                    sStudyPeak = bst_get('StudyWithCondition', [SubjName '/' condPeak]);
                    if ~isempty(sStudyPeak) && isfield(sStudyPeak, 'HeadModel') && ~isempty(sStudyPeak.HeadModel) && isfield(sStudyPeak.HeadModel(1), 'FileName') && ~isempty(sStudyPeak.HeadModel(1).FileName)
                        sourceHeadModelRelativePath = sStudyPeak.HeadModel(1).FileName;
                        capturedHeadModelFullPath = file_fullpath(sourceHeadModelRelativePath); % Store the full path
                        if ~isempty(capturedHeadModelFullPath)
                            addLog(sprintf('   => Captured head model full path: %s', capturedHeadModelFullPath));
                        else
                            addLog(sprintf('WARNING: Could not resolve full path for head model: %s', sourceHeadModelRelativePath));
                        end
                    else
                        addLog(sprintf('WARNING: Could not find HeadModel entry in database for %s to capture path.', condPeak));
                    end
                catch ME_headModel
                    addLog(sprintf('ERROR computing head model for %s/%s: %s.', SubjName, NightName, ME_headModel.message));
                    % Decide whether to continue
                end
            end

            % Copy Head Model file before running sLORETA (if not the first night)
            try
                if didHeadModel && ~isempty(capturedHeadModelFullPath) && exist(capturedHeadModelFullPath, 'file')
                    % Get current study info
                    [sStudyPeak, iStudyPeak] = bst_get('StudyWithCondition', [SubjName '/' condPeak]);
                    if ~isempty(sStudyPeak) && isfield(sStudyPeak, 'FileName') && ~isempty(sStudyPeak.FileName)
                        % Get FULL path to destination study file, then get folder path
                        destStudyFullPath = file_fullpath(sStudyPeak.FileName);
                        destPeakFolderFullPath = fileparts(destStudyFullPath);
                        targetHeadModelPath = fullfile(destPeakFolderFullPath, 'headmodel_surf_openmeeg.mat');

                        % Avoid copying onto itself (compare full paths)
                        if ~strcmpi(capturedHeadModelFullPath, targetHeadModelPath) % Use strcmpi for case-insensitivity
                            copyfile(capturedHeadModelFullPath, targetHeadModelPath);
                            addLog(sprintf('   => Copied head model to %s', condPeak));
                            % Reload the destination study
                            db_reload_studies(iStudyPeak);
                            addLog(sprintf('   => Reloaded study: %s', condPeak));
                        end
                    else
                        addLog(sprintf('WARNING: Could not find study %s to copy head model into.', condPeak));
                    end
                elseif didHeadModel % Head model was computed but path is invalid
                     addLog(sprintf('WARNING: Source head model path not valid or file not found (%s). Cannot copy head model for %s.', capturedHeadModelFullPath, condPeak));
                end
                % If didHeadModel is false, it means this is the first night, HM was just computed, no copy needed.
            catch ME_copyReloadHM_preSLORETA
                addLog(sprintf('ERROR copying/reloading head model for %s: %s', condPeak, ME_copyReloadHM_preSLORETA.message));
            end

            % (F) Now run sLORETA for condition=[NightName,'_NegPeak']
            try
                runSLORETA(SubjName, condPeak);
                addLog(['(Night) sLORETA done for subject=', SubjName, ' night=', NightName]);
            catch ME_sloreta
                 addLog(sprintf('ERROR running sLORETA for %s/%s: %s.', SubjName, NightName, ME_sloreta.message));
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

                baseName = [SubjName,'_',NightName];  % For screenshot naming, e.g. "Subject_001_Night1"

                % Screenshot channels + noise
                try
                    screenshotChannels3D_SubjCond(SubjName, condPeak, baseName);
                    addLog('   => Channels screenshot saved.');
                catch ME_scrChan
                    addLog(sprintf('ERROR saving channel screenshot: %s', ME_scrChan.message));
                end
                try
                    screenshotAllNoiseCov(SubjName, condPeak, 'EEG', baseName);
                    addLog('   => Noise covariance screenshot saved.');
                catch ME_scrNoise
                    addLog(sprintf('ERROR saving noise cov screenshot: %s', ME_scrNoise.message));
                end

                % Retrieve sLORETA results for [NightName,'_NegPeak']
                sResults = []; % Initialize
                try
                    sResults = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                        'subjectname',   SubjName, ...
                        'condition',     condPeak, ...
                        'tag',           'sLORETA', ...
                        'includebad',    0, ...
                        'outprocesstab', 'process1'); % Using process1 might be slow if many results
                    if isempty(sResults)
                        addLog('WARNING: No sLORETA results found to export.');
                    end
                catch ME_getResults
                     addLog(sprintf('ERROR retrieving sLORETA results: %s', ME_getResults.message));
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
                         addLog(sprintf('ERROR mapping results to data files: %s', ME_map.message));
                    end

                    for iRes = 1:numel(sResults)
                        thisResFile = sResults(iRes).FileName;
                        [~,resBase,~] = fileparts(thisResFile);

                        % Find original wave name for this result
                        originalWaveName = '';
                        try
                            if isKey(resDataMap, thisResFile)
                                dataFile = resDataMap(thisResFile);
                                if isKey(waveFileMap, dataFile)
                                    originalWaveName = waveFileMap(dataFile);
                                end
                            end
                        catch ME_findName
                             addLog(sprintf('ERROR finding original wave name for %s: %s', resBase, ME_findName.message));
                        end

                        % If we found the original wave name, use it in the output filenames
                        if ~isempty(originalWaveName)
                            outCsv = [originalWaveName, '_scouts.csv'];
                            wavePNG = [originalWaveName, '_Source.png'];
                            try
                                scoutExportCSV_specificResult(thisResFile, outCsv);
                                addLog(['(Night) CSV => ', outCsv]);
                            catch ME_csv
                                addLog(sprintf('ERROR exporting CSV %s: %s', outCsv, ME_csv.message));
                            end
                            try
                                screenshotSourceColormap_specificResult(thisResFile, wavePNG);
                                addLog(['(Night) Screenshot => ', wavePNG]);
                            catch ME_png
                                addLog(sprintf('ERROR saving screenshot %s: %s', wavePNG, ME_png.message));
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
                                screenshotSourceColormap_specificResult(thisResFile, wavePNG);
                                addLog(['(Night) Screenshot => ', wavePNG, ' (no wave mapping found)']);
                            catch ME_png
                                addLog(sprintf('ERROR saving screenshot %s: %s', wavePNG, ME_png.message));
                            end
                        end
                    end % End export loop
                    addLog(['(Night) Finished attempting CSV + PNG exports for => ', NightName]);
                end % End if ~isempty(sResults)

            catch ME_export
                addLog(sprintf('ERROR during export section for night=%s: %s', NightName, ME_export.message));
            end
            cd(oldDir); % Change back directory regardless of errors in 'try' block

            addLog(['DONE with subject=', SubjName, ' night=', NightName,'-------------------------------']);
        end % End NIGHT LOOP (nightIdx)

        % === REMOVED old head model copy loop ===

    end % End SUBJECT LOOP (subIdx)

    % 4) Final log message
    addLog('=== Pipeline End ===');
    % Log file is already saved cumulatively in the working directory.
    % No final move needed.
    disp(['Cumulative log saved to: ', logName]);

end
