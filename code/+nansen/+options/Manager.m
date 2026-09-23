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
%       m = nansen.options.Manager("some.package.MyMethod");
%       m = nansen.options.Manager(schema, Location=folderPath);
%
%       m.listProfiles()
%
%       % Get options (and a record for provenance)
%       opts = m.resolve();                          % default profile
%       [opts, record] = m.resolve("Fast", Overrides={"binSize", 3});
%
%       % Create a profile from a preset, with some changes
%       m.createProfile("My profile", {"binSize", 4}, Parent="Fast", ...
%           Description="Tuned for dataset X")
%       m.setDefaultProfile("My profile")
%
%       % Edit options interactively
%       opts = m.edit("My profile");
%
%   See also nansen.options.Schema nansen.options.Profile
%            nansen.options.OptionsRecord nansen.options.getSchema

    properties (SetAccess = immutable)
        Schema (1,1) nansen.options.Schema          % Schema of method
        Store (1,1) nansen.options.ProfileStore     % Storage of user profiles
    end

    properties (Dependent, SetAccess = private)
        MethodName (1,1) string             % Name of method
        ProfileNames (1,:) string           % Names of all profiles (defaults, presets and user profiles)
        UserProfileNames (1,:) string       % Names of profiles saved by users
        DefaultProfileName (1,1) string     % Name of profile used when no profile is specified
    end

    methods % Constructor
        function obj = Manager(schema, options)
        %Manager Create an options manager
        %
        %   m = nansen.options.Manager(methodName) creates a manager for
        %   the method with the given name. The schema is retrieved using
        %   nansen.options.getSchema.
        %
        %   m = nansen.options.Manager(schema) creates a manager for the
        %   given schema.
        %
        %   m = nansen.options.Manager(..., Location=folderPath) saves
        %   profiles in the given folder.

            arguments
                schema {mustBeA(schema, ["string", "char", "nansen.options.Schema"])}
                options.Location (1,1) string = ""
            end

            if ~isa(schema, "nansen.options.Schema")
                schema = nansen.options.getSchema(schema);
            end
            if schema.Name == ""
                error("NANSEN:Options:InvalidInput", "Schema must have a name")
            end

            location = options.Location;
            if location == ""
                location = nansen.options.Manager.getDefaultLocation(schema.Name);
            end

            obj.Schema = schema;
            obj.Store = nansen.options.ProfileStore(location, schema.Name);
        end
    end

    methods % Resolve options

        function [values, record] = resolve(obj, profileName, options)
        %resolve Get the values of options for a profile
        %
        %   values = m.resolve() returns values of the default profile.
        %
        %   values = m.resolve(profileName) returns values of the given
        %   profile (or preset).
        %
        %   values = m.resolve(profileName, Overrides=overrides) applies
        %   runtime overrides on top of the profile. Overrides can be a
        %   (partial) struct or a cell array of name-value pairs, where
        %   names are full (dotted) names or unique short names.
        %
        %   [values, record] = m.resolve(...) also returns an
        %   nansen.options.OptionsRecord which should be saved with the
        %   results of the method.
        %
        %   NAME-VALUE ARGUMENTS:
        %       Overrides         : Runtime overrides (struct or cell)
        %       CaptureProvenance : Capture provenance in record (default true)

            arguments
                obj (1,1) nansen.options.Manager
                profileName (1,1) string = obj.DefaultProfileName
                options.Overrides {mustBeA(options.Overrides, ["struct", "cell"])} = struct()
                options.CaptureProvenance (1,1) logical = true
            end

            [values, sources, migrationLog] = obj.resolveProfile(profileName);

            runtimeOverrides = obj.Schema.parseOverrides(options.Overrides);
            values = obj.Schema.applyOverrides(values, runtimeOverrides);
            sources = markSources(sources, runtimeOverrides, "runtime");

            if nargout > 1
                record = nansen.options.OptionsRecord.create(obj.Schema, values, ...
                    ProfileName=profileName, ...
                    RuntimeOverrides=runtimeOverrides, ...
                    Sources=sources, ...
                    MigrationLog=migrationLog, ...
                    CaptureProvenance=options.CaptureProvenance);
            end
        end

        function differences = compareProfiles(obj, nameA, nameB)
        %compareProfiles Compare the values of two profiles
        %
        %   differences = m.compareProfiles(nameA, nameB) returns a table
        %   with variables Name, ValueA, ValueB and Change.
            arguments
                obj (1,1) nansen.options.Manager
                nameA (1,1) string
                nameB (1,1) string
            end
            differences = nansen.options.internal.diffStruct( ...
                obj.resolveProfile(nameA, IsQuiet=true), ...
                obj.resolveProfile(nameB, IsQuiet=true));
        end
    end

    methods % Manage profiles

        function T = listProfiles(obj)
        %listProfiles List all available profiles
        %
        %   T = m.listProfiles() returns a table with Name, Type, Parent,
        %   Description, Modified and IsDefault.
            arguments
                obj (1,1) nansen.options.Manager
            end

            userProfiles = arrayfun(@(name) obj.Store.read(name), ...
                obj.UserProfileNames, UniformOutput=false);
            profiles = [obj.getProfile(obj.Schema.DEFAULTS_NAME), ...
                obj.Schema.Presets, userProfiles{:}];

            Name = [profiles.Name]';
            Type = [profiles.Type]';
            Parent = [profiles.Parent]';
            Parent(Parent == "" & Type ~= nansen.options.ProfileType.Defaults) = ...
                obj.Schema.DEFAULTS_NAME;
            Description = [profiles.Description]';
            Modified = [profiles.Modified]';
            IsDefault = Name == obj.DefaultProfileName;

            T = table(Name, Type, Parent, Description, Modified, IsDefault);
        end

        function tf = hasProfile(obj, name)
        %hasProfile Check if a profile (or preset) with given name exists
            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
            end
            tf = name == obj.Schema.DEFAULTS_NAME || ...
                obj.Schema.hasPreset(name) || obj.Store.exists(name);
        end

        function profile = getProfile(obj, name)
        %getProfile Get a profile (presets and defaults are also returned as profiles)
            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
            end

            if name == obj.Schema.DEFAULTS_NAME
                profile = nansen.options.Profile(name, ...
                    Type=nansen.options.ProfileType.Defaults, ...
                    Description="Default values", ...
                    MethodName=obj.MethodName, ...
                    SchemaVersion=obj.Schema.Version);
            elseif obj.Schema.hasPreset(name)
                profile = obj.Schema.getPreset(name);
            else
                profile = obj.Store.read(name);
            end
        end

        function profile = createProfile(obj, name, values, options)
        %createProfile Create and save a new profile
        %
        %   profile = m.createProfile(name, values) creates a profile.
        %   values can be a complete or partial struct of options, or a
        %   cell array of name-value pairs. Only values that differ from
        %   the parent are stored as overrides.
        %
        %   profile = m.createProfile(name, values, Name=Value, ...)
        %
        %   NAME-VALUE ARGUMENTS:
        %       Parent      : Name of parent profile or preset (default: schema defaults)
        %       Description : Description of profile
        %       Frozen      : If true, values of this profile do not change
        %                     if inherited values (defaults/parent) change.
        %       Tags        : Tags for organizing profiles
        %       Overwrite   : Overwrite an existing profile (default false)

            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string {mustBeNonzeroLengthText, nansen.options.internal.mustBeProfileName}
                values {mustBeA(values, ["struct", "cell"])} = struct()
                options.Parent (1,1) string = ""
                options.Description (1,1) string = ""
                options.Frozen (1,1) logical = false
                options.Tags (1,:) string = string.empty(1, 0)
                options.Overwrite (1,1) logical = false
            end

            name = strtrim(name);
            obj.assertValidNewProfileName(name, options.Overwrite)

            parentName = obj.normalizeParentName(options.Parent);
            if parentName == name
                error("NANSEN:Options:InvalidInput", "A profile can not be its own parent")
            end

            [fullValues, overrides] = obj.computeValuesAndOverrides(values, parentName);

            timestamp = datetime("now", "TimeZone", "UTC");

            profile = nansen.options.Profile(name, ...
                Description=options.Description, ...
                MethodName=obj.MethodName, ...
                Parent=parentName, ...
                Overrides=overrides, ...
                Frozen=options.Frozen, ...
                Tags=options.Tags, ...
                SchemaVersion=obj.Schema.Version, ...
                DefaultsHash=obj.Schema.getDefaultsHash(), ...
                Snapshot=fullValues, ...
                Created=timestamp, ...
                Modified=timestamp, ...
                CreatedBy=nansen.options.internal.getCurrentUser(), ...
                NansenVersion=getNansenVersion());

            obj.Store.write(profile, Overwrite=options.Overwrite)

            if ~nargout; clear profile; end
        end

        function profile = updateProfile(obj, name, values, options)
        %updateProfile Update values or attributes of a saved profile
        %
        %   profile = m.updateProfile(name, values) sets new values. values
        %   can be a partial struct or a cell array of name-value pairs.
        %
        %   profile = m.updateProfile(name, values, Name=Value, ...) also
        %   updates attributes: Parent, Description, Frozen, Tags
        %
        %   The snapshot of the profile is updated, so any warnings about
        %   changed inherited values are resolved.

            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
                values {mustBeA(values, ["struct", "cell"])} = struct()
                options.Parent (1,1) string
                options.Description (1,1) string
                options.Frozen (1,1) logical
                options.Tags (1,:) string
            end

            obj.assertIsUserProfile(name)

            % Current values of the profile are the starting point
            currentValues = obj.resolveProfile(name, IsQuiet=true);
            profile = obj.Store.read(name);

            if isfield(options, "Parent")
                profile.Parent = obj.normalizeParentName(options.Parent);
                obj.assertNoCycle(name, profile.Parent)
            end
            if isfield(options, "Description"); profile.Description = options.Description; end
            if isfield(options, "Frozen"); profile.Frozen = options.Frozen; end
            if isfield(options, "Tags"); profile.Tags = options.Tags; end

            [fullValues, overrides] = obj.computeValuesAndOverrides( ...
                values, profile.Parent, currentValues);

            profile.Overrides = overrides;
            profile.Snapshot = fullValues;
            profile.SchemaVersion = obj.Schema.Version;
            profile.DefaultsHash = obj.Schema.getDefaultsHash();
            profile.Modified = datetime("now", "TimeZone", "UTC");
            profile.NansenVersion = getNansenVersion();

            obj.Store.write(profile, Overwrite=true)

            if ~nargout; clear profile; end
        end

        function profile = refreshProfile(obj, name)
        %refreshProfile Accept current inherited values and migrate profile
        %
        %   If defaults (or a parent profile) have changed since a profile
        %   was saved, resolving the profile gives a warning. Use this
        %   method to accept the changes and save the profile in the
        %   current schema version. (Frozen profiles keep their values,
        %   which are then stored as explicit overrides.)
            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
            end
            profile = obj.updateProfile(name, struct());
            if ~nargout; clear profile; end
        end

        function renameProfile(obj, name, newName)
        %renameProfile Rename a saved profile
        %
        %   Profiles that derive from the profile and the default profile
        %   setting are updated accordingly.
            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
                newName (1,1) string {mustBeNonzeroLengthText, nansen.options.internal.mustBeProfileName}
            end

            obj.assertIsUserProfile(name)
            obj.assertValidNewProfileName(newName, false)

            profile = obj.Store.read(name);
            profile.Name = newName;
            profile.Modified = datetime("now", "TimeZone", "UTC");
            obj.Store.write(profile)

            for child = obj.getChildProfiles(name)
                child.Parent = newName;
                obj.Store.write(child, Overwrite=true)
            end

            if obj.Store.getSetting("DefaultProfile", "") == name
                obj.Store.setSetting("DefaultProfile", newName)
            end

            obj.Store.remove(name)
        end

        function deleteProfile(obj, name)
        %deleteProfile Delete a saved profile
            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
            end

            obj.assertIsUserProfile(name)

            children = obj.getChildProfiles(name);
            if ~isempty(children)
                error("NANSEN:Options:ProfileInUse", ...
                    "Can not delete ""%s"" because it is the parent of: %s", ...
                    name, strjoin([children.Name], ", "))
            end

            if obj.Store.getSetting("DefaultProfile", "") == name
                obj.Store.setSetting("DefaultProfile", "")
            end

            obj.Store.remove(name)
        end

        function setDefaultProfile(obj, name)
        %setDefaultProfile Set profile to use when no profile is specified
            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
            end
            if ~obj.hasProfile(name)
                error("NANSEN:Options:ProfileNotFound", "No profile named ""%s"" exists", name)
            end
            if name == obj.Schema.DEFAULTS_NAME; name = ""; end
            obj.Store.setSetting("DefaultProfile", name)
        end

        function exportProfile(obj, name, filePath)
        %exportProfile Export a profile to a JSON file (e.g. for sharing)
        %
        %   The exported file contains the fully resolved values, so it
        %   can be imported without the parent profiles.
            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
                filePath (1,1) string
            end

            profile = obj.getProfile(name);
            values = obj.resolveProfile(name, IsQuiet=true);

            exported = nansen.options.Profile(profile.Name, ...
                Description=profile.Description, ...
                MethodName=obj.MethodName, ...
                Overrides=nansen.options.internal.diffToStruct( ...
                    obj.Schema.getDefaults(), values), ...
                Tags=profile.Tags, ...
                SchemaVersion=obj.Schema.Version, ...
                DefaultsHash=obj.Schema.getDefaultsHash(), ...
                Snapshot=values, ...
                Created=profile.Created, ...
                Modified=datetime("now", "TimeZone", "UTC"), ...
                CreatedBy=profile.CreatedBy, ...
                NansenVersion=getNansenVersion());

            writelines(nansen.options.internal.jsonEncode(exported.toStruct()), filePath)
        end

        function profile = importProfile(obj, filePath, options)
        %importProfile Import a profile from a JSON file
        %
        %   profile = m.importProfile(filePath) imports a profile exported
        %   with exportProfile (or copied from another profile folder).
        %
        %   profile = m.importProfile(filePath, Name=newName) imports it
        %   with a new name.
            arguments
                obj (1,1) nansen.options.Manager
                filePath (1,1) string {mustBeFile}
                options.Name (1,1) string = ""
            end

            imported = nansen.options.Profile.fromStruct( ...
                nansen.options.internal.jsonDecode(fileread(filePath)));

            if imported.MethodName ~= "" && imported.MethodName ~= obj.MethodName
                error("NANSEN:Options:InvalidInput", ...
                    "Profile is for method ""%s"", not ""%s""", ...
                    imported.MethodName, obj.MethodName)
            end

            name = imported.Name;
            if options.Name ~= ""; name = options.Name; end

            % Values are migrated from the version the profile was saved with
            values = imported.Snapshot;
            if isempty(fieldnames(values)); values = imported.Overrides; end
            if imported.SchemaVersion ~= ""
                values = obj.Schema.migrate(values, imported.SchemaVersion);
            end
            values = obj.Schema.conform(values, Unknown="warn");

            profile = obj.createProfile(name, values, ...
                Description=imported.Description, Tags=imported.Tags, ...
                Frozen=imported.Frozen);
        end

        function [values, wasCanceled] = edit(obj, profileName)
        %edit Edit options interactively in the options editor
        %
        %   [values, wasCanceled] = m.edit(profileName) opens the options
        %   editor, where profiles can also be created, saved and managed.
        %   Returns the values that were selected when pressing OK.
        %
        %   See also nansen.options.ui.OptionsEditor
            arguments
                obj (1,1) nansen.options.Manager
                profileName (1,1) string = obj.DefaultProfileName
            end

            editor = nansen.options.ui.OptionsEditor(obj, Profile=profileName);
            [values, wasCanceled] = editor.waitForResult();
        end

        function imported = importLegacyOptions(obj, filePath)
        %importLegacyOptions Import custom options saved by nansen.manage.OptionsManager
        %
        %   imported = m.importLegacyOptions() imports all custom options
        %   that were saved with the legacy options manager as profiles,
        %   and returns the names of the imported profiles.
        %
        %   See also nansen.options.legacy.importOptionsFile
            arguments
                obj (1,1) nansen.options.Manager
                filePath (1,1) string = nansen.options.legacy.getOptionsFilePath(obj.MethodName)
            end
            imported = nansen.options.legacy.importOptionsFile(obj, filePath);
        end
    end

    methods % Set/get

        function name = get.MethodName(obj)
            name = obj.Schema.Name;
        end

        function names = get.ProfileNames(obj)
            names = [obj.Schema.DEFAULTS_NAME, obj.Schema.PresetNames, ...
                obj.UserProfileNames];
        end

        function names = get.UserProfileNames(obj)
            names = obj.Store.list();
        end

        function name = get.DefaultProfileName(obj)
            name = string(obj.Store.getSetting("DefaultProfile", ""));
            if name == "" || ~obj.hasProfile(name)
                name = obj.Schema.DEFAULTS_NAME;
            end
        end
    end

    methods (Access = private)

        function [values, sources, migrationLog] = resolveProfile(obj, name, options)
        %resolveProfile Resolve values of a profile by resolving its parents
            arguments
                obj (1,1) nansen.options.Manager
                name (1,1) string
                options.Visited (1,:) string = string.empty(1, 0)
                options.IsQuiet (1,1) logical = false
            end

            schema = obj.Schema;
            migrationLog = string.empty(1, 0);

            if name == schema.DEFAULTS_NAME
                values = schema.getDefaults();
                sources = markSources(struct(), values, "defaults");

            elseif schema.hasPreset(name)
                [values, sources] = obj.resolveProfile(schema.DEFAULTS_NAME);
                preset = schema.getPreset(name);
                values = schema.applyOverrides(values, preset.Overrides);
                sources = markSources(sources, preset.Overrides, "preset:" + name);

            elseif obj.Store.exists(name)
                if ismember(name, options.Visited)
                    error("NANSEN:Options:CyclicProfiles", ...
                        "Profiles have cyclic parents: %s", ...
                        strjoin([options.Visited, name], " -> "))
                end

                profile = obj.Store.read(name);
                [overrides, snapshot, migrationLog] = obj.migrateProfile(profile);

                parentName = profile.Parent;
                if parentName == ""; parentName = schema.DEFAULTS_NAME; end
                [values, sources, parentLog] = obj.resolveProfile(parentName, ...
                    Visited=[options.Visited, name], IsQuiet=options.IsQuiet);
                migrationLog = [parentLog, migrationLog];

                if profile.Frozen && ~isempty(fieldnames(snapshot))
                    values = schema.conform(snapshot, Unknown="drop");
                    sources = markSources(sources, snapshot, "profile:" + name + " (frozen)");
                else
                    values = schema.applyOverrides(values, overrides);
                    sources = markSources(sources, overrides, "profile:" + name);
                    if ~options.IsQuiet
                        obj.warnIfValuesChanged(profile, values, snapshot)
                    end
                end
            else
                error("NANSEN:Options:ProfileNotFound", ...
                    "No profile named ""%s"" exists for ""%s""", name, obj.MethodName)
            end
        end

        function [overrides, snapshot, migrationLog] = migrateProfile(obj, profile)
        %migrateProfile Migrate saved values of profile to current schema

            schema = obj.Schema;
            overrides = profile.Overrides;
            snapshot = profile.Snapshot;
            migrationLog = string.empty(1, 0);

            if profile.SchemaVersion ~= "" && nansen.options.internal.compareVersions( ...
                    profile.SchemaVersion, schema.Version) < 0
                [overrides, migrationLog] = schema.migrate(overrides, profile.SchemaVersion);
                snapshot = schema.migrate(snapshot, profile.SchemaVersion);
                migrationLog = "Profile """ + profile.Name + """: " + migrationLog;
            end

            % Remove overrides for parameters which no longer exist.
            obsoleteNames = setdiff(nansen.options.internal.flattenStruct(overrides), ...
                schema.ParameterNames, "stable");
            if ~isempty(obsoleteNames)
                warning("NANSEN:Options:ObsoleteParameter", ...
                    "Profile ""%s"" contains values for parameters that no longer " + ...
                    "exist and will be ignored: %s", profile.Name, strjoin(obsoleteNames, ", "))
                for obsoleteName = obsoleteNames
                    overrides = nansen.options.internal.removeValue(overrides, obsoleteName);
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
                snapshot = obj.Schema.conform(snapshot, Unknown="drop");
            catch
                return % Snapshot is no longer valid, i.e. schema changed
            end

            differences = nansen.options.internal.diffStruct(snapshot, values);
            if isempty(differences); return; end

            toText = @(values) string(cellfun(@nansen.options.internal.valueToString, ...
                values, UniformOutput=false));
            changes = "  " + differences.Name + ": " + toText(differences.ValueA) + ...
                " -> " + toText(differences.ValueB);

            warning("NANSEN:Options:InheritedValuesChanged", ...
                "Values of profile ""%s"" have changed since it was saved, because " + ...
                "defaults or a parent profile changed:\n%s\n" + ...
                "Use refreshProfile to accept the new values, updateProfile to " + ...
                "set explicit values, or make the profile Frozen to keep values fixed.", ...
                profile.Name, strjoin(changes', newline))
        end

        function [fullValues, overrides] = computeValuesAndOverrides(obj, values, parentName, baseValues)
        %computeValuesAndOverrides Get all values and overrides relative to parent

            if parentName == ""; parentName = obj.Schema.DEFAULTS_NAME; end
            parentValues = obj.resolveProfile(parentName, IsQuiet=true);

            if nargin < 4; baseValues = parentValues; end

            fullValues = obj.Schema.applyOverrides(baseValues, values);
            overrides = nansen.options.internal.diffToStruct(parentValues, fullValues);
        end

        function children = getChildProfiles(obj, name)
        %getChildProfiles Get saved profiles which have the given parent
            children = nansen.options.Profile.empty(1, 0);
            for profileName = obj.UserProfileNames
                profile = obj.Store.read(profileName);
                if profile.Parent == name
                    children(end+1) = profile; %#ok<AGROW>
                end
            end
        end

        function name = normalizeParentName(obj, name)
            if name == obj.Schema.DEFAULTS_NAME; name = ""; end
            if name ~= "" && ~obj.hasProfile(name)
                error("NANSEN:Options:ProfileNotFound", ...
                    "Parent profile ""%s"" does not exist", name)
            end
        end

        function assertValidNewProfileName(obj, name, allowOverwrite)
            if strcmpi(name, obj.Schema.DEFAULTS_NAME)
                error("NANSEN:Options:ReservedName", """%s"" is a reserved name", name)
            elseif obj.Schema.hasPreset(name)
                error("NANSEN:Options:ReservedName", ...
                    "A preset named ""%s"" already exists", name)
            elseif obj.Store.exists(name) && ~allowOverwrite
                error("NANSEN:Options:ProfileExists", ...
                    "A profile named ""%s"" already exists", name)
            end
        end

        function assertIsUserProfile(obj, name)
            if name == obj.Schema.DEFAULTS_NAME || obj.Schema.hasPreset(name)
                error("NANSEN:Options:ReadOnlyProfile", ...
                    """%s"" is defined in code and can not be modified", name)
            elseif ~obj.Store.exists(name)
                error("NANSEN:Options:ProfileNotFound", ...
                    "No profile named ""%s"" exists for ""%s""", name, obj.MethodName)
            end
        end

        function assertNoCycle(obj, name, parentName)
            visited = name;
            while parentName ~= "" && obj.Store.exists(parentName)
                if ismember(parentName, visited)
                    error("NANSEN:Options:CyclicProfiles", ...
                        "Setting parent to ""%s"" would create a cycle", parentName)
                end
                visited(end+1) = parentName; %#ok<AGROW>
                parentProfile = obj.Store.read(parentName);
                parentName = parentProfile.Parent;
            end
        end
    end

    methods (Static)
        function location = getDefaultLocation(methodName)
        %getDefaultLocation Get default folder for saving profiles
        %
        %   Profiles for methods that are part of NANSEN are saved in the
        %   user's local NANSEN folder, while profiles for methods that
        %   are part of a project are saved in the project folder.
            arguments
                methodName (1,1) string
            end

            filePath = string(which(methodName));
            isNansenMethod = contains(filePath, fullfile("code", "integrations", "sessionmethods")) ...
                || contains(filePath, "+nansen");

            if isNansenMethod
                folderPath = nansen.localpath('custom_options');
            else
                folderPath = nansen.localpath('project_custom_options');
            end
            location = string(fullfile(folderPath, "profiles"));
        end
    end
end

function sources = markSources(sources, values, sourceName)
%markSources Set source for all (leaf) values in values
    for name = nansen.options.internal.flattenStruct(values)
        sources = nansen.options.internal.setValue(sources, name, sourceName);
    end
end

function versionStr = getNansenVersion()
    try
        versionStr = string(nansen.version());
    catch
        versionStr = "";
    end
end
