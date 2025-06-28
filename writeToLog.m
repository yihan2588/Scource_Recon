function writeToLog(~, message) % FileID argument is no longer used
% WRITETOLOG (Reverted) - Placeholder, now using diary. Displays message only.
%
% INPUTS:
%   ~       : Ignored argument (previously fileID or logFilename).
%   message : The string message to display.

    timestampStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    logLine = sprintf('[%s] %s', timestampStr, message);

    % Print to command window
    disp(logLine);

    % File writing is now handled by MATLAB's diary function in main.m
end
