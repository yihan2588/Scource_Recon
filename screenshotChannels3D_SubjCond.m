function screenshotChannels3D_SubjCond(SubjectName, ConditionName, baseName)
% SCREENSHOTCHANNELS3D_SUBJCOND  3D sensors snapshot
    [sStudies, ~] = bst_get('StudyWithCondition', [SubjectName '/' ConditionName]);
    if isempty(sStudies) || isempty(sStudies(end).Channel)
        disp('No channel file found for channels 3D screenshot.');
        return;
    end
    sStudy = sStudies(end);
    ChannelFile = sStudy.Channel.FileName;
    [hFig, ~, ~] = view_channels_3d({ChannelFile}, 'EEG', 'scalp', 1, 0, []);
    set(hFig, 'Visible', 'off');
    
    % e.g. "Subject_001_Night1_Channels3D.png"
    outName = sprintf('%s_Channels3D.png', baseName);
    saveas(hFig, outName);
    close(hFig);
end
