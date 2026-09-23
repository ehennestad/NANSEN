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

    properties (SetAccess = private)
        RootFolder char = ''        % Root folder for all option profiles
        MethodName char = ''        % Name of method
    end

    properties (Dependent)
        FolderPath                  % Folder where profiles of this method are saved
    end

    properties (Constant, Hidden)
        SETTINGS_FILENAME = '_settings.json'
    end

    methods
        function obj = ProfileStore(rootFolder, methodName)
            obj.RootFolder = char(rootFolder);
            obj.MethodName = char(methodName);
        end

        function names = listProfileNames(obj)
        %listProfileNames List names of all saved profiles
            names = cell(1, 0);
            if ~isfolder(obj.FolderPath); return; end

            L = dir(fullfile(obj.FolderPath, '*.json'));
            L = L(~strcmp({L.name}, obj.SETTINGS_FILENAME));

            for i = 1:numel(L)
                try
                    S = readJson(fullfile(obj.FolderPath, L(i).name));
                    names{end+1} = S.Name; %#ok<AGROW>
                catch ME
                    warning('NANSEN:Options:CorruptProfile', ...
                        'Could not read profile file "%s": %s', L(i).name, ME.message)
                end
            end
            names = sort(names);
        end

        function tf = exists(obj, name)
            tf = isfile(obj.getFilePath(name));
        end

        function profile = load(obj, name)
        %load Load a profile
            filePath = obj.getFilePath(name);
            if ~isfile(filePath)
                error('NANSEN:Options:ProfileNotFound', ...
                    'No profile named "%s" exists for "%s"', name, obj.MethodName)
            end
            profile = nansen.options.Profile.fromStruct(readJson(filePath));
        end

        function save(obj, profile, allowOverwrite)
        %save Save a profile
        %
        %   store.save(profile) saves a profile. Throws an error if a
        %   profile with the same name already exists.
        %
        %   store.save(profile, true) overwrites an existing profile.

            if nargin < 3; allowOverwrite = false; end

            filePath = obj.getFilePath(profile.Name);

            if isfile(filePath)
                existing = readJson(filePath);
                if ~strcmp(existing.Name, profile.Name)
                    error('NANSEN:Options:NameConflict', ['Can not save profile ', ...
                        '"%s" because its filename conflicts with profile "%s"'], ...
                        profile.Name, existing.Name)
                elseif ~allowOverwrite
                    error('NANSEN:Options:ProfileExists', ...
                        'A profile named "%s" already exists for "%s"', ...
                        profile.Name, obj.MethodName)
                end
            end

            if ~isfolder(obj.FolderPath); mkdir(obj.FolderPath); end
            writeJson(filePath, profile.toStruct())
        end

        function remove(obj, name)
        %remove Delete a saved profile
            filePath = obj.getFilePath(name);
            if isfile(filePath)
                delete(filePath)
            else
                error('NANSEN:Options:ProfileNotFound', ...
                    'No profile named "%s" exists for "%s"', name, obj.MethodName)
            end
        end

        function value = getSetting(obj, name, defaultValue)
        %getSetting Get a setting (e.g. name of default profile)
            if nargin < 3; defaultValue = []; end
            value = defaultValue;

            filePath = fullfile(obj.FolderPath, obj.SETTINGS_FILENAME);
            if isfile(filePath)
                S = readJson(filePath);
                if isfield(S, name); value = S.(name); end
            end
        end

        function setSetting(obj, name, value)
        %setSetting Set a setting (e.g. name of default profile)
            filePath = fullfile(obj.FolderPath, obj.SETTINGS_FILENAME);
            if isfile(filePath)
                S = readJson(filePath);
            else
                S = struct();
            end
            S.(name) = value;

            if ~isfolder(obj.FolderPath); mkdir(obj.FolderPath); end
            writeJson(filePath, S)
        end

        function filePath = getFilePath(obj, profileName)
            fileName = [nansen.options.internal.sanitizeName(profileName), '.json'];
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
%writeJson Write to a temporary file first to avoid corrupt files
    jsonStr = nansen.options.internal.jsonEncode(S);

    tempFilePath = [filePath, '.tmp'];
    fid = fopen(tempFilePath, 'w', 'n', 'UTF-8');
    if fid == -1
        error('NANSEN:Options:FileError', 'Could not write to "%s"', filePath)
    end
    fprintf(fid, '%s', jsonStr);
    fclose(fid);

    [wasSuccess, message] = movefile(tempFilePath, filePath, 'f');
    if ~wasSuccess
        error('NANSEN:Options:FileError', 'Could not write to "%s": %s', filePath, message)
    end
end
