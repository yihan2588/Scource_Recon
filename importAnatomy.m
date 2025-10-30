function importAnatomy(SubjectName, AnatDir)
% Import anatomy using subject-specific fiducials when available.

    % Default fallback fiducials (legacy values)
    defaultNas = [127, 213, 139];
    defaultLpa = [52, 113, 96];
    defaultRpa = [202, 113, 91];

    % Attempt to load per-subject fiducials from lookup table
    scriptDir = fileparts(mfilename('fullpath'));
    lookupPath = fullfile(scriptDir, 'fiducials_lookup.json');
    nas = defaultNas;
    lpa = defaultLpa;
    rpa = defaultRpa;

    if exist(lookupPath, 'file')
        try
            fiducialTable = jsondecode(fileread(lookupPath));
            if isstruct(fiducialTable) && isfield(fiducialTable, SubjectName)
                subjectEntry = fiducialTable.(SubjectName);
                if isfield(subjectEntry, 'NAS'), nas = double(subjectEntry.NAS(:))'; end
                if isfield(subjectEntry, 'LPA'), lpa = double(subjectEntry.LPA(:))'; end
                if isfield(subjectEntry, 'RPA'), rpa = double(subjectEntry.RPA(:))'; end
            else
                fprintf('[importAnatomy] Subject %s not found in fiducials lookup. Using defaults.\n', SubjectName);
            end
        catch ME
            fprintf('[importAnatomy] Failed to read fiducials lookup (%s). Using defaults. Error: %s\n', lookupPath, ME.message);
        end
    else
        fprintf('[importAnatomy] Fiducials lookup not found at %s. Using defaults.\n', lookupPath);
    end

    % Use process_import_anatomy with resolved fiducials
    bst_process('CallProcess', 'process_import_anatomy', [], [], ...
        'subjectname', SubjectName, ...
        'mrifile', {AnatDir, "FreeSurfer"}, ...
        'nvertices', 15000, ...
        'nas', nas, ...
        'lpa', lpa, ...
        'rpa', rpa);
end
