% screenshot noise cov matrix
function screenshotAllNoiseCov(SubjectName, ConditionName, Modality, baseName)
    [sStudies, ~] = bst_get('StudyWithCondition', [SubjectName '/' ConditionName]);
    if isempty(sStudies) || isempty(sStudies(end).NoiseCov)
        disp('No noise covariance found for screenshot.');
        return;
    end
    sStudy = sStudies(end);
    for iCov = 1:numel(sStudy.NoiseCov)
        NoiseCovFile = sStudy.NoiseCov(iCov).FileName;
        hFig = view_noisecov(NoiseCovFile, Modality);
        
        % e.g. "Subject_001_AllWaves_NoiseCov1.png"
        outName = sprintf('%s_NoiseCov%d.png', baseName, iCov);
        saveas(hFig, outName);
        close(hFig);
    end
end