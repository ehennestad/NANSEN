classdef Provenance
%nansen.options.Provenance Information about the code and environment of a run
%
%   provenance = nansen.options.Provenance.capture() describes the software
%   environment in which a method is run: the version and git commit of
%   NANSEN, versions of MATLAB, toolboxes and add-ons, versions (git
%   commits) of external dependencies, and information about the computer
%   and user.
%
%   provenance = nansen.options.Provenance.capture(Name=Value, ...)
%
%   NAME-VALUE ARGUMENTS:
%       MethodName          : Name of method. If given, the path and a hash
%                             of the method's source file are included.
%       Dependencies        : Names of functions/classes from external
%                             toolboxes. The version (git commit) of the
%                             repository containing each is recorded.
%       IncludeAddons       : Include NANSEN's addons (default true)
%       IncludeToolboxes    : Include MATLAB toolboxes and add-ons (default true)
%       IncludeGitStatus    : Check if the NANSEN repository has uncommitted
%                             changes. Requires git (default true).
%
%   The information captured here answers the question: "Which code
%   produced this result?". Together with the options values it should be
%   enough to reproduce a result.
%
%   See also nansen.options.OptionsRecord

    properties (SetAccess = private)
        Timestamp (1,1) datetime = NaT("TimeZone", "UTC")
        Nansen (1,1) struct = struct()      % Version, Commit, Branch, RemoteUrl, IsDirty, Path
        Matlab (1,1) struct = struct()      % Version, Release, Toolboxes, Addons
        Dependencies struct = struct("Name", {}, "FunctionName", {}, ...
            "Path", {}, "Commit", {}, "RemoteUrl", {})   % Struct array
        Method (1,1) struct = struct()      % Name, FilePath, FileHash
        System (1,1) struct = struct()      % Computer, Hostname, User
    end

    properties (Constant, Hidden)
        FORMAT_VERSION = "1.0"
    end

    methods
        function S = toStruct(obj)
        %toStruct Convert to a struct of plain values (e.g. for saving)
            arguments
                obj (1,1) nansen.options.Provenance
            end
            S = struct();
            S.FormatVersion = obj.FORMAT_VERSION;
            S.Timestamp = nansen.options.internal.formatTimestamp(obj.Timestamp);
            S.Nansen = obj.Nansen;
            S.Matlab = obj.Matlab;
            S.Dependencies = obj.Dependencies;
            S.Method = obj.Method;
            S.System = obj.System;
        end
    end

    methods (Static)

        function obj = capture(options)
        %capture Capture provenance of the current environment
            arguments
                options.MethodName (1,1) string = ""
                options.Dependencies (1,:) string = string.empty(1, 0)
                options.IncludeAddons (1,1) logical = true
                options.IncludeToolboxes (1,1) logical = true
                options.IncludeGitStatus (1,1) logical = true
            end

            import nansen.options.Provenance

            obj = Provenance();
            obj.Timestamp = datetime("now", "TimeZone", "UTC");
            obj.Nansen = Provenance.getNansenInfo(IncludeGitStatus=options.IncludeGitStatus);
            obj.Matlab = Provenance.getMatlabInfo(IncludeToolboxes=options.IncludeToolboxes);
            obj.Dependencies = Provenance.getDependencyInfo(options.Dependencies, ...
                IncludeAddons=options.IncludeAddons);
            if options.MethodName ~= ""
                obj.Method = Provenance.getMethodInfo(options.MethodName);
            end
            obj.System = Provenance.getSystemInfo();
        end

        function obj = fromStruct(S)
        %fromStruct Create from a struct (see toStruct)
            arguments
                S (1,1) struct
            end
            obj = nansen.options.Provenance();
            if isfield(S, "Timestamp")
                obj.Timestamp = nansen.options.internal.parseTimestamp(S.Timestamp);
            end
            for name = ["Nansen", "Matlab", "Method", "System"]
                if isfield(S, name) && isstruct(S.(name)); obj.(name) = S.(name); end
            end
            if isfield(S, "Dependencies") && isstruct(S.Dependencies) && ~isempty(S.Dependencies)
                obj.Dependencies = reshape(S.Dependencies, 1, []);
            end
        end

        function info = getNansenInfo(options)
        %getNansenInfo Get version and git commit of NANSEN
            arguments
                options.IncludeGitStatus (1,1) logical = true
            end

            info = struct();
            try
                info.Version = string(nansen.version());
            catch
                info.Version = "";
            end

            rootPath = nansen.options.Provenance.getNansenRootPath();
            gitInfo = nansen.options.internal.getGitInfo(rootPath, ...
                IncludeStatus=options.IncludeGitStatus);

            info.Commit = gitInfo.Commit;
            info.Branch = gitInfo.Branch;
            info.RemoteUrl = gitInfo.RemoteUrl;
            info.IsDirty = gitInfo.IsDirty;
            info.Path = rootPath;
        end

        function info = getMatlabInfo(options)
        %getMatlabInfo Get version of MATLAB and installed toolboxes/add-ons
            arguments
                options.IncludeToolboxes (1,1) logical = true
            end

            info = struct();
            info.Version = string(version());
            info.Release = "R" + string(version("-release"));

            if options.IncludeToolboxes
                [info.Toolboxes, info.Addons] = ...
                    nansen.options.Provenance.getInstalledProducts();
            end
        end

        function [toolboxes, addons] = getInstalledProducts()
        %getInstalledProducts Get installed toolboxes and add-ons (cached)
        %
        %   The result is cached for the MATLAB session, as calling ver
        %   and installedAddons is slow.

            persistent cachedToolboxes cachedAddons

            if isempty(cachedToolboxes)
                v = ver();
                cachedToolboxes = reshape(struct("Name", {v.Name}, ...
                    "Version", {v.Version}), 1, []);

                cachedAddons = struct("Name", {}, "Version", {}, "Identifier", {});
                try
                    T = matlab.addons.installedAddons();
                    for i = 1:height(T)
                        cachedAddons(end+1) = struct("Name", T.Name(i), ...
                            "Version", T.Version(i), "Identifier", T.Identifier(i)); %#ok<AGROW>
                    end
                catch
                    % Add-on information not available
                end
            end
            toolboxes = cachedToolboxes;
            addons = cachedAddons;
        end

        function dependencies = getDependencyInfo(functionNames, options)
        %getDependencyInfo Get version info for external dependencies
        %
        %   For each function/class name, find the repository containing
        %   it and record its git commit.
            arguments
                functionNames (1,:) string = string.empty(1, 0)
                options.IncludeAddons (1,1) logical = true
            end

            names = strings(0, 2); % [Name, FunctionName]

            if options.IncludeAddons
                try
                    addonList = nansen.setup.defaults.getAddonList();
                    names = [names; [string({addonList.Name})', string({addonList.FunctionName})']];
                catch
                    % Addon list is not available
                end
            end

            names = [names; [strings(numel(functionNames), 1), functionNames']];
            [~, uniqueIdx] = unique(names(:, 2), "stable");
            names = names(uniqueIdx, :);

            dependencies = struct("Name", {}, "FunctionName", {}, "Path", {}, ...
                "Commit", {}, "RemoteUrl", {});

            for i = 1:size(names, 1)
                [name, functionName] = deal(names(i, 1), names(i, 2));

                filePath = string(which(functionName));
                if filePath == "" || startsWith(filePath, "built-in")
                    continue % Not installed
                end

                folderPath = string(fileparts(filePath));
                gitInfo = nansen.options.internal.getGitInfo(folderPath);

                if gitInfo.RepositoryPath ~= ""
                    folderPath = gitInfo.RepositoryPath;
                end
                if name == ""
                    [~, name] = fileparts(folderPath);
                end

                dependencies(end+1) = struct("Name", string(name), ...
                    "FunctionName", functionName, "Path", folderPath, ...
                    "Commit", gitInfo.Commit, "RemoteUrl", gitInfo.RemoteUrl); %#ok<AGROW>
            end
        end

        function info = getMethodInfo(methodName)
        %getMethodInfo Get path and hash of the source file of a method
        %
        %   The hash of the source file identifies the exact code even if
        %   the file has uncommitted changes.
            arguments
                methodName (1,1) string
            end

            info = struct("Name", methodName, "FilePath", "", "FileHash", "");
            filePath = string(which(methodName));

            if filePath ~= "" && isfile(filePath)
                info.FilePath = filePath;
                fid = fopen(filePath, "r");
                bytes = fread(fid, Inf, "*uint8");
                fclose(fid);
                info.FileHash = nansen.options.internal.sha256(bytes);
            end
        end

        function info = getSystemInfo()
        %getSystemInfo Get information about the computer
            info = struct();
            info.Computer = string(computer());
            info.Hostname = getHostname();
            info.User = nansen.options.internal.getCurrentUser();
        end

        function rootPath = getNansenRootPath()
        %getNansenRootPath Get root folder of the NANSEN repository

            % This file is located in <root>/code/+nansen/+options
            rootPath = string(fileparts(fileparts(fileparts(fileparts( ...
                mfilename("fullpath"))))));
        end
    end
end

function hostname = getHostname()
    hostname = string(getenv("COMPUTERNAME")); % Windows
    if hostname == ""
        hostname = string(getenv("HOSTNAME"));
    end
    if hostname == ""
        [status, output] = system("hostname");
        if status == 0
            hostname = strtrim(string(output));
        end
    end
end
