%Helper function to read EEGLAB format channel file (bst channel)
function ChanLocs = read_xyz_as_chanlocs(xyzFile)
%READ_XYZ_AS_CHANLOCS  Parse a 5-column .xyz file:
%   [index, X, Y, Z, Label]
%   Skip the index, read X/Y/Z as float, Label as string.

    fid = fopen(xyzFile, 'r');
    if fid == -1
        error('Could not open file: %s', xyzFile);
    end

    % Format: skip first int (%*d), then read 3 floats, then 1 string
    % Adjust Delimiter if needed (tabs vs. spaces).
    raw = textscan(fid, '%*d %f %f %f %s', ...
        'Delimiter', {'\t',' '}, ...  % be flexible with tabs/spaces
        'MultipleDelimsAsOne', true);
    fclose(fid);

    x = raw{1};
    y = raw{2};
    z = raw{3};
    labels = raw{4};  % cell array of strings

    nCh = length(labels);
    ChanLocs(nCh) = struct();
    for iC = 1:nCh
        ChanLocs(iC).X      = x(iC);
        ChanLocs(iC).Y      = y(iC);
        ChanLocs(iC).Z      = z(iC);
        ChanLocs(iC).labels = labels{iC};
    end
end
