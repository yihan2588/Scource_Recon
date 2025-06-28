% take graphic of 2D sensor cap for a specific EEG recording
function screenshotSensorCap_specificResult(dataFile, outPng)
    % SCREENSHOTSENSORCAP_SPECIFICRESULT
    %   Opens the specified EEG data file, displays its 2D sensor cap at 0ms,
    %   saves the figure to outPng, then closes the figure.
    
    [hFig, ~, ~] = view_topography(dataFile, 'EEG', '2DSensorCap');
    if ~isempty(hFig)
        set(hFig, 'Visible', 'off');
        % Set time to 0ms
        panel_time('SetCurrentTime', 0);
        saveas(hFig, outPng);
        close(hFig);
    end
end
