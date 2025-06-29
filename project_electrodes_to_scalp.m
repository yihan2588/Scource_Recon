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
    
    % Validate channel locations
    validChannels = [];
    for iChan = 1:length(ChanLoc)
        if isfield(ChanLoc(iChan), 'Loc') && ~isempty(ChanLoc(iChan).Loc) && numel(ChanLoc(iChan).Loc) == 3
            validChannels(end+1) = iChan;
        else
            addLog(sprintf('WARNING: Channel %d (%s) has invalid or missing location data.', iChan, ChanLoc(iChan).Name));
        end
    end
    
    if isempty(validChannels)
        addLog('ERROR: No valid channel locations found. Cannot proceed with projection.');
        return;
    end
    
    % Extract just the .Loc field for the projection function
    InitialChanLoc = zeros(length(validChannels), 3);
    for idx = 1:length(validChannels)
        iChan = validChannels(idx);
        loc = ChanLoc(iChan).Loc;
        % Ensure we have a row vector for the projection function
        if size(loc, 1) == 3 && size(loc, 2) == 1
            InitialChanLoc(idx, :) = loc';  % Convert column to row
        elseif size(loc, 1) == 1 && size(loc, 2) == 3
            InitialChanLoc(idx, :) = loc;   % Already a row vector
        else
            addLog(sprintf('WARNING: Unexpected dimension for channel %d location: %dx%d', iChan, size(loc, 1), size(loc, 2)));
        end
    end
    addLog(sprintf('Loaded %d valid channel locations out of %d total channels.', length(validChannels), length(ChanLoc)));

    % --- 3. Call the Projection Function ---
    ProjectedChanLoc = channel_project_scalp(Vertices, InitialChanLoc);
    addLog('Completed projection of electrodes onto scalp surface.');

    % --- 4. Update the ChannelMat Structure ---
    % Only update the valid channels that were projected
    for idx = 1:length(validChannels)
        iChan = validChannels(idx);
        % Convert row vector to column vector (Brainstorm expects 3x1 column vectors)
        if size(ProjectedChanLoc, 2) == 3
            ChanLoc(iChan).Loc = ProjectedChanLoc(idx, :)';  % Transpose to column vector
        else
            addLog(sprintf('WARNING: Unexpected dimension for channel %d projection result.', iChan));
            ChanLoc(iChan).Loc = ProjectedChanLoc(idx, :);
        end
    end
    ChannelMat.Channel = ChanLoc;

    % --- 5. Save the Updated Channel File ---
    % Overwrite the existing channel file with the new locations
    bst_save(channelFullPath, ChannelMat, 'v7');
    addLog(sprintf('Successfully saved updated channel file to: %s', channelFullPath));
    
    % --- 6. Reload the study to apply changes ---
    db_reload_studies(iStudy);
    addLog(sprintf('Reloaded study for condition %s.', ConditionName));

end
