% Generate BEM surface for constructing head (forward) model
% factors (like 1922) set as default (Braistorm tutorial said do not change
% unless there is a reason to

function generateBEM(SubjectName)
bst_report('Start', []);
bst_process('CallProcess', 'process_generate_bem', [], [], ...
    'subjectname', SubjectName, ...
    'nscalp',      1922, ...
    'nouter',      1922, ...
    'ninner',      1922, ...
    'thickness',   4, ...
    'method',      'brainstorm');
bst_report('Save', []);
end