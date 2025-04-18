function writeCumulativeLog(logFilename, messages)
% WRITECUMULATIVELOG Writes a cell array of messages to a log file, overwriting previous content.
%
% INPUTS:
%   logFilename : Full path to the log file (string).
%   messages    : Cell array of strings, where each cell is a line to write.

    % Attempt to open, write, and close the log file
    try
        fileID = fopen(logFilename, 'w'); % Open for writing (overwrite)
        if fileID == -1
            warning('Could not open log file for writing: %s.', logFilename);
        else
            % Write all messages collected so far
            for i = 1:numel(messages)
                if ~isempty(messages{i}) % Ensure message is not empty
                    fprintf(fileID, '%s\n', messages{i});
                end
            end
            fclose(fileID);
        end
    catch ME_log
        warning('Error writing cumulative log to file %s: %s.', logFilename, ME_log.message);
        % Ensure file is closed if fopen succeeded but fprintf/fclose failed
        if exist('fileID','var') && fileID ~= -1
            try
                fclose(fileID);
            catch
                % Ignore fclose error
            end
        end
    end
end
