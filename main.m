function main()
    % Get directory of this script
    scriptDir = fileparts(mfilename('fullpath'));
    % Add it (and subfolders, if any) to MATLAB path
    addpath(scriptDir);
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
%           * Compute noise covariance using NightX_noise
%           * (Once per subject if needed) BEM + Head model (Though you can do once or do each night)
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

    % (1) Optional: Start diary log
    timestampStr = datestr(now, 'yyyy-mm-dd_HHMMSS');
    logName      = ['mainPipelineLog_' timestampStr '.txt'];
    diary(logName);

    % (2) Prompt user for STRENGTHEN path
    userDir = input('Enter the path to STRENGTHEN folder: ','s');
    if isempty(userDir)
        subjects = parseStrengthenPaths(); % default
    else
        subjects = parseStrengthenPaths(userDir);
    end

    % (2.5) Allow user to select which subjects and nights to process
    [selectedSubjects, selectedNights] = selectSubjectsNights(subjects);

    % If no subjects were selected, exit
    if isempty(selectedSubjects)
        disp('No subjects selected. Exiting.');
        return;
    end

    % Loop over selected subjects
    for subIdx = 1:numel(selectedSubjects)
        iSubj = selectedSubjects(subIdx);
        SubjName = subjects(iSubj).SubjectName;
        AnatDir  = subjects(iSubj).AnatDir;

        % Import anatomy for this subject
        importAnatomy(SubjName, AnatDir);
        disp(['1) Anatomy imported => ', SubjName]);

        if ~isfield(subjects(iSubj), 'Nights') || isempty(subjects(iSubj).Nights)
            warning('No nights for subject=%s', SubjName);
            continue;
        end

        % BEM surfaces generated once per subject:
        generateBEM(SubjName);
        disp('   => BEM surfaces generated (once per subj)');

        % We'll do only one head model per subject, referencing the "Night1_NegPeak"
        % or we do "NightX_NegPeak" for the first night. Up to you, but we'll do it for the first night encountered.
        didHeadModel = false;

        % For each selected night
        selectedNightsForSubj = selectedNights{iSubj};
        if isempty(selectedNightsForSubj)
            warning('No nights selected for subject=%s. Skipping.', SubjName);
            continue;
        end

        for nightIdx = 1:numel(selectedNightsForSubj)
            iN = selectedNightsForSubj(nightIdx);
            NightName    = subjects(iSubj).Nights(iN).NightName;
            mainEEGFiles = subjects(iSubj).Nights(iN).MainEEGFiles;
            noiseEEGFile = subjects(iSubj).Nights(iN).NoiseEEGFile;

            if isempty(mainEEGFiles)
                warning('No mainEEGFiles for %s / %s', SubjName, NightName);
                continue;
            end

            % Build SourceRecon folder (just for external .png/.csv export):
            firstMain       = mainEEGFiles{1};
            [mainEEGDir, ~] = fileparts(firstMain);
            slowWaveParent  = fileparts(mainEEGDir);
            nightOutputDir  = fileparts(slowWaveParent);
            sourceReconDir  = fullfile(nightOutputDir, 'SourceRecon');
            if ~exist(sourceReconDir, 'dir')
                mkdir(sourceReconDir);
            end

            fprintf('--------------------------------------------------\n');
            fprintf('Processing Subject=%s, Night=%s\n', SubjName, NightName);
            fprintf('NoiseEEG=%s\n', noiseEEGFile);
            fprintf('SourceRecon=%s\n', sourceReconDir);

            % (B) Import noise EEG => condition = [NightName, '_noise']
            condNoise = [NightName, '_noise'];
            importNoiseEEG(SubjName, noiseEEGFile, condNoise, [0,84]);
            disp(['   => Noise EEG imported => ', noiseEEGFile]);

            % (C) For each wave .set => import => condition=[NightName, '_NegPeak']
            % Create a storage for mapping wave files to their imported results
            waveFileMap = containers.Map();
            
            for iFile = 1:numel(mainEEGFiles)
                thisMain = mainEEGFiles{iFile};
                [~, slowBase] = fileparts(thisMain);

                fprintf('Night=%s, waveFile %d/%d: %s\n', ...
                    NightName, iFile, numel(mainEEGFiles), thisMain);
                [nImported, importedFiles] = importMainEEG(SubjName, thisMain, NightName, [-0.05, 0.05]);
                disp(['   => Imported [', num2str(nImported), '] epoch(s) as "', NightName,'_NegPeak".']);
                
                % Store mapping between imported files and original wave name
                if nImported > 0 && ~isempty(importedFiles)
                    for i = 1:numel(importedFiles)
                        waveFileMap(importedFiles{i}) = slowBase;
                    end
                end

                % Overwrite channel if we can find it:
                negPeakChanFile = getNegPeakChannelFile(SubjName, [NightName,'_NegPeak']);
                if ~isempty(negPeakChanFile)
                    [nChUsed, ~] = OverwriteChannel(SubjName, negPeakChanFile, userDir);
                    disp(['   => Overwrote channels => ', num2str(nChUsed), ' matched']);
                else
                    warning('   => No channel file found => skipping OverwriteChannel.');
                end
            end

            % (D) Compute noise cov for this night => condition=[NightName,'_noise']
            computeNoiseCov(SubjName, [NightName,'_noise'], [0,84]);
            disp(['   => Noise cov computed => ', noiseEEGFile]);

            % (E) Head-model computed once per subject or per night. We'll do once per subject if not done.
            if ~didHeadModel
                computeHeadModel(SubjName, [NightName, '_NegPeak']);
                disp(['   => Head-model computed (once) for condition=', NightName,'_NegPeak']);
                didHeadModel = true;
            end

            % (F) Now run sLORETA for condition=[NightName,'_NegPeak']
            runSLORETA(SubjName, [NightName,'_NegPeak']);
            disp(['(Night) sLORETA done for subject=', SubjName, ' night=', NightName]);

            % (G) Save screenshots and export CSV for sLORETA results
            % Move to the final SourceRecon folder from the first night
            oldDir = pwd;
            try
                cd(sourceReconDir);

                baseName = [SubjName,'_',NightName];  % For screenshot naming, e.g. "Subject_001_Night1"
                % Screenshot channels + noise
                screenshotChannels3D_SubjCond(SubjName, [NightName,'_NegPeak'], baseName);
                screenshotAllNoiseCov(SubjName, [NightName,'_NegPeak'], 'EEG', baseName);

                % Retrieve sLORETA results for [NightName,'_NegPeak']
                sResults = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                    'subjectname',   SubjName, ...
                    'condition',     [NightName,'_NegPeak'], ...
                    'tag',           'sLORETA', ...
                    'includebad',    0, ...
                    'outprocesstab', 'process1');

                % Create a mapping from result files to their corresponding data files
                resDataMap = containers.Map();
                for iRes = 1:numel(sResults)
                    thisResFile = sResults(iRes).FileName;
                    % Get the DataFile that this result is based on
                    resInfo = in_bst_results(thisResFile, 0);
                    if ~isempty(resInfo) && isfield(resInfo, 'DataFile') && ~isempty(resInfo.DataFile)
                        resDataMap(thisResFile) = resInfo.DataFile;
                    end
                end
                
                for iRes = 1:numel(sResults)
                    thisResFile = sResults(iRes).FileName;
                    [~,resBase,~] = fileparts(thisResFile);
                    
                    % Find original wave name for this result
                    originalWaveName = '';
                    if isKey(resDataMap, thisResFile)
                        dataFile = resDataMap(thisResFile);
                        % Find the original wave name from our mapping
                        if isKey(waveFileMap, dataFile)
                            originalWaveName = waveFileMap(dataFile);
                        end
                    end
                    
                    % If we found the original wave name, use it in the output filenames
                    if ~isempty(originalWaveName)
                        % CSV => originalWaveName_scouts.csv
                        outCsv = [originalWaveName, '_scouts.csv'];
                        scoutExportCSV_specificResult(thisResFile, outCsv);
                        disp(['(Night) CSV => ', outCsv, ' (from wave: ', originalWaveName, ')']);

                        % Screenshot => originalWaveName_Source.png
                        wavePNG = [originalWaveName, '_Source.png'];
                        screenshotSourceColormap_specificResult(thisResFile, wavePNG);
                        disp(['(Night) Screenshot => ', wavePNG, ' (from wave: ', originalWaveName, ')']);
                    else
                        % Fallback to the original naming if mapping fails
                        outCsv = [resBase, '_scouts.csv'];
                        scoutExportCSV_specificResult(thisResFile, outCsv);
                        disp(['(Night) CSV => ', outCsv, ' (no wave mapping found)']);

                        wavePNG = [resBase, '_Source.png'];
                        screenshotSourceColormap_specificResult(thisResFile, wavePNG);
                        disp(['(Night) Screenshot => ', wavePNG, ' (no wave mapping found)']);
                    end
                end
                disp(['(Night) Done wave-labeled CSV + PNG exports => ', NightName]);

            catch ME
                warning('Could not do final wave-labeled exports for night=%s: %s', NightName, ME.message);
            end
            cd(oldDir);

            disp(['DONE with subject=', SubjName, ' night=', NightName,'-------------------------------']);
        end
    end

    % 4) Stop diary => move .txt to the last SourceRecon used
    diary off;
    if exist('sourceReconDir','var') && exist(logName,'file')
        try
            movefile(logName, fullfile(sourceReconDir, logName));
            disp(['Log file saved => ', fullfile(sourceReconDir, logName)]);
        catch
            disp(['Log file saved => ', logName]);
        end
    end
end
