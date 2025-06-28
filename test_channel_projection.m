function test_channel_projection()
% TEST_CHANNEL_PROJECTION - Test script to verify channel file handling and projection fixes
%
% This script tests the fixed channel projection functionality on an existing
% Brainstorm protocol. Run this from the MATLAB command line after ensuring
% Brainstorm is running and a protocol is loaded.
%
% Usage:
%   test_channel_projection()

    fprintf('\n=== Channel Projection Test Script ===\n');
    
    % Check if Brainstorm is running
    if ~brainstorm('status')
        error('Brainstorm is not running. Please start Brainstorm first.');
    end
    
    % Get current protocol
    ProtocolInfo = bst_get('ProtocolInfo');
    if isempty(ProtocolInfo)
        error('No protocol is currently loaded. Please load a protocol first.');
    end
    fprintf('Current protocol: %s\n', ProtocolInfo.Comment);
    
    % Get list of subjects
    ProtocolSubjects = bst_get('ProtocolSubjects');
    if isempty(ProtocolSubjects.Subject)
        error('No subjects found in the current protocol.');
    end
    
    % Display available subjects
    fprintf('\nAvailable subjects:\n');
    for i = 1:length(ProtocolSubjects.Subject)
        fprintf('%d: %s\n', i, ProtocolSubjects.Subject(i).Name);
    end
    
    % Let user select a subject
    subjectIdx = input('\nSelect subject number to test: ');
    if subjectIdx < 1 || subjectIdx > length(ProtocolSubjects.Subject)
        error('Invalid subject selection.');
    end
    
    SubjectName = ProtocolSubjects.Subject(subjectIdx).Name;
    fprintf('Selected subject: %s\n', SubjectName);
    
    % Get studies for this subject - try different methods
    fprintf('\nSearching for studies...\n');
    [sStudies, iStudies] = bst_get('StudyWithSubject', SubjectName);
    
    % If that didn't work, try getting all studies and filtering
    if isempty(sStudies)
        fprintf('First method failed, trying alternative approach...\n');
        % Get all studies
        ProtocolInfo = bst_get('ProtocolInfo');
        allStudies = bst_get('ProtocolStudies');
        
        fprintf('Total studies in protocol: %d\n', length(allStudies.Study));
        
        % Debug: Show all study info
        fprintf('\nDebugging - All studies:\n');
        for i = 1:min(5, length(allStudies.Study))  % Show first 5 studies
            fprintf('Study %d:\n', i);
            if ~isempty(allStudies.Study(i).BrainStormSubject)
                fprintf('  BrainStormSubject: %s\n', allStudies.Study(i).BrainStormSubject);
            end
            if ~isempty(allStudies.Study(i).Condition)
                if iscell(allStudies.Study(i).Condition)
                    fprintf('  Condition: %s\n', allStudies.Study(i).Condition{1});
                else
                    fprintf('  Condition: %s\n', allStudies.Study(i).Condition);
                end
            end
            if ~isempty(allStudies.Study(i).Name)
                fprintf('  Name: %s\n', allStudies.Study(i).Name);
            end
        end
        
        % Filter for this subject
        sStudies = struct([]);  % Initialize as empty struct array
        iStudies = [];
        for i = 1:length(allStudies.Study)
            if ~isempty(allStudies.Study(i).BrainStormSubject) && ...
               contains(allStudies.Study(i).BrainStormSubject, SubjectName)
                if isempty(sStudies)
                    sStudies = allStudies.Study(i);
                else
                    sStudies(end+1) = allStudies.Study(i);
                end
                iStudies(end+1) = i;
            end
        end
    end
    
    if isempty(sStudies)
        % Try one more method - look for conditions containing the subject name
        fprintf('Second method failed, trying condition-based search...\n');
        allStudies = bst_get('ProtocolStudies');
        sStudies = struct([]);  % Initialize as empty struct array
        iStudies = [];
        for i = 1:length(allStudies.Study)
            if ~isempty(allStudies.Study(i).Condition)
                % Handle cell array condition
                if iscell(allStudies.Study(i).Condition)
                    condName = allStudies.Study(i).Condition{1};
                else
                    condName = allStudies.Study(i).Condition;
                end
                
                if contains(condName, SubjectName)
                    if isempty(sStudies)
                        sStudies = allStudies.Study(i);
                    else
                        sStudies(end+1) = allStudies.Study(i);
                    end
                    iStudies(end+1) = i;
                end
            end
        end
    end
    
    if isempty(sStudies)
        error('No studies found for subject %s. Make sure data has been imported for this subject.', SubjectName);
    end
    
    fprintf('Found %d studies for subject %s\n', length(sStudies), SubjectName);
    
    % Display available conditions
    fprintf('\nAvailable conditions:\n');
    conditions = {};
    conditionIndices = [];
    for i = 1:length(sStudies)
        if ~isempty(sStudies(i).Condition)
            % Get condition name (handle cell array)
            if iscell(sStudies(i).Condition)
                condName = sStudies(i).Condition{1};
            else
                condName = sStudies(i).Condition;
            end
            
            % Check if this condition has a channel file
            hasChannel = ~isempty(sStudies(i).Channel) && isfield(sStudies(i).Channel, 'FileName');
            conditions{end+1} = condName;
            conditionIndices(end+1) = i;
            fprintf('%d: %s', length(conditions), condName);
            if hasChannel
                fprintf(' [Has channel file]');
            else
                fprintf(' [No channel file]');
            end
            fprintf('\n');
        end
    end
    
    if isempty(conditions)
        error('No conditions found for subject %s', SubjectName);
    end
    
    % Let user select a condition
    condIdx = input('\nSelect condition number to test: ');
    if condIdx < 1 || condIdx > length(conditions)
        error('Invalid condition selection.');
    end
    
    ConditionName = conditions{condIdx};
    fprintf('Selected condition: %s\n', ConditionName);
    
    % Get the study for this condition - use the one we already found
    studyIdx = conditionIndices(condIdx);
    sStudy = sStudies(studyIdx);
    iStudy = iStudies(studyIdx);
    
    % Double-check by also trying the standard method
    if isempty(sStudy)
        [sStudy, iStudy] = bst_get('StudyWithCondition', [SubjectName '/' ConditionName]);
    end
    
    if isempty(sStudy)
        error('Could not find study for %s/%s', SubjectName, ConditionName);
    end
    
    % Check if there's a channel file
    if isempty(sStudy.Channel) || isempty(sStudy.Channel.FileName)
        error('No channel file found for %s/%s', SubjectName, ConditionName);
    end
    
    channelFile = sStudy.Channel.FileName;
    fprintf('\nFound channel file: %s\n', channelFile);
    
    % Test 1: Path resolution
    fprintf('\n--- Test 1: Path Resolution ---\n');
    fprintf('Relative path: %s\n', channelFile);
    
    fullPath = file_fullpath(channelFile);
    fprintf('Full path: %s\n', fullPath);
    
    if exist(fullPath, 'file')
        fprintf('✓ File exists at full path\n');
    else
        fprintf('✗ File NOT found at full path\n');
        error('Channel file not found');
    end
    
    % Test 2: Load channel data and check dimensions
    fprintf('\n--- Test 2: Channel Data Validation ---\n');
    try
        ChannelMat = in_bst_channel(fullPath);
        fprintf('✓ Successfully loaded channel file\n');
        fprintf('Number of channels: %d\n', length(ChannelMat.Channel));
        
        % Check channel locations
        validCount = 0;
        invalidCount = 0;
        for i = 1:length(ChannelMat.Channel)
            if isfield(ChannelMat.Channel(i), 'Loc') && ~isempty(ChannelMat.Channel(i).Loc)
                locSize = size(ChannelMat.Channel(i).Loc);
                if isequal(locSize, [3, 1])
                    validCount = validCount + 1;
                else
                    invalidCount = invalidCount + 1;
                    fprintf('Channel %s has unexpected Loc dimensions: %dx%d\n', ...
                        ChannelMat.Channel(i).Name, locSize(1), locSize(2));
                end
            else
                invalidCount = invalidCount + 1;
                fprintf('Channel %s has missing or empty Loc field\n', ChannelMat.Channel(i).Name);
            end
        end
        
        fprintf('Valid channel locations: %d\n', validCount);
        fprintf('Invalid channel locations: %d\n', invalidCount);
        
    catch ME
        fprintf('✗ Error loading channel file: %s\n', ME.message);
        error('Failed to load channel data');
    end
    
    % Test 3: Test the projection function
    fprintf('\n--- Test 3: Projection Function Test ---\n');
    
    % Create a simple logging function
    testLog = @(msg) fprintf('[TEST LOG] %s\n', msg);
    
    % Ask user if they want to run the projection
    response = input('Run projection test? (y/n): ', 's');
    if strcmpi(response, 'y')
        try
            % Make a backup of the channel file first
            backupPath = [fullPath '.backup'];
            copyfile(fullPath, backupPath);
            fprintf('Created backup at: %s\n', backupPath);
            
            % Run the projection
            project_electrodes_to_scalp(SubjectName, ConditionName, channelFile, testLog);
            
            fprintf('\n✓ Projection completed successfully!\n');
            
            % Verify the results
            ChannelMatAfter = in_bst_channel(fullPath);
            fprintf('\nVerifying results:\n');
            
            % Check if locations changed
            locChanged = 0;
            for i = 1:min(length(ChannelMat.Channel), length(ChannelMatAfter.Channel))
                if isfield(ChannelMat.Channel(i), 'Loc') && isfield(ChannelMatAfter.Channel(i), 'Loc')
                    if ~isequal(ChannelMat.Channel(i).Loc, ChannelMatAfter.Channel(i).Loc)
                        locChanged = locChanged + 1;
                    end
                end
            end
            fprintf('Number of channels with modified locations: %d\n', locChanged);
            
            % Ask if user wants to restore backup
            response = input('\nRestore original channel file from backup? (y/n): ', 's');
            if strcmpi(response, 'y')
                copyfile(backupPath, fullPath);
                delete(backupPath);
                db_reload_studies(iStudy);
                fprintf('Original channel file restored.\n');
            else
                delete(backupPath);
                fprintf('Backup deleted, keeping projected channels.\n');
            end
            
        catch ME
            fprintf('\n✗ Projection failed with error:\n');
            fprintf('Error: %s\n', ME.message);
            fprintf('Stack trace:\n');
            for i = 1:length(ME.stack)
                fprintf('  In %s at line %d\n', ME.stack(i).name, ME.stack(i).line);
            end
            
            % Try to restore backup if it exists
            if exist(backupPath, 'file')
                copyfile(backupPath, fullPath);
                delete(backupPath);
                db_reload_studies(iStudy);
                fprintf('\nOriginal channel file restored from backup.\n');
            end
        end
    end
    
    fprintf('\n=== Test Complete ===\n');
end
