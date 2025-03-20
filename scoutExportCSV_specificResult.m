function scoutExportCSV_specificResult(resultFile, outCsv)
% extract time matrix of sLORETA source map
% Use DKT atlas, csv saving format = ASCII-CSV-HDR

    sThis = bst_process('CallProcess', 'process_extract_scout', ...
        {resultFile}, [], ...
        'timewindow',    [-0.05, 0.05], ...
        'scouts',        {'DKT', {...   % list of DKT scouts ...
                       'caudalanteriorcingulate L','caudalanteriorcingulate R','caudalmiddlefrontal L','caudalmiddlefrontal R','cuneus L','cuneus R','entorhinal L','entorhinal R','fusiform L','fusiform R','inferiorparietal L','inferiorparietal R','inferiortemporal L','inferiortemporal R','insula L','insula R','isthmuscingulate L','isthmuscingulate R','lateraloccipital L','lateraloccipital R','lateralorbitofrontal L','lateralorbitofrontal R','lingual L','lingual R','medialorbitofrontal L','medialorbitofrontal R','middletemporal L','middletemporal R','paracentral L','paracentral R','parahippocampal L','parahippocampal R','parsopercularis L','parsopercularis R','parsorbitalis L','parsorbitalis R','parstriangularis L','parstriangularis R','pericalcarine L','pericalcarine R','postcentral L','postcentral R','posteriorcingulate L','posteriorcingulate R','precentral L','precentral R','precuneus L','precuneus R','rostralanteriorcingulate L','rostralanteriorcingulate R','rostralmiddlefrontal L','rostralmiddlefrontal R','superiorfrontal L','superiorfrontal R','superiorparietal L','superiorparietal R','superiortemporal L','superiortemporal R','supramarginal L','supramarginal R','transversetemporal L','transversetemporal R'}}, ...
        'flatten',       0, ...
        'scoutfunc',     'all', ...
        'pcaedit',       struct('Method','pca','Baseline',[-0.1,0],'DataTimeWindow',[0,1],'RemoveDcOffset','file'), ...
        'isflip',        0, ...
        'isnorm',        0, ...
        'concatenate',   0, ...
        'save',          1, ...
        'addrowcomment', 1, ...
        'addfilecomment',[]);
    bst_report('Save', sThis);

    bst_process('CallProcess', 'process_export_file', sThis, [], ...
        'exportmatrix',  {outCsv, 'ASCII-CSV-HDR'});
end
