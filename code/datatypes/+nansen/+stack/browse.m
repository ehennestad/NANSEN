function pathStr = browse()

    pathStr = [];

    [fileName, folderPath, ~] = uigetfile(...
        {'*', 'All Files (*.*)'; ...
         '*.tif', 'Tiff Files (*.tif)'; ...
         '*.tiff', 'Tiff Files (*.tiff)'; ...
         '*.avi', 'Avi Files (*.avi)' ...
        }, ...
        'Find Stack', '', 'MultiSelect', 'on');

    if isequal(fileName, 0); return; end

    pathStr = fullfile(folderPath, fileName);

end                                    

    