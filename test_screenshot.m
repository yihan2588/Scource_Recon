function test_screenshot()
    % TEST_SCREENSHOT  Test the screenshotSourceColormap_specificResult function
    %
    % USAGE:
    %   1. Open MATLAB
    %   2. Navigate to the Source_Recon directory
    %   3. Run this script: test_screenshot
    %   4. When prompted, provide the full path to a sLORETA result file.
    %      (e.g., /Users/wyh/brainstorm_db/MyProtocol/data/Subject_01/Night1_post-stim/results_sLORETA_....mat)

    % Add current directory to path
    addpath(pwd);

    % --- User Input ---
    resultFile = '';
    while isempty(resultFile) || ~exist(resultFile, 'file')
        resultFile = input('Enter the full path to a Brainstorm result file (.mat): ', 's');
        if ~exist(resultFile, 'file')
            disp('File not found. Please provide a valid path.');
            resultFile = '';
        end
    end

    % --- Test Parameters ---
    outputPng = fullfile(pwd, 'test_screenshot.png');
    dataThreshold = 0.4; % Use a slightly different threshold for testing

    fprintf('\n--- Running Test ---\n');
    fprintf('Input Result File: %s\n', resultFile);
    fprintf('Output PNG File:   %s\n', outputPng);
    fprintf('Data Threshold:    %.2f\n', dataThreshold);

    % --- Execute the function ---
    try
        screenshotSourceColormap_specificResult(resultFile, outputPng, dataThreshold);
        
        if exist(outputPng, 'file')
            fprintf('\n[SUCCESS] Test completed. Screenshot saved to:\n%s\n', outputPng);
            % Try to open the image
            try
                if ispc
                    winopen(outputPng);
                elseif ismac
                    system(['open "', outputPng, '"']);
                else
                    disp('Could not automatically open the image. Please open it manually.');
                end
            catch ME_open
                fprintf('Could not automatically open the image: %s\n', ME_open.message);
            end
        else
            fprintf('\n[FAILURE] Screenshot function ran, but the output file was not created.\n');
        end
        
    catch ME
        fprintf('\n[ERROR] An error occurred while running the screenshot function:\n');
        fprintf('%s\n', ME.message);
    end
end
