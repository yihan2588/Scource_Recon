%function to write EEGLAB format channel (editted template channel) to import back to Brainstorm
function write_xyz_from_chanlocs(ChanLocs, outFile)
% WRITE_XYZ_WITH_INDEX
% Writes lines in the format:
%   <LineIndex>  <X>  <Y>  <Z>  <Label>
% with 3 decimals for the coordinates.

    fid = fopen(outFile, 'w');
    if fid == -1
        error('Could not open file for writing: %s', outFile);
    end

    for iC = 1:numel(ChanLocs)
        % Row index: iC
        % Coordinates: ChanLocs(iC).X, .Y, .Z
        % Label: ChanLocs(iC).labels
        fprintf(fid, '%d\t%.3f\t%.3f\t%.3f\t%s\n', ...
            iC, ...
            ChanLocs(iC).X, ...
            ChanLocs(iC).Y, ...
            ChanLocs(iC).Z, ...
            ChanLocs(iC).labels);
    end

    fclose(fid);
end
