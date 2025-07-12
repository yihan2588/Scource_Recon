function screenshotTopoContactSheet()
    % SCREENSHOTOPOCONTACTSHEET
    %   Generates a topography contact sheet or 3D source map.
    %   This is a standalone script.

    % Ensure Brainstorm is running (in nogui mode if not already)
    if ~brainstorm('status')
        disp('Brainstorm not running. Starting in nogui mode...');
        brainstorm nogui;
        pause(5); % Give Brainstorm a moment to initialize
        disp('Brainstorm started.');
    else
        disp('Brainstorm already running.');
    end

    % --- Step 1: Choose operation type ---
    operationType = '';
    while ~ismember(operationType, {'recording', 'source'})
        operationType = lower(strtrim(input('Choose operation type (recording/source): ', 's')));
        if ~ismember(operationType, {'recording', 'source'})
            disp('Invalid input. Please enter "recording" or "source".');
        end
    end

    % --- Step 2: Get common parameters ---
    SubjectName = strtrim(input('Enter the Brainstorm Subject Name (empty for all): ', 's'));
    ConditionName = strtrim(input('Enter the Brainstorm Condition Name (empty for all): ', 's'));
    FileTag = strtrim(input('Enter tag to filter files (e.g., "sLORETA", empty for none): ', 's'));
    
    % --- Step 3: Get operation-specific parameters and select files ---
    sFiles = [];
    if strcmp(operationType, 'recording')
        % Select data files
        sFiles = bst_process('CallProcess', 'process_select_files_data', [], [], ...
            'subjectname',   SubjectName, ...
            'condition',     ConditionName, ...
            'tag',           FileTag, ...
            'includebad',    0, ...
            'includeintra',  0, ...
            'includecommon', 0, ...
            'outprocesstab', 'no');
        
        if isempty(sFiles)
            error('No data files found for the specified criteria.');
        end
        disp(['Selected data file: ', sFiles(1).FileName]);

        % Prompt for number of images
        nImages = input('Enter the number of images for the contact sheet (e.g., 11): ');
        if isempty(nImages) || ~isnumeric(nImages) || nImages <= 0 || mod(nImages, 1) ~= 0
            error('Number of images must be a positive integer.');
        end
        
        % Define contact sheet time range
        timeRange = [-0.05, 0.05]; % -50ms to 50ms

        % Prompt for output filename
        outPng = strtrim(input('Enter output PNG filename (e.g., TopoContactSheet): ', 's')); % Removed .png from example
        if isempty(outPng)
            error('Output filename cannot be empty.');
        end
        fullOutPath = fullfile(pwd, [outPng, '.png']); % Construct full path with .png extension
        
        % Create the initial topography figure
        hFig = view_topography(sFiles(1).FileName, 'EEG', '2DSensorCap');
        if isempty(hFig)
            error('Could not create topography figure.');
        end
        
        % Create contact sheet figure (pass [] for filename so CData is populated)
        hContactFig = view_contactsheet(hFig, 'time', 'fig', [], nImages, timeRange);
        
        % Get the image definition (RGB) from the figure
        img = get(findobj(hContactFig, 'Type', 'image'), 'CData');
        
        % Save image in file using out_image
        out_image(fullOutPath, img);
        disp(['Contact sheet saved to: ', fullOutPath]);

        % Close both figures
        close(hContactFig);
        close(hFig);
        
    elseif strcmp(operationType, 'source')
        % Prompt for orientation
        orientOptions = {'left', 'right', 'top', 'bottom', 'front', 'back', 'left_intern', 'right_intern'};
        disp('Available orientations: left, right, top, bottom, front, back, left_intern, right_intern');
        selectedOrient = '';
        while ~ismember(selectedOrient, orientOptions)
            selectedOrient = lower(strtrim(input('Enter desired orientation: ', 's')));
            if ~ismember(selectedOrient, orientOptions)
                disp('Invalid orientation. Please choose from the list.');
            end
        end

        % Select results files (sLORETA)
        sFiles = bst_process('CallProcess', 'process_select_files_results', [], [], ...
            'subjectname',   SubjectName, ...
            'condition',     ConditionName, ...
            'tag',           FileTag, ... % User can specify 'sLORETA' here
            'includebad',    0, ...
            'outprocesstab', 'no');
        
        if isempty(sFiles)
            error('No source results found for the specified criteria.');
        end
        disp(['Selected source file: ', sFiles(1).FileName]);

        % Prompt for number of images
        nImages = input('Enter the number of images for the contact sheet (e.g., 11): ');
        if isempty(nImages) || ~isnumeric(nImages) || nImages <= 0 || mod(nImages, 1) ~= 0
            error('Number of images must be a positive integer.');
        end

        % Define contact sheet time range
        timeRange = [-0.05, 0.05]; % -50ms to 50ms

        % Prompt for output filename
        outPng = strtrim(input('Enter output PNG filename (e.g., SourceMap): ', 's')); % Removed .png from example
        if isempty(outPng)
            error('Output filename cannot be empty.');
        end
        fullOutPath = fullfile(pwd, [outPng, '.png']); % Construct full path with .png extension

        % Display sources
        hFig = script_view_sources(sFiles(1).FileName, 'cortex');
        if isempty(hFig)
            error('Could not create source figure.');
        end

        % Set camera orientation
        figure_3d('SetStandardView', hFig, selectedOrient);
        
        % Create contact sheet figure (pass [] for filename so CData is populated)
        hContactFig = view_contactsheet(hFig, 'time', 'fig', [], nImages, timeRange);
        
        % Get the image definition (RGB) from the figure
        img = get(findobj(hContactFig, 'Type', 'image'), 'CData');
        
        % Save image in file using out_image
        out_image(fullOutPath, img);
        disp(['Source map saved to: ', fullOutPath]);

        % Close both figures
        close(hContactFig);
        close(hFig);
    end
end
