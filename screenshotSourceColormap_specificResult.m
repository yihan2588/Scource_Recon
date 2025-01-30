%take graphic validation of sLORETA source file
function screenshotSourceColormap_specificResult(resultFile, outPng)
    [hFig, ~, ~] = view_surface_data([], resultFile, 'EEG', 'NewFigure');
    if ~isempty(hFig)
        saveas(hFig, outPng);
        close(hFig);
    end
end