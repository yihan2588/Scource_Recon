function set_bad_channel(SubjName, Condition, BadChannels, addLog)
% SET_BAD_CHANNEL - Marks specified channels as bad in Brainstorm.
%
%   Usage:
%       set_bad_channel(SubjName, Condition, BadChannels, addLog)
%
%   Inputs:
%       SubjName    - String, the name of the subject in Brainstorm.
%       Condition   - String, the name of the condition (e.g., 'Night1_noise').
%       BadChannels - Cell array of strings, where each string is a channel
%                     name to be marked as bad (e.g., {'E1', 'E2'}).
%       addLog      - Function handle to the logging function from main.m.

    if nargin < 4
        addLog = @(msg) disp(msg); % Default to just displaying the message
    end

    if isempty(BadChannels)
        addLog(sprintf('No bad channels specified for %s / %s. Skipping.', SubjName, Condition));
        return;
    end

    % Convert cell array of channel names to a comma-separated string
    badChannelsStr = strjoin(BadChannels, ',');

    addLog(sprintf('Setting bad channels for %s / %s: %s', SubjName, Condition, badChannelsStr));

    try
        % Get the study for the specified condition
        [sStudy, ~] = bst_get('StudyWithCondition', [SubjName '/' Condition]);
        if isempty(sStudy)
            addLog(sprintf('ERROR: Could not find study for condition: %s / %s', SubjName, Condition));
            return;
        end

        % Find the data files (EEG recordings) within this study
        sFiles = {sStudy.Data.FileName};
        if isempty(sFiles)
            addLog(sprintf('ERROR: No data files found in condition: %s / %s', SubjName, Condition));
            return;
        end

        % Call the Brainstorm process to set bad channels
        bst_process('CallProcess', 'process_channel_setbad', sFiles, [], ...
            'sensortypes', badChannelsStr, ...
            'isbad',       1);

        addLog(sprintf('Successfully set %d bad channel(s) for %d data file(s) in %s / %s.', ...
                 numel(BadChannels), numel(sFiles), SubjName, Condition));

    catch ME
        addLog(sprintf('ERROR setting bad channels for %s / %s: %s', SubjName, Condition, ME.message));
        % Optionally rethrow the error if you want the script to stop
        % rethrow(ME);
    end

end
