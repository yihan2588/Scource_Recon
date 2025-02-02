% Compute head model
% Select file to process --> process compute head model
function computeHeadModel(SubjectName)
bst_report('Start', []);
sFiles = bst_process('CallProcess', 'process_select_files_data', [], [], ...
    'subjectname',   SubjectName, ...
    'condition',     'NegPeak', ...
    'tag',           '', ...
    'includebad',    0, ...
    'includeintra',  0, ...
    'includecommon', 0, ...
    'outprocesstab', 'process1');
bst_process('CallProcess', 'process_headmodel', sFiles, [], ...
    'Comment',      '', ...
    'sourcespace',  1, ...
    'meg',          3, ... 
    'eeg',          3, ... 
    'ecog',         2, ...
    'seeg',         2, ...
    'openmeeg', struct( ...
        'BemFiles',    {{}}, ...
        'BemNames',    {{'Scalp','Skull','Brain'}}, ...
        'BemCond',     [1,0.0125,1], ...
        'BemSelect',   [1,1,1], ...
        'isAdjoint',   0, ...
        'isAdaptative',1, ...
        'isSplit',     0, ...
        'SplitLength', 4000), ...
    'channelfile',  '');
bst_report('Save', []);
end
