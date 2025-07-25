function project_electrodes_to_scalp(SubjectName, ConditionName, channelFilePath, addLog)
% PROJECT_ELECTRODES_TO_SCALP: Wrapper to project channels onto the scalp surface.
%
% INPUTS:
%   SubjectName     : The subject name in Brainstorm
%   ConditionName   : The condition name (e.g., 'Night1_post-stim')
%   channelFilePath : Full path to the channel file to modify
%   addLog          : Handle to the logging function

    addLog(sprintf('--- Starting electrode projection for %s ---', ConditionName));

    % --- 1. Get Scalp Surface Vertices ---
    sSubject = bst_get('Subject', SubjectName);
    if isempty(sSubject)
        addLog(sprintf('ERROR: Could not find subject %s.', SubjectName));
        return;
    end
    
    % Find the scalp surface file path
    scalpPath = sSubject.Surface(sSubject.iScalp).FileName;
    scalpFullPath = file_fullpath(scalpPath);
    if ~exist(scalpFullPath, 'file')
        addLog(sprintf('ERROR: Scalp surface file not found for %s at %s.', SubjectName, scalpFullPath));
        return;
    end
    
    % Load the scalp surface data
    scalpSurface = in_tess_bst(scalpFullPath);
    Vertices = scalpSurface.Vertices;
    addLog(sprintf('Loaded scalp surface with %d vertices.', size(Vertices, 1)));

    % --- 2. Get Channel File for the Condition ---
    % The channel file path is now passed directly as an argument.
    [~, iStudy] = bst_get('StudyWithCondition', [SubjectName, '/', ConditionName]);
    if isempty(iStudy)
        addLog(sprintf('ERROR: Could not find study index for condition %s.', ConditionName));
        return;
    end

    channelFullPath = file_fullpath(channelFilePath);
    if ~exist(channelFullPath, 'file')
        addLog(sprintf('ERROR: Channel file not found at %s.', channelFullPath));
        return;
    end
    
    % Load the channel data
    ChannelMat = in_bst_channel(channelFullPath);
    ChanLoc = ChannelMat.Channel;
    
    % Extract coordinates with robust format handling
    % Handle both 3×1 (column) and 1×3 (row) coordinate formats
    InitialChanLoc = zeros(length(ChanLoc), 3);
    for iChan = 1:length(ChanLoc)
        loc = ChanLoc(iChan).Loc;
        if size(loc, 1) == 3 && size(loc, 2) == 1
            % Column vector (3×1) - transpose to row for processing
            InitialChanLoc(iChan, :) = loc';
        elseif size(loc, 1) == 1 && size(loc, 2) == 3
            % Row vector (1×3) - use as is
            InitialChanLoc(iChan, :) = loc;
        elseif numel(loc) == 3
            % Handle any other 3-element format
            InitialChanLoc(iChan, :) = reshape(loc, 1, 3);
        else
            addLog(sprintf('ERROR: Unexpected channel coordinate format for channel %d (%s): %dx%d', ...
                iChan, ChanLoc(iChan).Name, size(loc,1), size(loc,2)));
            return;
        end
    end
    addLog(sprintf('Loaded %d channel locations (format: %dx%d).', size(InitialChanLoc, 1), size(InitialChanLoc, 2)));

    % --- 3. Call the Projection Function ---
    ProjectedChanLoc = channel_project_scalp(Vertices, InitialChanLoc);
    addLog('Completed projection of electrodes onto scalp surface.');

    % --- 4. Update the ChannelMat Structure ---
    % Validate projected coordinates format
    addLog(sprintf('Projected coordinates format: %dx%d', size(ProjectedChanLoc, 1), size(ProjectedChanLoc, 2)));
    
    if size(ProjectedChanLoc, 1) ~= length(ChanLoc) || size(ProjectedChanLoc, 2) ~= 3
        addLog(sprintf('ERROR: Projected coordinates have unexpected dimensions: %dx%d (expected %dx3)', ...
            size(ProjectedChanLoc, 1), size(ProjectedChanLoc, 2), length(ChanLoc)));
        return;
    end
    
    % Assign projected coordinates back as column vectors (Brainstorm convention)
    for iChan = 1:length(ChanLoc)
        % Ensure coordinates are stored as 3×1 column vectors
        ChanLoc(iChan).Loc = ProjectedChanLoc(iChan, :)';
    end
    ChannelMat.Channel = ChanLoc;
    addLog(sprintf('Updated %d channel locations with projected coordinates.', length(ChanLoc)));

    % --- 5. Save the Updated Channel File ---
    % Overwrite the existing channel file with the new locations
    bst_save(channelFullPath, ChannelMat, 'v7');
    addLog(sprintf('Successfully saved updated channel file to: %s', channelFullPath));
    
    % --- 6. Reload the study to apply changes ---
    db_reload_studies(iStudy);
    addLog(sprintf('Reloaded study for condition %s.', ConditionName));

end
