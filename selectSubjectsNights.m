function [selectedSubjects, selectedNights] = selectSubjectsNights(subjects)
% SELECTSUBJECTSNIGHTS  Allow user to select which subjects and nights to process
%
% INPUT:
%   subjects : Array of subject structures from parseStrengthenPaths()
%
% OUTPUT:
%   selectedSubjects : Array of indices of selected subjects
%   selectedNights   : Array of indices of selected nights for each subject
%                      (cell array, one cell per subject)
%
% USAGE:
%   This function displays a list of available subjects and nights,
%   and prompts the user to select which ones to process.
%   The user can enter comma-separated indices (e.g., "1,3,5") or "all".

    % Initialize outputs
    selectedSubjects = [];
    selectedNights = cell(1, numel(subjects));
    
    % Display available subjects
    fprintf('\n=== Available Subjects ===\n');
    for i = 1:numel(subjects)
        fprintf('%d: %s\n', i, subjects(i).SubjectName);
    end
    
    % Prompt user to select subjects
    subjectInput = input('Enter subject indices to process (comma-separated, e.g., "1,3,5") or "all": ', 's');
    
    % Parse subject selection
    if strcmpi(subjectInput, 'all')
        selectedSubjects = 1:numel(subjects);
    else
        % Split by comma and convert to numbers
        subjectIndices = strsplit(subjectInput, ',');
        for i = 1:numel(subjectIndices)
            idx = str2double(strtrim(subjectIndices{i}));
            if ~isnan(idx) && idx >= 1 && idx <= numel(subjects)
                selectedSubjects = [selectedSubjects, idx];
            else
                warning('Invalid subject index: %s. Skipping.', subjectIndices{i});
            end
        end
    end
    
    % If no valid subjects selected, return empty
    if isempty(selectedSubjects)
        warning('No valid subjects selected. Exiting.');
        return;
    end
    
    % For each selected subject, prompt for nights
    for subIdx = 1:numel(selectedSubjects)
        subjectIndex = selectedSubjects(subIdx);
        subject = subjects(subjectIndex);
        
        % Check if subject has nights
        if ~isfield(subject, 'Nights') || isempty(subject.Nights)
            warning('Subject %s has no nights. Skipping.', subject.SubjectName);
            continue;
        end
        
        % Display available nights for this subject
        fprintf('\n=== Available Nights for %s ===\n', subject.SubjectName);
        for i = 1:numel(subject.Nights)
            fprintf('%d: %s\n', i, subject.Nights(i).NightName);
        end
        
        % Prompt user to select nights
        nightInput = input(sprintf('Enter night indices to process for %s (comma-separated) or "all": ', subject.SubjectName), 's');
        
        % Parse night selection
        if strcmpi(nightInput, 'all')
            selectedNights{subjectIndex} = 1:numel(subject.Nights);
        else
            nightIndices = strsplit(nightInput, ',');
            for i = 1:numel(nightIndices)
                idx = str2double(strtrim(nightIndices{i}));
                if ~isnan(idx) && idx >= 1 && idx <= numel(subject.Nights)
                    selectedNights{subjectIndex} = [selectedNights{subjectIndex}, idx];
                else
                    warning('Invalid night index: %s. Skipping.', nightIndices{i});
                end
            end
        end
        
        % If no valid nights selected for this subject, warn
        if isempty(selectedNights{subjectIndex})
            warning('No valid nights selected for subject %s.', subject.SubjectName);
        end
    end
end
