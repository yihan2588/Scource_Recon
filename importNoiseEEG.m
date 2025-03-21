function importNoiseEEG(SubjectName, NoiseEEGFile, NightNoiseCond, NoiseTime)
% Import noise EEG file => condition = <NightName>_noise
% If NightNoiseCond = 'Night1_noise', pass that in from main
% e.g. importNoiseEEG('Subject_001', '/path/noise_eeg_data.set', 'Night1_noise', [0,84])

    if nargin<4
        NoiseTime = [0,84];
    end

    if isempty(NoiseEEGFile) || ~exist(NoiseEEGFile,'file')
        warning('NoiseEEG file not found: %s', NoiseEEGFile);
        return;
    end

    bst_report('Start', []);
    bst_process('CallProcess', 'process_import_data_time', [], [], ...
        'subjectname',   SubjectName, ...
        'condition',     NightNoiseCond, ...
        'datafile',      {{NoiseEEGFile}, 'EEG-EEGLAB'}, ...
        'channelreplace',1, ...  % Ensure stable channel file
        'channelalign',  0, ...
        'timewindow',    NoiseTime, ...
        'split',         0, ...
        'ignoreshort',   0, ...
        'usectfcomp',    0, ...
        'usessp',        0, ...
        'freq',          [], ...
        'baseline',      [], ...
        'blsensortypes', 'EEG');
    bst_report('Save', []);
end
