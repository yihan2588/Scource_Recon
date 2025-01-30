function [nChUsed, xyzChanFile] = OverwriteChannel(SubjectName, ThisChanFile, strengthenDir)
% OVERWRITECHANNEL  Overwrites BST channel coords with a template .xyz
%
% USAGE:
%   [nChUsed, xyzChanFile] = OverwriteChannel(SubjectName, ThisChanFile, strengthenDir)
%
% INPUTS:
%   SubjectName   : The subject name in Brainstorm
%   ThisChanFile  : The relative Brainstorm channel file path (e.g. "Subject_001/NegPeak/channel.mat")
%   strengthenDir : The top-level "STRENGTHEN" working directory (e.g. "/Users/wyh/0122")
%
% OUTPUTS:
%   nChUsed       : Number of matched channels between BST and template
%   xyzChanFile   : Path to the newly created *_reduced.xyz file
%
% LOGIC:
%   1) Convert Brainstorm relative channel file => absolute OS path
%   2) Rename E1->E001, E2->E002, ...
%   3) Load your "Assets/template.xyz" => "E001..E256" => store in TemplateClean
%   4) Match & overwrite coordinates in BST channels
%   5) Write "<channel>_reduced.xyz" from template
%   6) Re-import that .xyz as 'EEGLAB' format
%
% NOTE: We added "strengthenDir" so we can reference "strengthenDir/Assets/template.xyz"
%       instead of a hardcoded absolute path.

    %% === 1) Convert BST path -> absolute OS path ===
    FullChanPath = file_fullpath(ThisChanFile);
    if isempty(FullChanPath) || ~exist(FullChanPath, 'file')
        error('Could not resolve or find path for: %s', ThisChanFile);
    end
    fprintf('\n[DEBUG] Real OS path:\n  %s\n', FullChanPath);

    %% Load the channel file from the real path
    fprintf('[DEBUG] Loading Brainstorm channel file...\n');
    ChannelMat = in_bst_channel(FullChanPath);
    oldChannels = ChannelMat.Channel;

    %% Rename E1->E001, E2->E002, etc.
    for iC = 1:numel(oldChannels)
        rawBST = oldChannels(iC).Name;
        if startsWith(rawBST, 'E')
            val = str2double(rawBST(2:end)); 
            oldChannels(iC).Name = sprintf('E%03d', val);
        end
    end
    oldNames = {oldChannels.Name};
    fprintf('  Found %d channels in BST file\n', numel(oldNames));

    %% === 2) Load & filter the template .xyz from "strengthenDir/Assets/template.xyz" ===
    templateXYZ = fullfile(strengthenDir, 'Assets', 'template.xyz');  
    fprintf('[DEBUG] Loading template file:\n  %s\n', templateXYZ);
    if ~exist(templateXYZ,'file')
        error('Template .xyz file not found: %s', templateXYZ);
    end
    TemplateAll = read_xyz_as_chanlocs(templateXYZ);
    fprintf('  Template has %d lines before cleanup.\n', numel(TemplateAll));

    % Build the "clean" array with zero-padded labels
    TemplateClean = TemplateAll([]);  % empty struct array
    for iT = 1:numel(TemplateAll)
        rawLabel = TemplateAll(iT).labels;  
        if ~startsWith(rawLabel, 'E')
            % skip lines that do not start with 'E'
            continue;
        end
        val = str2double(rawLabel(2:end)); 
        paddedLabel = sprintf('E%03d', val);

        newStruct = TemplateAll(iT);
        newStruct.labels = paddedLabel;
        TemplateClean(end+1) = newStruct; %#ok<AGROW>
    end

    templateNames = {TemplateClean.labels};
    fprintf('  After zero-padding, template has %d valid channels.\n', numel(templateNames));

    %% === 3) Match & Overwrite Coordinates ===
    keepMask = ismember(oldNames, templateNames);
    matchedChannels = oldChannels(keepMask);
    nChUsed = sum(keepMask);
    fprintf('  Matched %d channels between BST and template.\n', nChUsed);

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

    %% === 4) Write the final .xyz in the same OS folder as FullChanPath ===
    ChanXYZ(numel(matchedChannels)) = struct('labels','','X',0,'Y',0,'Z',0);
    for iM = 1:numel(matchedChannels)
        ChanXYZ(iM).labels = matchedChannels(iM).Name;
        ChanXYZ(iM).X      = matchedChannels(iM).Loc(1);
        ChanXYZ(iM).Y      = matchedChannels(iM).Loc(2);
        ChanXYZ(iM).Z      = matchedChannels(iM).Loc(3);
    end

    [chanDir, chanBase] = fileparts(FullChanPath); 
    xyzChanFile = fullfile(chanDir, [chanBase, '_reduced.xyz']);
    fprintf('\n[DEBUG] Writing final .xyz to: %s\n', xyzChanFile);

    % Attempt to write the file
    write_xyz_from_chanlocs(ChanXYZ, xyzChanFile);

    %% === 5) Re-import the _reduced.xyz into Brainstorm ===
    fprintf('\n[DEBUG] Importing %s into Brainstorm (EEGLAB format)...\n', xyzChanFile);
    bst_report('Start', []);
    % Select data files in the entire subject (all conditions)
    sFiles = bst_process('CallProcess', 'process_select_files_data', [], [], ...
        'subjectname', SubjectName, ...
        'condition',   '', ...
        'tag',         '', ...
        'includebad',  0, ...
        'includeintra',0, ...
        'includecommon',0, ...
        'outprocesstab','no');

    % Import the new .xyz
    sFiles = bst_process('CallProcess', 'process_import_channel', sFiles, [], ...
        'channelfile',  {xyzChanFile, 'EEGLAB'}, ...
        'usedefault',   '', ...
        'channelalign', 1, ...
        'fixunits',     1, ...
        'vox2ras',      0);

    bst_report('Save', sFiles);
    fprintf('[DEBUG] Done importing. Final matched channel count: %d\n', nChUsed);
end