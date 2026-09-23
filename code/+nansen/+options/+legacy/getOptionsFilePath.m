function filePath = getOptionsFilePath(methodName)
%getOptionsFilePath Get path to the options file of the legacy OptionsManager
%
%   filePath = nansen.options.legacy.getOptionsFilePath(methodName)
%   returns the path to the MAT file where nansen.manage.OptionsManager
%   saves options for the given method, or "" if the path can not be
%   determined (e.g. if NANSEN is not set up).

    arguments
        methodName (1,1) string
    end

    filePath = "";
    try
        folderPath = fileparts(nansen.options.Manager.getDefaultLocation(methodName));
        filePath = string(fullfile(folderPath, methodName + ".mat"));
    catch
        % Options folder is not available
    end
end
