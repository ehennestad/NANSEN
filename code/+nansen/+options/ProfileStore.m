classdef ProfileStore < handle
%nansen.options.ProfileStore Save and load option profiles as JSON files
%
%   Profiles for a method are stored as one JSON file per profile:
%
%       <RootFolder>/<MethodName>/<ProfileName>.json
%       <RootFolder>/<MethodName>/_settings.json   (e.g. default profile)
%
%   JSON is human readable, works well with version control (diffs show
%   exactly which values changed), and can be read by other tools and
%   programming languages.
%
%   store = nansen.options.ProfileStore(rootFolder, methodName)
%
%   See also nansen.options.Manager nansen.options.Profile

    properties (SetAccess = immutable)
        RootFolder (1,1) string = ""        % Root folder for all option profiles
        MethodName (1,1) string = ""        % Name of method
    end

    properties (Dependent, SetAccess = private)
        FolderPath (1,1) string             % Folder where profiles of this method are saved
    end

    properties (Constant, Hidden)
        SETTINGS_FILENAME = "_settings.json"
    end

    methods
        function obj = ProfileStore(rootFolder, methodName)
            arguments
                rootFolder (1,1) string = ""
                methodName (1,1) string = ""
            end
            obj.RootFolder = rootFolder;
            obj.MethodName = methodName;
        end

        function names = list(obj)
        %list List names of all saved profiles
            arguments
                obj (1,1) nansen.options.ProfileStore
            end

            names = string.empty(1, 0);
            if ~isfolder(obj.FolderPath); return; end

            L = dir(fullfile(obj.FolderPath, "*.json"));
            L = L(~strcmp({L.name}, obj.SETTINGS_FILENAME));

            for i = 1:numel(L)
                filePath = fullfile(L(i).folder, L(i).name);
                try
                    S = readJson(filePath);
                    names(end+1) = string(S.Name); %#ok<AGROW>
                catch ME
                    warning("NANSEN:Options:CorruptProfile", ...
                        "Could not read profile file ""%s"": %s", filePath, ME.message)
                end
            end
            names = sort(names);
        end

        function tf = exists(obj, name)
        %exists Check if a profile with the given name is saved
            arguments
                obj (1,1) nansen.options.ProfileStore
                name (1,1) string
            end
            tf = isfile(obj.getFilePath(name));
        end

        function profile = read(obj, name)
        %read Read a profile
            arguments
                obj (1,1) nansen.options.ProfileStore
                name (1,1) string
            end
            filePath = obj.getFilePath(name);
            if ~isfile(filePath)
                error("NANSEN:Options:ProfileNotFound", ...
                    "No profile named ""%s"" exists for ""%s""", name, obj.MethodName)
            end
            profile = nansen.options.Profile.fromStruct(readJson(filePath));
        end

        function write(obj, profile, options)
        %write Write a profile to file
        %
        %   store.write(profile) saves a profile. Throws an error if a
        %   profile with the same name already exists.
        %
        %   store.write(profile, Overwrite=true) overwrites an existing profile.
            arguments
                obj (1,1) nansen.options.ProfileStore
                profile (1,1) nansen.options.Profile
                options.Overwrite (1,1) logical = false
            end

            filePath = obj.getFilePath(profile.Name);

            if isfile(filePath)
                existing = readJson(filePath);
                if string(existing.Name) ~= profile.Name
                    error("NANSEN:Options:NameConflict", "Can not save profile " + ...
                        """%s"" because its filename conflicts with profile ""%s""", ...
                        profile.Name, existing.Name)
                elseif ~options.Overwrite
                    error("NANSEN:Options:ProfileExists", ...
                        "A profile named ""%s"" already exists for ""%s""", ...
                        profile.Name, obj.MethodName)
                end
            end

            writeJson(filePath, profile.toStruct())
        end

        function remove(obj, name)
        %remove Delete a saved profile
            arguments
                obj (1,1) nansen.options.ProfileStore
                name (1,1) string
            end
            filePath = obj.getFilePath(name);
            if ~isfile(filePath)
                error("NANSEN:Options:ProfileNotFound", ...
                    "No profile named ""%s"" exists for ""%s""", name, obj.MethodName)
            end
            delete(filePath)
        end

        function value = getSetting(obj, name, defaultValue)
        %getSetting Get a setting (e.g. name of default profile)
            arguments
                obj (1,1) nansen.options.ProfileStore
                name (1,1) string
                defaultValue = []
            end
            value = defaultValue;
            filePath = fullfile(obj.FolderPath, obj.SETTINGS_FILENAME);
            if isfile(filePath)
                S = readJson(filePath);
                if isfield(S, name); value = S.(name); end
            end
        end

        function setSetting(obj, name, value)
        %setSetting Set a setting (e.g. name of default profile)
            arguments
                obj (1,1) nansen.options.ProfileStore
                name (1,1) string
                value
            end
            filePath = fullfile(obj.FolderPath, obj.SETTINGS_FILENAME);
            S = struct();
            if isfile(filePath); S = readJson(filePath); end
            S.(name) = value;
            writeJson(filePath, S)
        end

        function filePath = getFilePath(obj, profileName)
        %getFilePath Get path to the file of a profile
            arguments
                obj (1,1) nansen.options.ProfileStore
                profileName (1,1) string
            end
            fileName = nansen.options.internal.sanitizeName(profileName) + ".json";
            filePath = fullfile(obj.FolderPath, fileName);
        end
    end

    methods
        function folderPath = get.FolderPath(obj)
            folderPath = fullfile(obj.RootFolder, ...
                nansen.options.internal.sanitizeName(obj.MethodName));
        end
    end
end

function S = readJson(filePath)
    S = nansen.options.internal.jsonDecode(fileread(filePath));
end

function writeJson(filePath, S)
%writeJson Write to a temporary file first, so files are never left corrupt
    folderPath = fileparts(filePath);
    if ~isfolder(folderPath); mkdir(folderPath); end

    tempFilePath = filePath + ".tmp";
    writelines(nansen.options.internal.jsonEncode(S), tempFilePath)

    [wasSuccess, message] = movefile(tempFilePath, filePath, "f");
    if ~wasSuccess
        error("NANSEN:Options:FileError", "Could not write to ""%s"": %s", filePath, message)
    end
end
