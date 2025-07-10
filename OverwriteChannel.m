function [nChUsed, xyzChanFile] = OverwriteChannel(SubjectName, ConditionName, ThisChanFile, strengthenDir)
% Overwrite BST channel coords with a template .xyz
%
% INPUTS:
%   SubjectName   : The subject name in Brainstorm
%   ConditionName : The specific condition to apply the new channel file to
%   ThisChanFile  : The relative Brainstorm channel file path
%   strengthenDir : The top-level STRENGTHEN folder (for "Assets/256_net_temp.xyz")
%
% OUTPUTS:
%   nChUsed       : Number of matched channels
%   xyzChanFile   : The newly created _reduced.xyz file

    %% 1) Convert BST path -> absolute OS path
    FullChanPath = file_fullpath(ThisChanFile);
    if isempty(FullChanPath) || ~exist(FullChanPath, 'file')
        error('Could not resolve or find path for: %s', ThisChanFile);
    end
    fprintf('\n[DEBUG] Real OS path:\n  %s\n', FullChanPath);

    %% Load the channel file
    ChannelMat = in_bst_channel(FullChanPath);
    oldChannels = ChannelMat.Channel;

    % Rename E1->E001, E2->E002, etc.
    for iC = 1:numel(oldChannels)
        rawBST = oldChannels(iC).Name;
        if startsWith(rawBST, 'E')
            val = str2double(rawBST(2:end));
            oldChannels(iC).Name = sprintf('E%03d', val);
        end
    end
    oldNames = {oldChannels.Name};

    %% 2) Load & filter the template .xyz from "Assets/256_net_temp.xyz"
    templateXYZ = fullfile(strengthenDir, 'Assets', '256_net_temp.xyz');
    if ~exist(templateXYZ,'file')
        error('Template .xyz file not found: %s', templateXYZ);
    end
    TemplateAll = read_xyz_as_chanlocs(templateXYZ);

    % Build the "clean" array with zero-padded labels
    TemplateClean = TemplateAll([]);
    for iT = 1:numel(TemplateAll)
        rawLabel = TemplateAll(iT).labels;
        if ~startsWith(rawLabel, 'E')
            continue;
        end
        val = str2double(rawLabel(2:end));
        paddedLabel = sprintf('E%03d', val);

        newStruct = TemplateAll(iT);
        newStruct.labels = paddedLabel;
        TemplateClean(end+1) = newStruct; %#ok<AGROW>
    end

    templateNames = {TemplateClean.labels};

    %% 3) Match & Overwrite Coordinates
    keepMask = ismember(oldNames, templateNames);
    matchedChannels = oldChannels(keepMask);
    nChUsed = sum(keepMask);

    for iM = 1:numel(matchedChannels)
        labelBST = matchedChannels(iM).Name;
        idxT = find(strcmp(labelBST, templateNames), 1);
        if ~isempty(idxT)
            matchedChannels(iM).Loc = [
                TemplateClean(idxT).X;
                TemplateClean(idxT).Y;
                TemplateClean(idxT).Z
            ];
        end
    end

    %% 4) Write the final .xyz in same folder
    ChanXYZ(numel(matchedChannels)) = struct('labels','','X',0,'Y',0,'Z',0);
    for iM = 1:numel(matchedChannels)
        ChanXYZ(iM).labels = matchedChannels(iM).Name;
        ChanXYZ(iM).X      = matchedChannels(iM).Loc(1);
        ChanXYZ(iM).Y      = matchedChannels(iM).Loc(2);
        ChanXYZ(iM).Z      = matchedChannels(iM).Loc(3);
    end

    [chanDir, chanBase] = fileparts(FullChanPath);
    xyzChanFile = fullfile(chanDir, [chanBase, '_reduced.xyz']);
    write_xyz_from_chanlocs(ChanXYZ, xyzChanFile);

    %% 5) Re-import the _reduced.xyz into Brainstorm
    bst_report('Start', []);
    % Select data files ONLY from the specified condition
    sFiles = bst_process('CallProcess', 'process_select_files_data', [], [], ...
        'subjectname', SubjectName, ...
        'condition',   ConditionName, ...
        'tag',         '', ...
        'includebad',  0, ...
        'includeintra',0, ...
        'includecommon',0, ...
        'outprocesstab','no');

    % Import the new channel file and link it to the selected data files
    sFiles_new = bst_process('CallProcess', 'process_import_channel', sFiles, [], ...
        'channelfile',  {xyzChanFile, 'EEGLAB'}, ...
        'usedefault',   '', ...
        'channelalign', 1, ...
        'fixunits',     1, ...
        'vox2ras',      0);
    bst_report('Save', sFiles_new);

    % After import, the link to the *new* channel.mat is in the updated sFiles structure.
    % We return the path to this new channel file.
    if ~isempty(sFiles_new) && isfield(sFiles_new(1), 'ChannelFile') && ~isempty(sFiles_new(1).ChannelFile)
        xyzChanFile = sFiles_new(1).ChannelFile; % This is now the relative path to the new channel.mat
    else
        warning('Could not get the new channel file path after import. Subsequent steps may fail.');
        xyzChanFile = ''; % Return empty if failed
    end
end
