function importNoiseEEG(SubjectName, NoiseEEGFile, NightNoiseCond)
% Import noise EEG file => condition = <NightName>_noise
% Imports the entire duration of the file.
% e.g. importNoiseEEG('Subject_001', '/path/noise_eeg_data.set', 'Night1_noise')

    if isempty(NoiseEEGFile) || ~exist(NoiseEEGFile,'file')
        warning('NoiseEEG file not found: %s. Skipping import.', NoiseEEGFile);
        return;
    end

    bst_report('Start', []);
    bst_process('CallProcess', 'process_import_data_time', [], [], ...
        'subjectname',   SubjectName, ...
        'condition',     NightNoiseCond, ...
        'datafile',      {{NoiseEEGFile}, 'EEG-EEGLAB'}, ...
        'channelreplace',1, ...  % Ensure stable channel file
        'channelalign',  0, ...  % Reverted to original value
        'timewindow',    [], ... % Import entire file duration
        'split',         0, ...
        'ignoreshort',   0, ...  % Reverted to original value
        'usectfcomp',    0, ...  % Reverted to original value
        'usessp',        0, ...  % Reverted to original value
        'freq',          [], ...
        'baseline',      [], ...
        'blsensortypes', 'EEG');
    bst_report('Save', []);
end
