function project_electrodes_to_scalp(SubjectName, ConditionName, addLog)
% PROJECT_ELECTRODES_TO_SCALP: Wrapper to project channels onto the scalp surface.
%
% INPUTS:
%   SubjectName   : The subject name in Brainstorm
%   ConditionName : The condition name (e.g., 'Night1_post-stim')
%   addLog        : Handle to the logging function

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
    [sStudy, iStudy] = bst_get('StudyWithCondition', [SubjectName, '/', ConditionName]);
    if isempty(sStudy)
        addLog(sprintf('ERROR: Could not find study for condition %s.', ConditionName));
        return;
    end
    
    % Find the channel file for the first data file in the study
    % (assuming all data files in a condition share the same channel file)
    if ~isfield(sStudy, 'Data') || isempty(sStudy.Data)
        addLog(sprintf('ERROR: No data files found in condition %s to get channel file from.', ConditionName));
        return;
    end
    
    channelFilePath = sStudy.Data(1).ChannelFile;
    channelFullPath = file_fullpath(channelFilePath);
    if ~exist(channelFullPath, 'file')
        addLog(sprintf('ERROR: Channel file not found at %s.', channelFullPath));
        return;
    end
    
    % Load the channel data
    ChannelMat = in_bst_channel(channelFullPath);
    ChanLoc = ChannelMat.Channel;
    
    % Extract just the .Loc field for the projection function
    InitialChanLoc = vertcat(ChanLoc.Loc);
    addLog(sprintf('Loaded %d channel locations.', size(InitialChanLoc, 1)));

    % --- 3. Call the Projection Function ---
    ProjectedChanLoc = channel_project_scalp(Vertices, InitialChanLoc);
    addLog('Completed projection of electrodes onto scalp surface.');

    % --- 4. Update the ChannelMat Structure ---
    for iChan = 1:length(ChanLoc)
        ChanLoc(iChan).Loc = ProjectedChanLoc(iChan, :);
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
