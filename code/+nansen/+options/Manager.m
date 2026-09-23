classdef Manager < handle
%nansen.options.Manager Manage option profiles for a method
%
%   The manager ties together the schema of a method (definition of
%   parameters and presets) and the profiles that users have saved.
%
%   Options are resolved in layers, where each layer overrides the
%   previous one:
%
%       1. Schema defaults      (defined in code)
%       2. Preset               (defined in code, optional)
%       3. User profile(s)      (saved by user, can derive from each other)
%       4. Runtime overrides    (given when calling a method)
%
%   USAGE:
%       m = nansen.options.Manager('nansen.some.method');
%       m = nansen.options.Manager(schema, 'Location', folderPath);
%
%       m.listProfiles()
%
%       % Get options (and a record for provenance)
%       opts = m.resolve();                          % default profile
%       [opts, record] = m.resolve('Fast', 'binSize', 3);
%
%       % Create a profile from a preset, with some changes
%       m.createProfile('My profile', {'binSize', 4}, 'Parent', 'Fast', ...
%           'Description', 'Tuned for dataset X')
%       m.setDefaultProfile('My profile')
%
%       % Edit options interactively and save as a new profile
%       opts = m.edit('My profile');
%       m.createProfile('My profile 2', opts, 'Parent', 'My profile')
%
%   See also nansen.options.Schema nansen.options.Profile
%            nansen.options.OptionsRecord nansen.options.getSchema

    properties (SetAccess = private)
        Schema = []                 % nansen.options.Schema
        Store = []                  % nansen.options.ProfileStore
    end

    properties (Dependent)
        MethodName                  % Name of method
        ProfileNames                % Names of all profiles (defaults, presets and user profiles)
        DefaultProfileName          % Name of profile used when no profile is specified
    end

    methods % Constructor
        function obj = Manager(schema, varargin)
        %Manager Create an options manager
        %
        %   m = nansen.options.Manager(methodName) creates a manager for
        %   the method with the given name. The schema is retrieved using
        %   nansen.options.getSchema.
        %
        %   m = nansen.options.Manager(schema) creates a manager for the
        %   given schema.
        %
        %   m = nansen.options.Manager(..., 'Location', folderPath) saves
        %   profiles in the given folder.

            if ischar(schema) || isstring(schema)
                schema = nansen.options.getSchema(schema);
            end
            assert(isa(schema, 'nansen.options.Schema'), ...
                'NANSEN:Options:InvalidInput', ...
                'First input must be a method name or a nansen.options.Schema')
            assert(~isempty(schema.Name), 'NANSEN:Options:InvalidInput', ...
                'Schema must have a name')

            location = '';
            for i = 1:2:numel(varargin)
                switch lower(char(varargin{i}))
                    case 'location'
                        location = char(varargin{i+1});
                    otherwise
                        error('NANSEN:Options:InvalidInput', ...
                            'Unknown option "%s"', char(varargin{i}))
                end
            end

            if isempty(location)
                location = nansen.options.Manager.getDefaultLocation(schema.Name);
            end

            obj.Schema = schema;
            obj.Store = nansen.options.ProfileStore(location, schema.Name);
        end
    end

    methods % Profiles

        function T = listProfiles(obj)
        %listProfiles List all available profiles
        %
        %   T = m.listProfiles() returns a table (or struct array) with
        %   Name, Type, Parent, Description, Modified and IsDefault.

            defaultName = obj.DefaultProfileName;
            defaultsName = obj.Schema.DEFAULTS_PROFILE_NAME;

            S = struct('Name', {}, 'Type', {}, 'Parent', {}, ...
                'Description', {}, 'Modified', {}, 'IsDefault', {});

            S(end+1) = struct('Name', defaultsName, 'Type', 'defaults', ...
                'Parent', '', 'Description', 'Default values', ...
                'Modified', '', 'IsDefault', strcmp(defaultName, defaultsName));

            for i = 1:numel(obj.Schema.Presets)
                preset = obj.Schema.Presets(i);
                S(end+1) = struct('Name', preset.Name, 'Type', 'preset', ...
                    'Parent', defaultsName, 'Description', preset.Description, ...
                    'Modified', '', 'IsDefault', strcmp(defaultName, preset.Name)); %#ok<AGROW>
            end

            userProfileNames = obj.Store.listProfileNames();
            for i = 1:numel(userProfileNames)
                profile = obj.Store.load(userProfileNames{i});
                parentName = profile.Parent;
                if isempty(parentName); parentName = defaultsName; end
                S(end+1) = struct('Name', profile.Name, 'Type', 'user', ...
                    'Parent', parentName, 'Description', profile.Description, ...
                    'Modified', profile.Modified, ...
                    'IsDefault', strcmp(defaultName, profile.Name)); %#ok<AGROW>
            end

            try
                T = struct2table(S, 'AsArray', true);
            catch % Tables not available
                T = S;
            end
        end

        function tf = hasProfile(obj, name)
        %hasProfile Check if a profile (or preset) with given name exists
            tf = strcmp(name, obj.Schema.DEFAULTS_PROFILE_NAME) || ...
                obj.Schema.hasPreset(name) || obj.Store.exists(name);
        end

        function profile = getProfile(obj, name)
        %getProfile Get a profile (presets and defaults are also returned as profiles)

            if strcmp(name, obj.Schema.DEFAULTS_PROFILE_NAME)
                profile = nansen.options.Profile(name, 'Type', 'defaults', ...
                    'MethodName', obj.MethodName, 'SchemaVersion', obj.Schema.Version);
            elseif obj.Schema.hasPreset(name)
                preset = obj.Schema.getPreset(name);
                profile = nansen.options.Profile(name, 'Type', 'preset', ...
                    'MethodName', obj.MethodName, 'Description', preset.Description, ...
                    'Overrides', preset.Overrides, 'SchemaVersion', obj.Schema.Version);
            else
                profile = obj.Store.load(name);
            end
        end

        function [values, record] = resolve(obj, profileName, varargin)
        %resolve Get the values of options for a profile
        %
        %   values = m.resolve() returns values of the default profile.
        %
        %   values = m.resolve(profileName) returns values of the given
        %   profile (or preset).
        %
        %   values = m.resolve(profileName, Name, Value, ...) or
        %   values = m.resolve(profileName, overridesStruct) applies
        %   runtime overrides on top of the profile. Names can be full
        %   (dotted) names or unique short names.
        %
        %   [values, record] = m.resolve(...) also returns an
        %   nansen.options.OptionsRecord that should be saved with the
        %   results of the method.

            if nargin < 2 || isempty(profileName)
                profileName = obj.DefaultProfileName;
            end
            profileName = char(profileName);

            [values, sources, migrationLog] = obj.resolveProfile(profileName, {});

            runtimeOverrides = struct();
            if ~isempty(varargin)
                if numel(varargin) == 1 && isstruct(varargin{1})
                    runtimeOverrides = obj.Schema.parseOverrides(varargin{1});
                else
                    runtimeOverrides = obj.Schema.parseOverrides(varargin);
                end
                values = obj.Schema.applyOverrides(values, runtimeOverrides);
                sources = markSources(sources, runtimeOverrides, 'runtime');
            end

            if nargout > 1
                record = nansen.options.OptionsRecord.create(obj.Schema, values, ...
                    'ProfileName', profileName, ...
                    'RuntimeOverrides', runtimeOverrides, ...
                    'Sources', sources, ...
                    'MigrationLog', migrationLog);
            end
        end

        function profile = createProfile(obj, name, values, varargin)
        %createProfile Create and save a new profile
        %
        %   profile = m.createProfile(name, values) creates a profile.
        %   values can be a complete or partial struct of options, or a
        %   cell array of name-value pairs. Only values that differ from
        %   the parent are stored as overrides.
        %
        %   profile = m.createProfile(name, values, Name, Value, ...)
        %
        %   NAME-VALUE PAIRS:
        %       Parent      : Name of parent profile or preset (default: schema defaults)
        %       Description : Description of profile
        %       Frozen      : If true, values of this profile do not change
        %                     if inherited values (defaults/parent) change.
        %       Tags        : Cell array of tags
        %       Overwrite   : Overwrite an existing profile (default false)

            if nargin < 3; values = struct(); end

            params = struct('Parent', '', 'Description', '', 'Frozen', false, ...
                'Tags', {{}}, 'Overwrite', false);
            params = parseNameValuePairs(params, varargin{:});

            name = strtrim(char(name));
            obj.assertValidNewProfileName(name, params.Overwrite)

            parentName = char(params.Parent);
            if strcmp(parentName, obj.Schema.DEFAULTS_PROFILE_NAME)
                parentName = '';
            end
            if ~isempty(parentName)
                assert(obj.hasProfile(parentName), 'NANSEN:Options:ProfileNotFound', ...
                    'Parent profile "%s" does not exist', parentName)
                assert(~strcmp(parentName, name), 'NANSEN:Options:InvalidInput', ...
                    'A profile can not be its own parent')
            end

            [fullValues, overrides] = obj.computeValuesAndOverrides(values, parentName, []);

            timestamp = nansen.options.internal.isoTimestamp();

            profile = nansen.options.Profile(name, ...
                'Description', char(params.Description), ...
                'MethodName', obj.MethodName, ...
                'Parent', parentName, ...
                'Overrides', overrides, ...
                'Frozen', logical(params.Frozen), ...
                'Tags', params.Tags, ...
                'SchemaVersion', obj.Schema.Version, ...
                'DefaultsHash', obj.Schema.getDefaultsHash(), ...
                'Snapshot', fullValues, ...
                'Created', timestamp, ...
                'Modified', timestamp, ...
                'CreatedBy', nansen.options.internal.getCurrentUser(), ...
                'NansenVersion', getNansenVersion());

            obj.Store.save(profile, params.Overwrite)

            if ~nargout; clear profile; end
        end

        function profile = updateProfile(obj, name, values, varargin)
        %updateProfile Update values or attributes of a saved profile
        %
        %   profile = m.updateProfile(name, values) sets new values. values
        %   can be a partial struct or a cell array of name-value pairs.
        %
        %   profile = m.updateProfile(name, values, Name, Value, ...) also
        %   updates attributes: Parent, Description, Frozen, Tags
        %
        %   The snapshot of the profile is updated, so any warnings about
        %   changed inherited values are resolved.

            if nargin < 3; values = struct(); end

            obj.assertIsUserProfile(name)
            profile = obj.Store.load(name);

            params = struct('Parent', profile.Parent, ...
                'Description', profile.Description, ...
                'Frozen', profile.Frozen, 'Tags', {profile.Tags});
            params = parseNameValuePairs(params, varargin{:});

            parentName = char(params.Parent);
            if strcmp(parentName, obj.Schema.DEFAULTS_PROFILE_NAME)
                parentName = '';
            end
            if ~isempty(parentName)
                assert(obj.hasProfile(parentName), 'NANSEN:Options:ProfileNotFound', ...
                    'Parent profile "%s" does not exist', parentName)
                obj.assertNoCycle(name, parentName)
            end

            % Current values of the profile are the starting point
            currentValues = obj.resolveProfile(name, {}, true);
            [fullValues, overrides] = obj.computeValuesAndOverrides( ...
                values, parentName, currentValues);

            profile.Parent = parentName;
            profile.Description = char(params.Description);
            profile.Frozen = logical(params.Frozen);
            profile.Tags = params.Tags;
            profile.Overrides = overrides;
            profile.Snapshot = fullValues;
            profile.SchemaVersion = obj.Schema.Version;
            profile.DefaultsHash = obj.Schema.getDefaultsHash();
            profile.Modified = nansen.options.internal.isoTimestamp();
            profile.NansenVersion = getNansenVersion();

            obj.Store.save(profile, true)

            if ~nargout; clear profile; end
        end

        function profile = refreshProfile(obj, name)
        %refreshProfile Accept current inherited values and migrate profile
        %
        %   If defaults (or a parent profile) have changed since a profile
        %   was saved, resolving the profile gives a warning. Use this
        %   method to accept the changes and save the profile in the
        %   current schema version. (For frozen profiles, values are kept
        %   as they are and stored as explicit overrides instead)
            profile = obj.updateProfile(name, struct());
            if ~nargout; clear profile; end
        end

        function deleteProfile(obj, name)
        %deleteProfile Delete a saved profile

            obj.assertIsUserProfile(name)

            % Do not delete profiles that other profiles depend on
            userProfileNames = obj.Store.listProfileNames();
            children = {};
            for i = 1:numel(userProfileNames)
                profile = obj.Store.load(userProfileNames{i});
                if strcmp(profile.Parent, name)
                    children{end+1} = profile.Name; %#ok<AGROW>
                end
            end
            if ~isempty(children)
                error('NANSEN:Options:ProfileInUse', ...
                    'Can not delete "%s" because it is the parent of: %s', ...
                    name, strjoin(children, ', '))
            end

            if strcmp(obj.Store.getSetting('DefaultProfile', ''), name)
                obj.Store.setSetting('DefaultProfile', '')
            end

            obj.Store.remove(name)
        end

        function setDefaultProfile(obj, name)
        %setDefaultProfile Set profile to use when no profile is specified
            assert(obj.hasProfile(name), 'NANSEN:Options:ProfileNotFound', ...
                'No profile named "%s" exists', name)
            if strcmp(name, obj.Schema.DEFAULTS_PROFILE_NAME); name = ''; end
            obj.Store.setSetting('DefaultProfile', char(name))
        end

        function differences = compareProfiles(obj, nameA, nameB)
        %compareProfiles Compare the values of two profiles
        %
        %   differences = m.compareProfiles(nameA, nameB) returns a struct
        %   array with fields Name, ValueA, ValueB and Change.
            differences = nansen.options.internal.diffStruct( ...
                obj.resolve(nameA), obj.resolve(nameB));
        end

        function [values, wasAborted] = edit(obj, profileName, values)
        %edit Edit options interactively in the options editor
        %
        %   [values, wasAborted] = m.edit(profileName) opens the values of
        %   a profile in the options editor and returns the edited values.
        %   Use createProfile or updateProfile to save them.

            if nargin < 2 || isempty(profileName)
                profileName = obj.DefaultProfileName;
            end
            if nargin < 3 || isempty(values)
                values = obj.resolve(profileName);
            end

            S = obj.Schema.toEditorStruct(values);
            titleStr = sprintf('Options for %s (%s)', ...
                obj.Schema.getDisplayTitle(), profileName);

            [S, wasAborted] = tools.editStruct(S, 'all', titleStr);
            values = obj.Schema.fromEditorStruct(S);
        end

        function imported = importLegacyOptions(obj, filePath)
        %importLegacyOptions Import custom options saved by nansen.manage.OptionsManager
        %
        %   imported = m.importLegacyOptions() imports all custom options
        %   sets that were saved with the legacy options manager as
        %   profiles, and returns the names of imported profiles.
        %
        %   imported = m.importLegacyOptions(filePath) imports from a
        %   specific file.

            if nargin < 2 || isempty(filePath)
                filePath = obj.getLegacyFilePath();
            end

            imported = cell(1, 0);
            if isempty(filePath) || ~isfile(filePath)
                return
            end

            S = load(filePath);
            if ~isfield(S, 'OptionsEntries'); return; end

            for i = 1:numel(S.OptionsEntries)
                entry = S.OptionsEntries(i);
                if ~strcmp(entry.Type, 'Custom') || obj.hasProfile(entry.Name)
                    continue
                end

                try
                    values = obj.Schema.conform(entry.Options, 'Unknown', 'warn');
                    description = entry.Description;
                    if isempty(description)
                        description = sprintf('Imported from legacy options (created %s)', ...
                            entry.DateCreated);
                    end
                    obj.createProfile(entry.Name, values, 'Description', description);
                    imported{end+1} = entry.Name; %#ok<AGROW>
                catch ME
                    warning('NANSEN:Options:ImportFailed', ...
                        'Could not import options "%s": %s', entry.Name, ME.message)
                end
            end

            if isfield(S, 'DefaultOptionsName') && any(strcmp(imported, S.DefaultOptionsName))
                obj.setDefaultProfile(S.DefaultOptionsName)
            end
        end
    end

    methods % Set/get

        function name = get.MethodName(obj)
            name = obj.Schema.Name;
        end

        function names = get.ProfileNames(obj)
            names = [{obj.Schema.DEFAULTS_PROFILE_NAME}, obj.Schema.PresetNames, ...
                obj.Store.listProfileNames()];
        end

        function name = get.DefaultProfileName(obj)
            name = obj.Store.getSetting('DefaultProfile', '');
            if isempty(name) || ~obj.hasProfile(name)
                name = obj.Schema.DEFAULTS_PROFILE_NAME;
            end
        end
    end

    methods (Access = private)

        function [values, sources, migrationLog] = resolveProfile(obj, name, visited, isQuiet)
        %resolveProfile Resolve values of a profile by resolving its parents

            if nargin < 4; isQuiet = false; end

            schema = obj.Schema;
            migrationLog = {};

            if strcmp(name, schema.DEFAULTS_PROFILE_NAME)
                values = schema.getDefaults();
                sources = markSources(struct(), values, 'defaults');

            elseif schema.hasPreset(name)
                [values, sources] = obj.resolveProfile(schema.DEFAULTS_PROFILE_NAME, visited);
                preset = schema.getPreset(name);
                values = schema.applyOverrides(values, preset.Overrides);
                sources = markSources(sources, preset.Overrides, ['preset:', name]);

            elseif obj.Store.exists(name)
                if any(strcmp(visited, name))
                    error('NANSEN:Options:CyclicProfiles', ...
                        'Profiles have cyclic parents: %s', strjoin([visited, {name}], ' -> '))
                end

                profile = obj.Store.load(name);
                [overrides, snapshot, migrationLog] = obj.migrateProfile(profile);

                parentName = profile.Parent;
                if isempty(parentName); parentName = schema.DEFAULTS_PROFILE_NAME; end
                [values, sources, parentLog] = obj.resolveProfile( ...
                    parentName, [visited, {name}], isQuiet);
                migrationLog = [parentLog, migrationLog];

                if profile.Frozen && ~isempty(fieldnames(snapshot))
                    values = schema.conform(snapshot, 'Unknown', 'drop');
                    sources = markSources(sources, snapshot, ['profile:', name, ' (frozen)']);
                else
                    values = schema.applyOverrides(values, overrides);
                    sources = markSources(sources, overrides, ['profile:', name]);
                    if ~isQuiet
                        obj.warnIfValuesChanged(profile, values, snapshot)
                    end
                end
            else
                error('NANSEN:Options:ProfileNotFound', ...
                    'No profile named "%s" exists for "%s"', name, obj.MethodName)
            end
        end

        function [overrides, snapshot, migrationLog] = migrateProfile(obj, profile)
        %migrateProfile Migrate saved values of profile to current schema

            schema = obj.Schema;
            overrides = profile.Overrides;
            snapshot = profile.Snapshot;
            migrationLog = {};

            if ~isempty(profile.SchemaVersion) && nansen.options.internal.compareVersions( ...
                    profile.SchemaVersion, schema.Version) < 0
                [overrides, migrationLog] = schema.migrate(overrides, profile.SchemaVersion);
                snapshot = schema.migrate(snapshot, profile.SchemaVersion);
                migrationLog = cellfun(@(str) sprintf('Profile "%s": %s', profile.Name, str), ...
                    migrationLog, 'UniformOutput', false);
            end

            % Remove overrides for parameters which no longer exist.
            overrideNames = nansen.options.internal.flattenStruct(overrides);
            obsoleteNames = setdiff(overrideNames, schema.ParameterNames, 'stable');
            if ~isempty(obsoleteNames)
                warning('NANSEN:Options:ObsoleteParameter', ...
                    ['Profile "%s" contains values for parameters that no longer ', ...
                    'exist and will be ignored: %s'], profile.Name, strjoin(obsoleteNames, ', '))
                for i = 1:numel(obsoleteNames)
                    overrides = nansen.options.internal.removeValue(overrides, obsoleteNames{i});
                end
            end
        end

        function warnIfValuesChanged(obj, profile, values, snapshot)
        %warnIfValuesChanged Warn if values differ from when profile was saved
        %
        %   Values of a profile that are not overridden are inherited from
        %   the parent/defaults. If these change (e.g. because a developer
        %   changed a default value), the results of a method might change.
        %   This should never happen silently.

            if isempty(fieldnames(snapshot)); return; end

            try
                snapshot = obj.Schema.conform(snapshot, 'Unknown', 'drop');
            catch
                return % Snapshot is no longer valid, i.e. schema changed
            end

            differences = nansen.options.internal.diffStruct(snapshot, values);
            if isempty(differences); return; end

            changes = arrayfun(@(d) sprintf('  %s: %s -> %s', d.Name, ...
                nansen.options.internal.valueToString(d.ValueA), ...
                nansen.options.internal.valueToString(d.ValueB)), ...
                differences, 'UniformOutput', false);

            warning('NANSEN:Options:InheritedValuesChanged', ...
                ['Values of profile "%s" have changed since it was saved, because ', ...
                'defaults or a parent profile changed:\n%s\n', ...
                'Use refreshProfile to accept the new values, updateProfile to ', ...
                'set explicit values, or make the profile Frozen to keep values fixed.'], ...
                profile.Name, strjoin(changes, newline))
        end

        function [fullValues, overrides] = computeValuesAndOverrides(obj, values, parentName, baseValues)
        %computeValuesAndOverrides Get all values and overrides relative to parent

            if isempty(parentName)
                parentName = obj.Schema.DEFAULTS_PROFILE_NAME;
            end
            parentValues = obj.resolveProfile(parentName, {}, true);

            if isempty(baseValues); baseValues = parentValues; end
            if isempty(values); values = struct(); end

            fullValues = obj.Schema.applyOverrides(baseValues, values);

            differences = nansen.options.internal.diffStruct(parentValues, fullValues);
            overrides = struct();
            for i = 1:numel(differences)
                overrides = nansen.options.internal.setValue(overrides, ...
                    differences(i).Name, differences(i).ValueB);
            end
        end

        function assertValidNewProfileName(obj, name, allowOverwrite)
            if isempty(name)
                error('NANSEN:Options:InvalidName', 'Profile name can not be empty')
            elseif strcmpi(name, obj.Schema.DEFAULTS_PROFILE_NAME)
                error('NANSEN:Options:ReservedName', '"%s" is a reserved name', name)
            elseif obj.Schema.hasPreset(name)
                error('NANSEN:Options:ReservedName', ...
                    'A preset named "%s" already exists', name)
            elseif obj.Store.exists(name) && ~allowOverwrite
                error('NANSEN:Options:ProfileExists', ...
                    'A profile named "%s" already exists', name)
            end
        end

        function assertIsUserProfile(obj, name)
            if strcmp(name, obj.Schema.DEFAULTS_PROFILE_NAME) || obj.Schema.hasPreset(name)
                error('NANSEN:Options:ReadOnlyProfile', ...
                    '"%s" is defined in code and can not be modified', name)
            elseif ~obj.Store.exists(name)
                error('NANSEN:Options:ProfileNotFound', ...
                    'No profile named "%s" exists for "%s"', name, obj.MethodName)
            end
        end

        function assertNoCycle(obj, name, parentName)
            visited = {name};
            while ~isempty(parentName) && obj.Store.exists(parentName)
                if any(strcmp(visited, parentName))
                    error('NANSEN:Options:CyclicProfiles', ...
                        'Setting parent to "%s" would create a cycle', parentName)
                end
                visited{end+1} = parentName; %#ok<AGROW>
                parentProfile = obj.Store.load(parentName);
                parentName = parentProfile.Parent;
            end
        end

        function filePath = getLegacyFilePath(obj)
        %getLegacyFilePath Get path to file of legacy options manager
            filePath = '';
            try
                folderPath = nansen.options.Manager.getOptionsFolder(obj.MethodName);
                filePath = fullfile(folderPath, [obj.MethodName, '.mat']);
            catch
                % Options folder is not available (nansen is not set up)
            end
        end
    end

    methods (Static)
        function location = getDefaultLocation(methodName)
        %getDefaultLocation Get default folder for saving profiles
        %
        %   Profiles for methods that are part of NANSEN are saved in the
        %   user's local NANSEN folder, while profiles for methods that
        %   are part of a project are saved in the project folder (same
        %   rule as the legacy nansen.manage.OptionsManager).
            location = fullfile(nansen.options.Manager.getOptionsFolder(methodName), 'profiles');
        end
        
        function folderPath = getOptionsFolder(methodName)
        %getOptionsFolder Get folder for options (local or project folder)
            pathStr = which(methodName);
            isNansenMethod = ~isempty(strfind(pathStr, fullfile('code', 'integrations', 'sessionmethods'))) || ...
                ~isempty(strfind(pathStr, '+nansen')); %#ok<STREMP>

            if isNansenMethod
                folderPath = nansen.localpath('custom_options');
            else
                folderPath = nansen.localpath('project_custom_options');
            end
        end
    end
end

function sources = markSources(sources, values, sourceName)
%markSources Set source for all (leaf) values in values
    names = nansen.options.internal.flattenStruct(values);
    for i = 1:numel(names)
        sources = nansen.options.internal.setValue(sources, names{i}, sourceName);
    end
end

function params = parseNameValuePairs(params, varargin)
    names = fieldnames(params);
    for i = 1:2:numel(varargin)
        name = validatestring(char(varargin{i}), names);
        params.(name) = varargin{i+1};
    end
end

function versionStr = getNansenVersion()
    try
        versionStr = nansen.version();
    catch
        versionStr = '';
    end
end
