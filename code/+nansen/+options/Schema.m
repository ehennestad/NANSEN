classdef Schema < handle & matlab.mixin.CustomDisplay
%nansen.options.Schema Schema (definition) of the options for a method
%
%   A schema is the single source of truth for the options of a method:
%   which parameters exist, their default values, types, allowed values,
%   documentation and user interface hints. A schema also has a version,
%   and can define presets (named, developer-provided option profiles) and
%   migrations (functions that upgrade saved options from older schema
%   versions).
%
%   Schemas are defined in code, in a static method getOptionsSchema of a
%   method class (see nansen.options.getSchema).
%
%   USAGE:
%       schema = nansen.options.Schema("my.package.MyMethod", Version="1.0.0");
%
%       schema.addParameter("Preprocessing.binSize", 5, ...
%           Description="Number of frames to bin", Min=1, Integer=true)
%       schema.addParameter("Preprocessing.method", "mean", ...
%           Choices={"mean", "max"})
%       schema.addParameter("Run.numWorkers", 4, Transient=true)
%
%       schema.addPreset("Fast", {"binSize", 10}, Description="Quick previews")
%
%       opts = schema.getDefaults();        % Struct with default values
%       opts = schema.conform(opts);        % Validate / fill in missing
%
%   VERSIONING:
%       Increase the Version whenever defaults change, or parameters are
%       added, removed or renamed. Use addMigration to register a function
%       that converts options from an older version to a newer version,
%       e.g. when a parameter was renamed.
%
%   See also nansen.options.Parameter nansen.options.Manager
%            nansen.options.getSchema

    properties
        Name (1,1) string = ""              % Name of method the schema belongs to
        Version (1,1) string {nansen.options.internal.mustBeVersion} = "1.0.0"
        Title (1,1) string = ""             % Human readable title
        Description (1,1) string = ""       % Description of method/options
        Dependencies (1,:) string = string.empty(1, 0) % Functions/classes of external toolboxes whose versions are recorded in provenance
    end

    properties (SetAccess = private)
        Parameters (1,:) nansen.options.Parameter = nansen.options.Parameter.empty(1, 0)
        Presets (1,:) nansen.options.Profile = nansen.options.Profile.empty(1, 0)
        Migrations (1,:) nansen.options.Migration = nansen.options.Migration.empty(1, 0)
        GroupDescriptions (1,1) struct = struct()   % Descriptions of groups (nested like options)
        IsInferred (1,1) logical = false    % True if inferred from a legacy options definition
    end

    properties (Dependent, SetAccess = private)
        ParameterNames (1,:) string         % Names of all parameters
        PresetNames (1,:) string            % Names of all presets
        GroupNames (1,:) string             % Names of top level groups
        DisplayTitle (1,1) string           % Title, or name of method
    end

    properties (Constant)
        DEFAULTS_NAME = "Defaults"          % Reserved name for the defaults of a schema
    end

    methods % Constructor
        function obj = Schema(name, options)
        %Schema Create a new, empty options schema
        %
        %   schema = nansen.options.Schema(name, Name=Value, ...)
        %
        %   Name-value arguments: Version, Title, Description, Dependencies
            arguments
                name (1,1) string = ""
                options.Version (1,1) string {nansen.options.internal.mustBeVersion} = "1.0.0"
                options.Title (1,1) string = ""
                options.Description (1,1) string = ""
                options.Dependencies (1,:) string = string.empty(1, 0)
            end

            obj.Name = name;
            obj.Version = options.Version;
            obj.Title = options.Title;
            obj.Description = options.Description;
            obj.Dependencies = options.Dependencies;
        end
    end

    methods % Define parameters, presets and migrations

        function parameter = addParameter(obj, name, defaultValue, attributes)
        %addParameter Add a parameter to the schema
        %
        %   schema.addParameter(name, defaultValue, Name=Value, ...) adds a
        %   parameter. Use dotted names for parameters in a group, e.g.
        %   "Group.name". See nansen.options.Parameter for available
        %   attributes (Description, Units, Choices, Min, Max, ...)

            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
                defaultValue
                attributes.?nansen.options.Parameter
            end

            if obj.hasParameter(name)
                error("NANSEN:Options:DuplicateParameter", ...
                    "Parameter ""%s"" already exists in schema", name)
            end

            existingNames = obj.ParameterNames;
            isConflict = startsWith(existingNames, name + ".") | ...
                arrayfun(@(n) startsWith(name, n + "."), existingNames);
            if any(isConflict)
                error("NANSEN:Options:DuplicateParameter", ...
                    "Parameter ""%s"" conflicts with existing parameter ""%s""", ...
                    name, existingNames(find(isConflict, 1)))
            end

            attributeArgs = namedargs2cell(attributes);
            parameter = nansen.options.Parameter(name, defaultValue, attributeArgs{:});
            obj.Parameters(end+1) = parameter;

            if ~nargout; clear parameter; end
        end

        function removeParameter(obj, name)
        %removeParameter Remove a parameter from the schema
            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
            end
            obj.Parameters(obj.getParameterIndex(name)) = [];
        end

        function modifyParameter(obj, name, attributes)
        %modifyParameter Modify attributes (incl. Default) of a parameter
        %
        %   schema.modifyParameter(name, Name=Value, ...)
        %
        %   Example:
        %       schema.modifyParameter("binSize", Default=10, Max=50)

            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
                attributes.?nansen.options.Parameter
            end

            idx = obj.getParameterIndex(name);
            attributeArgs = namedargs2cell(attributes);
            obj.Parameters(idx) = obj.Parameters(idx).modify(attributeArgs{:});
        end

        function setDefault(obj, name, value)
        %setDefault Set default value of a parameter
            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
                value
            end
            obj.modifyParameter(name, Default=value)
        end

        function setGroupDescription(obj, groupName, description)
        %setGroupDescription Set description for a group of parameters
            arguments
                obj (1,1) nansen.options.Schema
                groupName (1,1) string
                description (1,1) string
            end
            obj.GroupDescriptions = nansen.options.internal.setValue( ...
                obj.GroupDescriptions, groupName, description);
        end

        function description = getGroupDescription(obj, groupName)
        %getGroupDescription Get description of a group of parameters
            arguments
                obj (1,1) nansen.options.Schema
                groupName (1,1) string
            end
            description = "";
            if nansen.options.internal.hasValue(obj.GroupDescriptions, groupName)
                value = nansen.options.internal.getValue(obj.GroupDescriptions, groupName);
                if isstring(value); description = value; end
            end
        end

        function addPreset(obj, name, overrides, options)
        %addPreset Add a preset (named set of values) to the schema
        %
        %   schema.addPreset(name, overrides) adds a preset. overrides is a
        %   (partial) nested struct with values that differ from defaults,
        %   or a cell array of name-value pairs (short or dotted names).
        %
        %   schema.addPreset(name, overrides, Description=text)

            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string {mustBeNonzeroLengthText}
                overrides {mustBeA(overrides, ["struct", "cell"])} = struct()
                options.Description (1,1) string = ""
            end

            if strcmpi(name, obj.DEFAULTS_NAME)
                error("NANSEN:Options:ReservedName", """%s"" is a reserved name", name)
            elseif obj.hasPreset(name)
                error("NANSEN:Options:DuplicatePreset", ...
                    "A preset named ""%s"" already exists", name)
            end

            overrides = obj.parseOverrides(overrides);
            obj.applyOverrides(obj.getDefaults(), overrides); % Validates values

            obj.Presets(end+1) = nansen.options.Profile(name, ...
                Type=nansen.options.ProfileType.Preset, ...
                MethodName=obj.Name, ...
                Description=options.Description, ...
                Overrides=overrides, ...
                SchemaVersion=obj.Version);
        end

        function addMigration(obj, fromVersion, toVersion, migrationFcn, options)
        %addMigration Add a function that migrates options between versions
        %
        %   schema.addMigration(fromVersion, toVersion, migrationFcn)
        %   registers a function which converts options from one version of
        %   the schema to a later version. See nansen.options.Migration.
        %
        %   Example:
        %       schema.addMigration("1.0.0", "2.0.0", ...
        %           @(S) nansen.options.migrate.renameField(S, "binSize", "Preprocessing.binSize"), ...
        %           Description="Moved binSize to Preprocessing")

            arguments
                obj (1,1) nansen.options.Schema
                fromVersion (1,1) string
                toVersion (1,1) string
                migrationFcn (1,1) function_handle
                options.Description (1,1) string = ""
            end

            obj.Migrations(end+1) = nansen.options.Migration(fromVersion, ...
                toVersion, migrationFcn, Description=options.Description);
        end
    end

    methods % Query parameters and presets

        function tf = hasParameter(obj, name)
            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
            end
            tf = any(obj.ParameterNames == name);
        end

        function parameter = getParameter(obj, name)
        %getParameter Get parameter by (full or unique short) name
            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
            end
            parameter = obj.Parameters(obj.getParameterIndex(name));
        end

        function parameters = getGroupParameters(obj, groupName)
        %getGroupParameters Get all parameters in a group (incl. subgroups)
            arguments
                obj (1,1) nansen.options.Schema
                groupName (1,1) string
            end
            if groupName == ""
                parameters = obj.Parameters(~contains(obj.ParameterNames, "."));
            else
                parameters = obj.Parameters(startsWith(obj.ParameterNames, groupName + "."));
            end
        end

        function fullName = resolveName(obj, name)
        %resolveName Resolve a (possibly short) parameter name to a full name
        %
        %   fullName = schema.resolveName(name) returns the full (dotted)
        %   name of a parameter. If name is not a full name, it is matched
        %   against the end of full names (e.g. "binSize" matches
        %   "Preprocessing.binSize") if the match is unique.

            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
            end

            allNames = obj.ParameterNames;
            if any(allNames == name)
                fullName = name; return
            end

            isMatch = endsWith(allNames, "." + name);

            if sum(isMatch) == 1
                fullName = allNames(isMatch);
            elseif sum(isMatch) > 1
                error("NANSEN:Options:AmbiguousName", ...
                    "Parameter name ""%s"" is ambiguous. Matches: %s", ...
                    name, strjoin(allNames(isMatch), ", "))
            else
                error("NANSEN:Options:UnknownParameter", ...
                    "Schema ""%s"" has no parameter named ""%s""", obj.Name, name)
            end
        end

        function tf = hasPreset(obj, name)
            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
            end
            tf = any(obj.PresetNames == name);
        end

        function preset = getPreset(obj, name)
        %getPreset Get a preset (as a nansen.options.Profile)
            arguments
                obj (1,1) nansen.options.Schema
                name (1,1) string
            end
            isMatch = obj.PresetNames == name;
            if ~any(isMatch)
                error("NANSEN:Options:PresetNotFound", ...
                    "Schema ""%s"" has no preset named ""%s""", obj.Name, name)
            end
            preset = obj.Presets(isMatch);
        end
    end

    methods % Work with option values

        function S = getDefaults(obj)
        %getDefaults Get struct with the default values of all parameters
            arguments
                obj (1,1) nansen.options.Schema
            end
            S = struct();
            for parameter = obj.Parameters
                S = nansen.options.internal.setValue(S, parameter.Name, parameter.Default);
            end
        end

        function S = getPresetValues(obj, presetName)
        %getPresetValues Get all values (defaults + overrides) of a preset
            arguments
                obj (1,1) nansen.options.Schema
                presetName (1,1) string
            end
            preset = obj.getPreset(presetName);
            S = obj.applyOverrides(obj.getDefaults(), preset.Overrides);
        end

        function overrides = parseOverrides(obj, overrides)
        %parseOverrides Convert overrides to a nested struct with full names
        %
        %   Overrides can be given as a (nested, partial) struct or as a
        %   cell array of name-value pairs. Short names are resolved to
        %   full names.

            arguments
                obj (1,1) nansen.options.Schema
                overrides {mustBeA(overrides, ["struct", "cell"])}
            end

            if iscell(overrides)
                if mod(numel(overrides), 2) ~= 0
                    error("NANSEN:Options:InvalidInput", ...
                        "Overrides must be given as name-value pairs")
                end
                names = string(overrides(1:2:end));
                values = overrides(2:2:end);
            else
                [names, values] = nansen.options.internal.flattenStruct(overrides);
            end

            overrides = struct();
            for i = 1:numel(names)
                overrides = nansen.options.internal.setValue(overrides, ...
                    obj.resolveName(names(i)), values{i});
            end
        end

        function S = applyOverrides(obj, S, overrides)
        %applyOverrides Apply (validated) overrides to a struct of options
        %
        %   S = schema.applyOverrides(S, overrides) where overrides is a
        %   nested struct (can be partial) or a cell array of name-value
        %   pairs. Throws an error if any value is invalid.

            arguments
                obj (1,1) nansen.options.Schema
                S (1,1) struct
                overrides {mustBeA(overrides, ["struct", "cell"])}
            end

            [names, values] = nansen.options.internal.flattenStruct( ...
                obj.parseOverrides(overrides));

            for i = 1:numel(names)
                parameter = obj.getParameter(names(i));
                value = parameter.coerce(values{i});
                [isValid, message] = parameter.validate(value);
                if ~isValid
                    error("NANSEN:Options:InvalidValue", ...
                        "Invalid value for ""%s"": %s", names(i), message)
                end
                S = nansen.options.internal.setValue(S, names(i), value);
            end
        end

        function [isValid, issues] = validate(obj, S)
        %validate Validate a struct of options against the schema
        %
        %   [isValid, issues] = schema.validate(S) returns true if S is
        %   valid. issues is a table with variables Name, Issue ("missing",
        %   "unknown" or "invalid") and Message.

            arguments
                obj (1,1) nansen.options.Schema
                S (1,1) struct
            end

            [names, values] = nansen.options.internal.flattenStruct(S);
            issues = createIssuesTable();

            for parameter = obj.Parameters
                [isPresent, idx] = ismember(parameter.Name, names);
                if ~isPresent
                    issues(end+1, :) = {parameter.Name, "missing", "Parameter is missing"}; %#ok<AGROW>
                else
                    [isParameterValid, message] = parameter.validate(values{idx});
                    if ~isParameterValid
                        issues(end+1, :) = {parameter.Name, "invalid", message}; %#ok<AGROW>
                    end
                end
            end

            for name = setdiff(names, obj.ParameterNames, "stable")
                issues(end+1, :) = {name, "unknown", "Parameter is not part of schema"}; %#ok<AGROW>
            end

            isValid = isempty(issues);
        end

        function [S, issues] = conform(obj, S, options)
        %conform Make a struct of options conform to the schema
        %
        %   S = schema.conform(S) converts values to the expected class and
        %   shape, fills in missing parameters with default values and
        %   validates all values. An error is thrown if any values are
        %   invalid or if S contains fields that are not in the schema.
        %
        %   [S, issues] = schema.conform(S, Name=Value)
        %
        %   NAME-VALUE ARGUMENTS:
        %       Unknown : How to handle fields not in the schema:
        %                 "error" (default), "warn" (and drop), "drop" or "keep"
        %       Missing : How to handle missing parameters:
        %                 "fill" (default, use default value) or "error"

            arguments
                obj (1,1) nansen.options.Schema
                S (1,1) struct
                options.Unknown (1,1) string {mustBeMember(options.Unknown, ["error", "warn", "drop", "keep"])} = "error"
                options.Missing (1,1) string {mustBeMember(options.Missing, ["fill", "error"])} = "fill"
            end

            [names, values] = nansen.options.internal.flattenStruct(S);

            conformed = struct();
            issues = createIssuesTable();

            for parameter = obj.Parameters
                [isPresent, idx] = ismember(parameter.Name, names);

                if isPresent
                    value = parameter.coerce(values{idx});
                    [isValid, message] = parameter.validate(value);
                    if ~isValid
                        error("NANSEN:Options:InvalidValue", ...
                            "Invalid value for ""%s"": %s", parameter.Name, message)
                    end
                elseif options.Missing == "error"
                    error("NANSEN:Options:MissingValue", ...
                        "Missing value for parameter ""%s""", parameter.Name)
                else
                    value = parameter.Default;
                    issues(end+1, :) = {parameter.Name, "missing", ...
                        "Filled in with default value"}; %#ok<AGROW>
                end
                conformed = nansen.options.internal.setValue(conformed, parameter.Name, value);
            end

            unknownNames = setdiff(names, obj.ParameterNames, "stable");
            if ~isempty(unknownNames)
                for name = unknownNames
                    issues(end+1, :) = {name, "unknown", "Parameter is not part of schema"}; %#ok<AGROW>
                end

                switch options.Unknown
                    case "error"
                        error("NANSEN:Options:UnknownParameter", ...
                            "Options contain parameters that are not part of the schema ""%s"": %s", ...
                            obj.Name, strjoin(unknownNames, ", "))
                    case "warn"
                        warning("NANSEN:Options:UnknownParameter", ...
                            "Ignoring parameters that are not part of the schema ""%s"": %s", ...
                            obj.Name, strjoin(unknownNames, ", "))
                    case "keep"
                        [~, idx] = ismember(unknownNames, names);
                        for i = 1:numel(unknownNames)
                            conformed = nansen.options.internal.setValue( ...
                                conformed, unknownNames(i), values{idx(i)});
                        end
                end
            end

            S = conformed;
        end

        function [S, migrationLog] = migrate(obj, S, fromVersion)
        %migrate Migrate options from an older version of the schema
        %
        %   [S, migrationLog] = schema.migrate(S, fromVersion) applies all
        %   registered migrations from fromVersion up to the current schema
        %   version. migrationLog is a string array describing the applied
        %   migrations.

            arguments
                obj (1,1) nansen.options.Schema
                S (1,1) struct
                fromVersion (1,1) string
            end

            migrationLog = string.empty(1, 0);
            currentVersion = fromVersion;
            compare = @nansen.options.internal.compareVersions;

            if compare(currentVersion, obj.Version) > 0
                warning("NANSEN:Options:NewerVersion", ...
                    "Options were created with a newer version (%s) of " + ...
                    "the schema for ""%s"" than the current version (%s)", ...
                    currentVersion, obj.Name, obj.Version)
                return
            end

            while compare(currentVersion, obj.Version) < 0
                % Find the migration which applies to the current version,
                % i.e. starts at or before it and ends after it. If there
                % are several, use the one with the smallest step.
                isCandidate = arrayfun(@(m) compare(m.FromVersion, currentVersion) <= 0 ...
                    && compare(m.ToVersion, currentVersion) > 0, obj.Migrations);
                candidates = obj.Migrations(isCandidate);

                if isempty(candidates); break; end

                isSmallest = arrayfun(@(m) all(arrayfun(@(c) ...
                    compare(m.ToVersion, c.ToVersion) <= 0, candidates)), candidates);
                migration = candidates(find(isSmallest, 1));

                S = migration.apply(S);
                migrationLog(end+1) = migration.describe(); %#ok<AGROW>
                currentVersion = migration.ToVersion;
            end
        end

        function S = getHashableValues(obj, S)
        %getHashableValues Remove transient parameters from options
            arguments
                obj (1,1) nansen.options.Schema
                S (1,1) struct
            end
            for parameter = obj.Parameters([obj.Parameters.Transient])
                S = nansen.options.internal.removeValue(S, parameter.Name);
            end
        end

        function hash = computeHash(obj, S)
        %computeHash Compute fingerprint of a (conformed) struct of options
        %
        %   The hash is computed from the method name and the values of
        %   all non-transient parameters. Two runs of a method with the
        %   same hash used the same configuration.
            arguments
                obj (1,1) nansen.options.Schema
                S (1,1) struct
            end
            hash = nansen.options.internal.computeHash( ...
                struct("Method", obj.Name, "Options", obj.getHashableValues(S)) );
        end

        function hash = getDefaultsHash(obj)
        %getDefaultsHash Get hash of default values (to detect changes)
            arguments
                obj (1,1) nansen.options.Schema
            end
            hash = nansen.options.internal.computeHash(obj.getDefaults());
        end
    end

    methods % Documentation and export

        function T = toTable(obj, options)
        %toTable Get a table with an overview of all parameters
        %
        %   T = schema.toTable(IncludeInternal=false)
            arguments
                obj (1,1) nansen.options.Schema
                options.IncludeInternal (1,1) logical = false
            end

            parameters = obj.Parameters;
            if ~options.IncludeInternal
                parameters = parameters(~[parameters.Internal]);
            end

            Name = [string.empty(0, 1); parameters.Name];
            Default = string(arrayfun(@(p) nansen.options.internal.valueToString(p.Default), ...
                parameters(:), UniformOutput=false));
            Type = [nansen.options.ParameterType.empty(0, 1); parameters.Type];
            Units = [string.empty(0, 1); parameters.Units];
            Description = [string.empty(0, 1); parameters.Description];

            if isempty(parameters)
                Default = string.empty(0, 1);
            end

            T = table(Name, Default, Type, Units, Description);
        end

        function S = toJsonSchema(obj)
        %toJsonSchema Get a JSON Schema (https://json-schema.org) description
        %
        %   The returned struct can be written to file with jsonencode, or
        %   use schema.writeJsonSchema(filePath). This makes the options
        %   understandable by other tools and languages (e.g. Python).
            arguments
                obj (1,1) nansen.options.Schema
            end

            propertyStruct = struct();
            for parameter = obj.Parameters
                propertyStruct = addJsonSchemaProperty(propertyStruct, ...
                    split(parameter.Name, ".")', parameter.toJsonSchema());
            end

            % Use a dictionary-like map to allow keys like "$schema"
            S = containers.Map();
            S("$schema") = "https://json-schema.org/draft/2020-12/schema";
            S("$id") = obj.Name;
            S("title") = obj.DisplayTitle;
            if obj.Description ~= ""; S("description") = obj.Description; end
            S("version") = obj.Version;
            S("type") = "object";
            S("properties") = propertyStruct;
        end

        function writeJsonSchema(obj, filePath)
        %writeJsonSchema Write JSON Schema description to file
            arguments
                obj (1,1) nansen.options.Schema
                filePath (1,1) string
            end
            writelines(jsonencode(obj.toJsonSchema(), PrettyPrint=true), filePath)
        end
    end

    methods % Set/get

        function names = get.ParameterNames(obj)
            names = [string.empty(1, 0), obj.Parameters.Name];
        end

        function names = get.PresetNames(obj)
            names = [string.empty(1, 0), obj.Presets.Name];
        end

        function names = get.GroupNames(obj)
            names = obj.ParameterNames(contains(obj.ParameterNames, "."));
            names = unique(extractBefore(names, "."), "stable");
        end

        function title = get.DisplayTitle(obj)
            if obj.Title ~= ""
                title = obj.Title;
            else
                nameParts = split(obj.Name, ".");
                title = nameParts(end);
            end
        end
    end

    methods (Hidden)
        function markAsInferred(obj)
        %markAsInferred Mark schema as inferred from a legacy definition
            obj.IsInferred = true;
        end
    end
    
    methods (Access = protected) % Custom display

        function header = getHeader(obj)
            if ~isscalar(obj)
                header = getHeader@matlab.mixin.CustomDisplay(obj); return
            end
            header = sprintf("  Options schema for <strong>%s</strong> (version %s)\n", ...
                obj.DisplayTitle, obj.Version);
            if obj.Description ~= ""
                header = header + sprintf("  %s\n", obj.Description);
            end
            if obj.IsInferred
                header = header + sprintf("  (Inferred from legacy options definition)\n");
            end
            header = char(header);
        end

        function displayScalarObject(obj)
            fprintf("%s\n", obj.getHeader())
            if ~isempty(obj.Parameters)
                disp(obj.toTable())
            end
            if ~isempty(obj.Presets)
                fprintf("  Presets: %s\n\n", strjoin(obj.PresetNames, ", "))
            end
        end
    end

    methods (Access = private)
        function idx = getParameterIndex(obj, name)
            idx = find(obj.ParameterNames == obj.resolveName(name));
        end
    end
end

function issues = createIssuesTable()
    issues = table('Size', [0, 3], ...
        'VariableTypes', ["string", "string", "string"], ...
        'VariableNames', ["Name", "Issue", "Message"]);
end

function S = addJsonSchemaProperty(S, nameParts, property)
    if isscalar(nameParts)
        S.(nameParts(1)) = property;
    else
        if ~isfield(S, nameParts(1))
            S.(nameParts(1)) = struct("type", "object", "properties", struct());
        end
        S.(nameParts(1)).properties = addJsonSchemaProperty( ...
            S.(nameParts(1)).properties, nameParts(2:end), property);
    end
end
