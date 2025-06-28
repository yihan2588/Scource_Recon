% take graphic of sLORETA source file on 2D spherical Mollweide projection
function screenshotSourceMollweide_specificResult(resultFile, outPng, DataThreshold)
% SCREENSHOTSOURCEMOLLWEIDE_SPECIFICRESULT
%   Opens the specified source result file with a Mollweide 2D sphere projection,
%   applies a data threshold, saves the figure to outPng, then closes the figure.
    if nargin < 3 || isempty(DataThreshold)
        DataThreshold = 0.3; % Default threshold
    end

    [hFig, ~, ~] = view_surface_sphere(resultFile, 'mollweide');
    if ~isempty(hFig)
        set(hFig, 'Visible', 'off');
        % Set surface threshold
        panel_surface('SetDataThreshold', hFig, 1, DataThreshold);
        saveas(hFig, outPng);
        close(hFig);
    end
end
