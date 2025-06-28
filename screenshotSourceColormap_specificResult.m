%take graphic validation of sLORETA source file
function screenshotSourceColormap_specificResult(resultFile, outPng, DataThreshold)
% SCREENSHOTSOURCECOLORMAP_SPECIFICRESULT
%   Opens the specified source result file with a colormap,
%   applies a data threshold, saves the figure to outPng, then closes the figure.
    if nargin < 3 || isempty(DataThreshold)
        DataThreshold = 0.3; % Default threshold
    end

    hFig = figure('Visible', 'off');
    view_surface_data(hFig, resultFile, 'EEG');
    if ~isempty(hFig)
        % Set surface threshold
        panel_surface('SetDataThreshold', hFig, 1, DataThreshold);
        saveas(hFig, outPng);
        close(hFig);
    end
end
