function main()
% screenshot sLORETA each wave: Single-pass sLORETA, but wave-by-wave CSV/sLORETA screenshot without duplication.
%
% LOGIC:
%   1) Gather subjects via parseStrengthenPaths().
%   2) For each subject:
%       - Import Anatomy
%       - For each Night:
%          * Import noise EEG
%          * For each .set wave => import + overwrite channels + noise cov
%            + (once) BEM + head model
%          * Record wave's base name
%       - After all waves => run sLORETA once for "NegPeak" data
%       - Then retrieve the separate sLORETA files from Brainstorm,
%         and for wave #i => export CSV + screenshot from the i-th file.
%   3) Next subject

    % 1) Optional: Start diary log 
    timestampStr = datestr(now, 'yyyy-mm-dd_HHMMSS');
    logName      = ['mainPipelineLog_' timestampStr '.txt'];
    diary(logName);

    % 2) Prompt user for STRENGTHEN path
    userDir = input('Enter the path to STRENGTHEN folder: ','s');
    if isempty(userDir)
        subjects = parseStrengthenPaths();
    else
        subjects = parseStrengthenPaths(userDir);
    end

    % 3) Loop over subjects
    for iSubj = 1:numel(subjects)
        SubjName = subjects(iSubj).SubjectName;
        AnatDir  = subjects(iSubj).AnatDir;

        importAnatomy(SubjName, AnatDir);
        disp(['1) Anatomy imported => ', SubjName]);

        if ~isfield(subjects(iSubj), 'Nights') || isempty(subjects(iSubj).Nights)
            warning('No nights for subject=%s', SubjName);
            continue;
        end

        didBEMHeadModel = false;
        waveRecords = [];

        % --- For each NIGHT
        for iN = 1:numel(subjects(iSubj).Nights)
            NightName    = subjects(iSubj).Nights(iN).NightName;
            mainEEGFiles = subjects(iSubj).Nights(iN).MainEEGFiles;
            noiseEEGFile = subjects(iSubj).Nights(iN).NoiseEEGFile;

            if isempty(mainEEGFiles)
                warning('No mainEEGFiles for %s / %s', SubjName, NightName);
                continue;
            end

            % Build SourceRecon folder
            firstMain       = mainEEGFiles{1};
            [mainEEGDir, ~] = fileparts(firstMain);
            slowWaveParent  = fileparts(mainEEGDir);
            nightOutputDir  = fileparts(slowWaveParent);
            sourceReconDir  = fullfile(nightOutputDir, 'SourceRecon');
            if ~exist(sourceReconDir, 'dir')
                mkdir(sourceReconDir);
            end

            disp('--------------------------------------------------');
            disp(['Processing Subject=', SubjName, ', Night=', NightName]);
            disp(['NoiseEEG=', noiseEEGFile]);
            disp(['SourceRecon=', sourceReconDir]);

            % (B) Import noise EEG once
            importNoiseEEG(SubjName, noiseEEGFile, [0,84]);
            disp(['(Night) Noise EEG imported => ', noiseEEGFile]);

            % For each wave .set
            for iFile = 1:numel(mainEEGFiles)
                thisMain = mainEEGFiles{iFile};
                [~, slowBase] = fileparts(thisMain);

                fprintf('Night=%s, waveFile %d/%d: %s\n', ...
                    NightName, iFile, numel(mainEEGFiles), thisMain);
                nImported = importMainEEG(SubjName, thisMain, 'NegPeak', [-0.05, 0.05]);
                disp(['   => Imported [', num2str(nImported), '] epoch(s) as "NegPeak".']);

                negPeakChanFile = getNegPeakChannelFile(SubjName, 'NegPeak');
                if ~isempty(negPeakChanFile)
                    [nChUsed, ~] = OverwriteChannel(SubjName, negPeakChanFile, userDir);
                    disp(['   => Overwrote channels => ', num2str(nChUsed), ' matched']);
                else
                    warning('   => No channel file found => skipping OverwriteChannel.');
                end

                computeNoiseCov(SubjName, [0,84]);
                disp(['   => Noise cov computed => ', noiseEEGFile]);

                if ~didBEMHeadModel
                    generateBEM(SubjName);
                    disp('   => BEM surfaces generated (once per subj)');

                    computeHeadModel(SubjName);
                    disp('   => Head-model computed (once per subj)');
                    didBEMHeadModel = true;
                end

                % Keep track of wave's base name
                waveRecords(end+1).waveName = slowBase; %#ok<AGROW>
            end
        end

        % --- If no waves, skip
        if isempty(waveRecords)
            disp(['No waves found => skip subject=', SubjName]);
            continue;
        end

        % (C) After all waves => run sLORETA once
        runSLORETA(SubjName);
        disp('6) sLORETA done for all waves');

        % (D) Wave-labeled exports
        oldDir = pwd;
        try
            % Move to the final SourceRecon folder from the first night
            firstNightEeg   = subjects(iSubj).Nights(1).MainEEGFiles{1};
            [mainEEGDir, ~] = fileparts(firstNightEeg);
            slowWaveParent  = fileparts(mainEEGDir);
            nightOutputDir  = fileparts(slowWaveParent);
            sourceReconDir  = fullfile(nightOutputDir, 'SourceRecon');
            cd(sourceReconDir);

            % Screenshot channels/noise => once
            baseName = fullfile(sourceReconDir, [SubjName, '_AllWaves']);
            screenshotChannels3D_SubjCond(SubjName, 'NegPeak', baseName);
            screenshotAllNoiseCov(SubjName, 'NegPeak', 'EEG', baseName);

            % ----------------------------------------------------------------
            % STEP: Retrieve all sLORETA results in the same order as waves
            % ----------------------------------------------------------------
            sResults = bst_process('CallProcess', 'process_select_files_results', [], [], ...
                'subjectname',   SubjName, ...
                'condition',     'NegPeak', ...
                'tag',           'sLORETA', ...
                'includebad',    0, ...
                'includeintra',  0, ...
                'includecommon', 0, ...
                'outprocesstab', 'process1');

            nRes  = numel(sResults);
            nWave = numel(waveRecords);
            if nRes < nWave
                warning('Found only %d sLORETA result(s) but %d waves. Some waves have no result.', nRes, nWave);
            end

            % Loop over waves in the same order
            for iW = 1:nWave
                waveBase = waveRecords(iW).waveName;

                if iW <= nRes
                    thisResFile = sResults(iW).FileName;  % one wave => one sLORETA
                else
                    warning('No sLORETA result # %d => skipping wave "%s"', iW, waveBase);
                    continue;
                end

                % CSV => waveBase_scouts.csv
                outCsv = fullfile(sourceReconDir, [waveBase, '_scouts.csv']);
                scoutExportCSV_specificResult(thisResFile, outCsv);
                disp(['(Wave) CSV => ', outCsv]);

                % Screenshot => waveBase_Source.png
                wavePNG = [waveBase, '_Source.png'];
                screenshotSourceColormap_specificResult(thisResFile, wavePNG);
                disp(['(Wave) Screenshot => ', wavePNG]);
            end

            disp('7) Done wave-labeled CSV + PNG exports');
        catch ME
            warning('Could not do final wave-labeled exports: %s', ME.message);
        end
        cd(oldDir);

        disp(['DONE with subject=', SubjName,'-------------------------------']);
    end

    % 4) Stop diary => move .txt to the last SourceRecon used
    diary off;
    if exist('sourceReconDir','var') && exist(logName,'file')
        movefile(logName, fullfile(sourceReconDir, logName));
        disp(['Log file saved => ', fullfile(sourceReconDir, logName)]);
    end
end
