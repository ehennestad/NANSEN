classdef Provenance
%nansen.options.Provenance Capture information about the code and environment
%
%   S = nansen.options.Provenance.capture() returns a struct describing
%   the software environment in which a method is run: the version and git
%   commit of NANSEN, versions of MATLAB and installed toolboxes, versions
%   (git commits) of external dependencies, and information about the
%   computer and user.
%
%   S = nansen.options.Provenance.capture(Name, Value, ...)
%
%   NAME-VALUE PAIRS:
%       MethodName          : Name of method. If given, the path and a hash
%                             of the method's source file are included.
%       Dependencies        : Cell array of function/class names from
%                             external toolboxes. The version (git commit)
%                             of the repository containing each of them
%                             is recorded (see Schema/Dependencies).
%       IncludeAddons       : Include all installed NANSEN addons (default true)
%       IncludeToolboxes    : Include MATLAB toolbox versions (default true)
%       IncludeGitStatus    : Check if the NANSEN repository has uncommitted
%                             changes. Requires git (default true).
%
%   The information captured here answers the question: "Which code
%   produced this result?". Together with the options values it should be
%   enough to reproduce a result.
%
%   See also nansen.options.OptionsRecord

    properties (Constant)
        FORMAT_VERSION = '1.0'
    end

    methods (Static)

        function S = capture(varargin)

            params = struct('MethodName', '', 'Dependencies', {{}}, ...
                'IncludeAddons', true, 'IncludeToolboxes', true, ...
                'IncludeGitStatus', true);
            for i = 1:2:numel(varargin)
                name = validatestring(char(varargin{i}), fieldnames(params));
                params.(name) = varargin{i+1};
            end

            S = struct();
            S.FormatVersion = nansen.options.Provenance.FORMAT_VERSION;
            S.Timestamp = nansen.options.internal.isoTimestamp();
            S.Nansen = nansen.options.Provenance.getNansenInfo(params.IncludeGitStatus);
            S.Matlab = nansen.options.Provenance.getMatlabInfo(params.IncludeToolboxes);

            dependencies = nansen.options.Provenance.getDependencyInfo( ...
                params.Dependencies, params.IncludeAddons);
            S.Dependencies = dependencies;

            if ~isempty(params.MethodName)
                S.Method = nansen.options.Provenance.getMethodInfo(params.MethodName);
            end

            S.System = nansen.options.Provenance.getSystemInfo();
        end

        function info = getNansenInfo(includeGitStatus)
        %getNansenInfo Get version and git commit of NANSEN
            if nargin < 1; includeGitStatus = true; end

            info = struct();
            try
                info.Version = nansen.version();
            catch
                info.Version = '';
            end

            rootPath = nansen.options.Provenance.getNansenRootPath();
            gitInfo = nansen.options.internal.getGitInfo(rootPath, includeGitStatus);

            info.Commit = gitInfo.Commit;
            info.Branch = gitInfo.Branch;
            info.RemoteUrl = gitInfo.RemoteUrl;
            info.IsDirty = gitInfo.IsDirty;
            info.Path = rootPath;
        end

        function info = getMatlabInfo(includeToolboxes)
        %getMatlabInfo Get version of MATLAB and installed toolboxes
            if nargin < 1; includeToolboxes = true; end

            info = struct();
            info.Version = version();
            try
                info.Release = ['R', version('-release')];
            catch % Octave
                info.Release = '';
            end

            if includeToolboxes
                info.Toolboxes = nansen.options.Provenance.getToolboxVersions();
            end
        end

        function toolboxes = getToolboxVersions()
        %getToolboxVersions Get names and versions of installed toolboxes
        %
        %   The result is cached, as calling ver is slow.

            persistent cachedToolboxes

            if isempty(cachedToolboxes)
                v = ver();
                cachedToolboxes = struct('Name', {v.Name}, 'Version', {v.Version});
            end
            toolboxes = cachedToolboxes;
        end

        function dependencies = getDependencyInfo(functionNames, includeAddons)
        %getDependencyInfo Get version info for external dependencies
        %
        %   For each function/class name, find the repository/toolbox
        %   containing it and record its git commit.

            if nargin < 1; functionNames = {}; end
            if nargin < 2; includeAddons = true; end
            if ischar(functionNames); functionNames = {functionNames}; end

            names = cell(1, 0);

            if includeAddons
                try
                    addonList = nansen.setup.defaults.getAddonList();
                    for i = 1:numel(addonList)
                        names{end+1} = {addonList(i).Name, addonList(i).FunctionName}; %#ok<AGROW>
                    end
                catch
                    % Addon list is not available
                end
            end

            for i = 1:numel(functionNames)
                names{end+1} = {'', functionNames{i}}; %#ok<AGROW>
            end

            dependencies = struct('Name', {}, 'FunctionName', {}, 'Path', {}, ...
                'Commit', {}, 'RemoteUrl', {});

            for i = 1:numel(names)
                [name, functionName] = deal(names{i}{:});

                if any(strcmp({dependencies.FunctionName}, functionName))
                    continue
                end

                filePath = which(functionName);
                if isempty(filePath) || strncmp(filePath, 'built-in', 8)
                    continue % Not installed
                end

                folderPath = fileparts(filePath);
                gitInfo = nansen.options.internal.getGitInfo(folderPath, false);

                if isempty(name)
                    if ~isempty(gitInfo.RepositoryPath)
                        [~, name] = fileparts(gitInfo.RepositoryPath);
                    else
                        name = functionName;
                    end
                end

                if ~isempty(gitInfo.RepositoryPath)
                    folderPath = gitInfo.RepositoryPath;
                end

                dependencies(end+1) = struct('Name', name, ...
                    'FunctionName', functionName, 'Path', folderPath, ...
                    'Commit', gitInfo.Commit, 'RemoteUrl', gitInfo.RemoteUrl); %#ok<AGROW>
            end
        end

        function info = getMethodInfo(methodName)
        %getMethodInfo Get path and hash of the source file of a method
        %
        %   The hash of the source file identifies the exact code even if
        %   the file has uncommitted changes.

            info = struct('Name', methodName, 'FilePath', '', 'FileHash', '');
            filePath = which(methodName);

            if ~isempty(filePath) && isfile(filePath)
                info.FilePath = filePath;
                fid = fopen(filePath, 'r');
                if fid ~= -1
                    bytes = fread(fid, inf, '*uint8');
                    fclose(fid);
                    info.FileHash = nansen.options.internal.sha256(bytes);
                end
            end
        end

        function info = getSystemInfo()
        %getSystemInfo Get information about the computer
            info = struct();
            info.Computer = computer();
            info.Hostname = getHostname();
            info.User = nansen.options.internal.getCurrentUser();
        end

        function rootPath = getNansenRootPath()
        %getNansenRootPath Get root folder of the NANSEN repository

            % This file is located in <root>/code/+nansen/+options
            rootPath = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        end
    end
end

function hostname = getHostname()
    hostname = getenv('COMPUTERNAME'); % Windows
    if isempty(hostname)
        hostname = getenv('HOSTNAME');
    end
    if isempty(hostname)
        try
            [status, hostname] = system('hostname');
            if status ~= 0; hostname = ''; end
            hostname = strtrim(hostname);
        catch
            hostname = '';
        end
    end
end
