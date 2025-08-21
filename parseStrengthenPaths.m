function subjects = parseStrengthenPaths(WorkingDir)
% PARSESTRENGTHENPATHS  Parse multiple m2m_* => multiple subjects, nights, .set
%                       MODIFIED: Only processes proto1_ files
%
% INPUT:
%   WorkingDir : Path to your STRENGTHEN folder (e.g. "/Users/wyh/STRENGTHEN")
%
% OUTPUT (struct array "subjects" for main.m):
%   subjects(i).SubjectName  : e.g. "Subject_001"
%   subjects(i).AnatDir      : e.g. "/Users/wyh/STRENGTHEN/Structural/m2m_001"
%   subjects(i).Nights(j).NightName   : e.g. "Night1"
%   subjects(i).Nights(j).MainEEGFiles: cell array of proto1_*.set files only
%   subjects(i).Nights(j).NoiseEEGFile: single noise_eeg_data.set
%
% NOTE: This version filters to include only files starting with 'proto1_'
%       Excludes proto2_, proto3_, ..., proto10_ files

    if nargin < 1 || isempty(WorkingDir)
        WorkingDir = '/Users/wyh/0122';  % ** define your own default path (the main will prompt for input if empty)
    end

    %% 1) Find all "m2m_*" under Structural => each => one subject
    structRoot = fullfile(WorkingDir, 'Structural');
    m2mList    = dir(fullfile(structRoot, 'm2m_*'));
    if isempty(m2mList)
        error('No m2m_* folder found in %s', structRoot);
    end

    subjects = struct([]);
    sCount = 0;

    for iM2M = 1:numel(m2mList)
        % e.g. "m2m_001"
        m2mName = m2mList(iM2M).name;
        AnatDir = fullfile(m2mList(iM2M).folder, m2mName);  % "/.../Structural/m2m_001"

        % "m2m_001" -> "Subject_001"
        subjSuffix = m2mName(5:end);  % "001"
        SubjectName = ['Subject_', subjSuffix];  % "Subject_001"

        % Build the subject struct entry
        sCount = sCount + 1;
        subjects(sCount).SubjectName = SubjectName;
        subjects(sCount).AnatDir     = AnatDir;

        %% 2) In EEG_data/, find the matching subject folder
        subjGlob = fullfile(WorkingDir, 'EEG_data', ['Subject_', subjSuffix]);
        if ~exist(subjGlob, 'dir')
            warning('No EEG_data folder found for subject: %s', SubjectName);
            subjects(sCount).Nights = struct([]);
            continue;
        end

        %% 3) Find all "Night*" subfolders under that subject
        nightRoot = subjGlob;
        nightList = dir(fullfile(nightRoot, 'Night*'));

        if isempty(nightList)
            warning('No "NightX" folder found under %s', subjGlob);
            subjects(sCount).Nights = struct([]);
            continue;
        end

        nCount = 0;
        for iNight = 1:numel(nightList)
            if ~nightList(iNight).isdir
                continue; % skip non-folders
            end
            nCount = nCount + 1;
            NightName = nightList(iNight).name;  % e.g. "Night1", "Night2"
            subjects(sCount).Nights(nCount).NightName = NightName;

            % e.g. ".../Night1/Output/Slow_Wave/sw_data/*.set"
            slowWavesDir = fullfile(nightList(iNight).folder, NightName, ...
                'Output', 'Slow_Wave', 'sw_data');

            if ~exist(slowWavesDir, 'dir')
                warning('No sw_data folder: %s', slowWavesDir);
                subjects(sCount).Nights(nCount).MainEEGFiles = {};
                subjects(sCount).Nights(nCount).NoiseEEGFile = '';
                continue;
            end

            % gather all .set in sw_data
            swList = dir(fullfile(slowWavesDir, '*.set'));
            
            % Filter for proto1 files only
            proto1Mask = false(size(swList));
            for iFile = 1:numel(swList)
                proto1Mask(iFile) = startsWith(swList(iFile).name, 'proto1_');
            end
            swList_proto1 = swList(proto1Mask);
            
            % Log filtering results
            fprintf('  Found %d total .set files, %d proto1 files in %s\n', ...
                numel(swList), numel(swList_proto1), slowWavesDir);
            
            mainEEGPaths = cell(numel(swList_proto1), 1);
            for iFile = 1:numel(swList_proto1)
                mainEEGPaths{iFile} = fullfile(swList_proto1(iFile).folder, swList_proto1(iFile).name);
            end

            subjects(sCount).Nights(nCount).MainEEGFiles = mainEEGPaths;

            % find "noise_eeg_data.set" in the parent Slow_Wave folder
            slowWaveParent = fileparts(slowWavesDir); % => ".../Slow_Wave"
            noisePath = fullfile(slowWaveParent, 'noise_eeg_data.set');
            if exist(noisePath, 'file')
                subjects(sCount).Nights(nCount).NoiseEEGFile = noisePath;
            else
                warning('No noise_eeg_data.set found in %s', slowWaveParent);
                subjects(sCount).Nights(nCount).NoiseEEGFile = '';
            end
        end
    end

    %% Print validation
    disp('=== parseStrengthenPaths: Found the following subjects & nights: ===');
    for iS = 1:numel(subjects)
        fprintf('Subject: %s\n', subjects(iS).SubjectName);
        fprintf('  AnatDir: %s\n', subjects(iS).AnatDir);
        if ~isfield(subjects(iS), 'Nights') || isempty(subjects(iS).Nights)
            disp('  (No nights found)');
            continue;
        end
        for iN = 1:numel(subjects(iS).Nights)
            Ninfo = subjects(iS).Nights(iN);
            fprintf('  -> %s: %d slow-wave .set files\n', ...
                Ninfo.NightName, numel(Ninfo.MainEEGFiles));
            fprintf('     noise = %s\n', Ninfo.NoiseEEGFile);
        end
    end
end
