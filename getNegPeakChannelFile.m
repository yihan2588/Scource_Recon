function negPeakChanFile = getNegPeakChannelFile(SubjectName, ConditionName)
% find the last data file in that condition with a valid .ChannelFile
    negPeakChanFile = '';
    sFiles = bst_process('CallProcess', 'process_select_files_data', [], [], ...
        'subjectname',   SubjectName, ...
        'condition',     ConditionName, ...
        'tag',           '', ...
        'includebad',    0, ...
        'includeintra',  0, ...
        'includecommon', 0, ...
        'outprocesstab', 'no');

    for i = numel(sFiles):-1:1
        if isfield(sFiles(i), 'ChannelFile') && ~isempty(sFiles(i).ChannelFile)
            negPeakChanFile = sFiles(i).ChannelFile;
            break;
        end
    end
end
