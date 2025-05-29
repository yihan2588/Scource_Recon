function [nImported, importedFiles] = importMainEEG(SubjectName, MainEEGFile, ConditionName, EpochTime)
% Import slow-wave EEG => condition = ConditionName.
% EventName = "NegPeak" is used for epoching, but 'createcond'=0 so we keep our condition name.
%
% OUTPUTS:
%   nImported    : Number of imported files
%   importedFiles: Cell array of imported file paths (for mapping to original wave files)

    if nargin<4
        EpochTime = [-0.05, 0.05];
    end

    if isempty(MainEEGFile) || ~exist(MainEEGFile,'file')
        warning('MainEEG file not found: %s', MainEEGFile);
        nImported=0;
        importedFiles = {};
        return;
    end

    bst_report('Start', []);
    sFiles = bst_process('CallProcess', 'process_import_data_event', [], [], ...
        'subjectname',  SubjectName, ...
        'condition',    ConditionName, ...
        'datafile',     {{MainEEGFile}, 'EEG-EEGLAB'}, ...
        'eventname',    'NegPeak', ...
        'timewindow',   [], ...
        'epochtime',    EpochTime, ...
        'createcond',   0, ...   % do NOT override with event name
        'ignoreshort',  0, ...
        'channelreplace', 1, ... % stable channel references
        'channelalign', 0, ...
        'usectfcomp',   0, ...
        'usessp',       0, ...
        'freq',         [], ...
        'baseline',     [], ...
        'blsensortypes','EEG');
    bst_report('Save', sFiles);

    nImported = numel(sFiles);
    
    % Extract the file paths for mapping to original wave files
    importedFiles = {};
    if nImported > 0
        for i = 1:numel(sFiles)
            importedFiles{i} = sFiles(i).FileName;
        end
    end
end
