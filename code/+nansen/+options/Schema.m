classdef Schema < handle
%nansen.options.Schema Schema (definition) of the options for a method
%
%   A schema is the single source of truth for the options of a method:
%   which parameters exist, their default values, types, allowed values,
%   documentation and user interface hints. A schema also has a version,
%   and can define presets (named, developer-provided option profiles) and
%   migrations (functions that upgrade saved options from older schema
%   versions).
%
%   Schemas are defined in code, e.g. in a static method getOptionsSchema
%   of a method class (see nansen.options.getSchema for conventions).
%
%   USAGE:
%       schema = nansen.options.Schema('my.package.myMethod', 'Version', '1.0.0');
%
%       schema.addParameter('Preprocessing.binSize', 5, ...
%           'Description', 'Number of frames to bin', 'Min', 1, 'Integer', true)
%       schema.addParameter('Preprocessing.method', 'mean', ...
%           'Choices', {'mean', 'max'})
%       schema.addParameter('Run.numWorkers', 4, 'Transient', true)
%
%       schema.addPreset('Fast', struct('Preprocessing', struct('binSize', 10)), ...
%           'Heavy binning for quick previews')
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
        Name char = ''              % Name of method/function the schema belongs to
        Version char = '1.0.0'      % Semantic version of the schema
        Title char = ''             % Human readable title
        Description char = ''       % Description of method/options
        Dependencies cell = {}      % Names of functions/classes from external toolboxes whose versions should be recorded in provenance
    end

    properties (SetAccess = private)
        Presets = struct('Name', {}, 'Description', {}, 'Overrides', {})
        Migrations = struct('FromVersion', {}, 'ToVersion', {}, ...
            'Function', {}, 'Description', {})
        GroupDescriptions = struct('Name', {}, 'Description', {})
        IsInferred logical = false  % True if schema was inferred from a legacy struct of options
    end

    properties (Dependent)
        Parameters                  % Array of parameters (nansen.options.Parameter)
        ParameterNames              % Names of all parameters
        PresetNames                 % Names of all presets
        NumParameters               % Number of parameters
    end

    properties (Constant)
        DEFAULTS_PROFILE_NAME = 'Defaults' % Reserved name for the defaults of a schema
    end

    properties (Access = private)
        ParameterList = {}          % Cell array of parameters
    end

    methods % Constructor
        function obj = Schema(name, varargin)
        %Schema Create a new, empty options schema
        %
        %   schema = nansen.options.Schema(name, Name, Value, ...)
        %
        %   Name-value pairs: Version, Title, Description, Dependencies

            if nargin < 1; return; end
            obj.Name = char(name);

            for i = 1:2:numel(varargin)
                propertyName = validatestring(char(varargin{i}), ...
                    {'Version', 'Title', 'Description', 'Dependencies'});
                obj.(propertyName) = varargin{i+1};
            end
        end
    end

    methods % Define parameters

        function parameter = addParameter(obj, name, defaultValue, varargin)
        %addParameter Add a parameter to the schema
        %
        %   schema.addParameter(name, defaultValue, Name, Value, ...) adds a
        %   parameter. Use dotted names for parameters in a group, e.g.
        %   'Group.name'. See nansen.options.Parameter for available
        %   name-value pairs (Description, Units, Choices, Min, Max, ...)

            name = char(name);

            if obj.hasParameter(name)
                error('NANSEN:Options:DuplicateParameter', ...
                    'Parameter "%s" already exists in schema', name)
            end

            existingNames = obj.ParameterNames;
            isConflict = strncmp(existingNames, [name, '.'], numel(name)+1) | ...
                cellfun(@(n) strncmp(name, [n, '.'], numel(n)+1), existingNames);
            if any(isConflict)
                error('NANSEN:Options:DuplicateParameter', ...
                    'Parameter "%s" conflicts with existing parameter "%s"', ...
                    name, existingNames{find(isConflict, 1)})
            end

            parameter = nansen.options.Parameter(name, defaultValue, varargin{:});
            obj.ParameterList{end+1} = parameter;

            if ~nargout; clear parameter; end
        end

        function removeParameter(obj, name)
        %removeParameter Remove a parameter from the schema
            idx = obj.getParameterIndex(name);
            obj.ParameterList(idx) = [];
        end

        function modifyParameter(obj, name, varargin)
        %modifyParameter Modify attributes (incl. Default) of a parameter
        %
        %   schema.modifyParameter(name, Name, Value, ...)
        %
        %   Example:
        %       schema.modifyParameter('binSize', 'Default', 10, 'Max', 50)

            idx = obj.getParameterIndex(name);
            obj.ParameterList{idx} = obj.ParameterList{idx}.modify(varargin{:});
        end

        function setDefault(obj, name, value)
        %setDefault Set default value of a parameter
            obj.modifyParameter(name, 'Default', value)
        end

        function setGroupDescription(obj, groupName, description)
        %setGroupDescription Set description for a group of parameters
            idx = find(strcmp({obj.GroupDescriptions.Name}, groupName));
            if isempty(idx); idx = numel(obj.GroupDescriptions) + 1; end
            obj.GroupDescriptions(idx).Name = char(groupName);
            obj.GroupDescriptions(idx).Description = char(description);
        end

        function addPreset(obj, name, overrides, description)
        %addPreset Add a preset (named set of values) to the schema
        %
        %   schema.addPreset(name, overrides) adds a preset. overrides is a
        %   (partial) nested struct with values that differ from defaults,
        %   or a cell array of name-value pairs with dotted names.
        %
        %   schema.addPreset(name, overrides, description)

            if nargin < 4; description = ''; end
            name = char(name);

            if strcmpi(name, obj.DEFAULTS_PROFILE_NAME)
                error('NANSEN:Options:ReservedName', ...
                    '"%s" is a reserved name', name)
            elseif obj.hasPreset(name)
                error('NANSEN:Options:DuplicatePreset', ...
                    'A preset named "%s" already exists', name)
            end

            overrides = obj.parseOverrides(overrides);

            % Validate values of the preset
            obj.applyOverrides(obj.getDefaults(), overrides);

            obj.Presets(end+1) = struct('Name', name, ...
                'Description', char(description), 'Overrides', overrides);
        end

        function addMigration(obj, fromVersion, toVersion, migrationFcn, description)
        %addMigration Add a function that migrates options between versions
        %
        %   schema.addMigration(fromVersion, toVersion, migrationFcn)
        %   registers a function which converts options from one version of
        %   the schema to a later version. The function receives a struct
        %   of options, and must return the converted struct.
        %
        %   Note: The struct can be partial (e.g. only values of a profile
        %   that differ from defaults), so migration functions should only
        %   modify fields that are present. See nansen.options.migrate for
        %   helper functions.
        %
        %   Example:
        %       schema.addMigration('1.0.0', '1.1.0', ...
        %           @(S) nansen.options.migrate.renameField(S, 'binSize', 'Preprocessing.binSize'))

            if nargin < 5; description = ''; end

            assert(isa(migrationFcn, 'function_handle'), ...
                'NANSEN:Options:InvalidInput', 'Migration must be a function handle')
            assert(nansen.options.internal.compareVersions(toVersion, fromVersion) > 0, ...
                'NANSEN:Options:InvalidInput', 'toVersion must be greater than fromVersion')

            obj.Migrations(end+1) = struct('FromVersion', char(fromVersion), ...
                'ToVersion', char(toVersion), 'Function', migrationFcn, ...
                'Description', char(description));
        end
    end

    methods % Query parameters

        function tf = hasParameter(obj, name)
            tf = any(strcmp(obj.ParameterNames, name));
        end

        function parameter = getParameter(obj, name)
            parameter = obj.ParameterList{obj.getParameterIndex(name)};
        end

        function fullName = resolveName(obj, name)
        %resolveName Resolve a (possibly short) parameter name to a full name
        %
        %   fullName = schema.resolveName(name) returns the full (dotted)
        %   name of a parameter. If name is not a full name, it is matched
        %   against names without group (e.g. 'binSize' matches
        %   'Preprocessing.binSize') if the match is unique.

            name = char(name);
            if obj.hasParameter(name)
                fullName = name; return
            end

            shortNames = cellfun(@(p) p.ShortName, obj.ParameterList, 'UniformOutput', false);
            isMatch = strcmp(shortNames, name);

            % Also match partial paths, i.e 'B.c' for 'A.B.c'
            if ~any(isMatch)
                isMatch = cellfun(@(n) numel(n) > numel(name) && ...
                    strcmp(n(end-numel(name):end), ['.', name]), obj.ParameterNames);
            end

            if sum(isMatch) == 1
                fullName = obj.ParameterList{isMatch}.Name;
            elseif sum(isMatch) > 1
                error('NANSEN:Options:AmbiguousName', ...
                    'Parameter name "%s" is ambiguous. Matches: %s', ...
                    name, strjoin(obj.ParameterNames(isMatch), ', '))
            else
                error('NANSEN:Options:UnknownParameter', ...
                    'Schema "%s" has no parameter named "%s"', obj.Name, name)
            end
        end

        function tf = hasPreset(obj, name)
            tf = any(strcmp(obj.PresetNames, name));
        end

        function preset = getPreset(obj, name)
        %getPreset Get preset (struct with Name, Description and Overrides)
            isMatch = strcmp(obj.PresetNames, name);
            if ~any(isMatch)
                error('NANSEN:Options:PresetNotFound', ...
                    'Schema "%s" has no preset named "%s"', obj.Name, name)
            end
            preset = obj.Presets(isMatch);
        end
    end

    methods % Work with option values

        function S = getDefaults(obj)
        %getDefaults Get struct with the default values of all parameters
            S = struct();
            for i = 1:numel(obj.ParameterList)
                S = nansen.options.internal.setValue(S, ...
                    obj.ParameterList{i}.Name, obj.ParameterList{i}.Default);
            end
        end

        function S = getPresetValues(obj, presetName)
        %getPresetValues Get all values (defaults + overrides) of a preset
            preset = obj.getPreset(presetName);
            S = obj.applyOverrides(obj.getDefaults(), preset.Overrides);
        end

        function overrides = parseOverrides(obj, overrides)
        %parseOverrides Convert overrides to a nested struct with full names
        %
        %   Overrides can be given as a (nested) struct or as a cell array
        %   of name-value pairs. Short names are resolved to full names.

            if isempty(overrides)
                overrides = struct(); return
            end

            if iscell(overrides)
                assert(mod(numel(overrides), 2) == 0, ...
                    'NANSEN:Options:InvalidInput', ...
                    'Overrides must be given as name-value pairs')
                names = cellfun(@char, overrides(1:2:end), 'UniformOutput', false);
                values = overrides(2:2:end);
            elseif isstruct(overrides)
                overrides = obj.removeEditorConfigFields(overrides);
                [names, values] = nansen.options.internal.flattenStruct(overrides);
            else
                error('NANSEN:Options:InvalidInput', ...
                    'Overrides must be a struct or a cell array of name-value pairs')
            end

            overrides = struct();
            for i = 1:numel(names)
                fullName = obj.resolveName(names{i});
                overrides = nansen.options.internal.setValue(overrides, fullName, values{i});
            end
        end

        function S = applyOverrides(obj, S, overrides)
        %applyOverrides Apply (validated) overrides to a struct of options
        %
        %   S = schema.applyOverrides(S, overrides) where overrides is a
        %   nested struct (can be partial) or a cell array of name-value
        %   pairs. Throws an error if any value is invalid.

            overrides = obj.parseOverrides(overrides);
            [names, values] = nansen.options.internal.flattenStruct(overrides);

            for i = 1:numel(names)
                parameter = obj.getParameter(names{i});
                value = parameter.coerce(values{i});
                [isValid, message] = parameter.validate(value);
                if ~isValid
                    error('NANSEN:Options:InvalidValue', ...
                        'Invalid value for "%s": %s', names{i}, message)
                end
                S = nansen.options.internal.setValue(S, names{i}, value);
            end
        end

        function [isValid, issues] = validate(obj, S)
        %validate Validate a struct of options against the schema
        %
        %   [isValid, issues] = schema.validate(S) returns true if S is
        %   valid. issues is a struct array with fields Name, Type
        %   ('missing', 'unknown' or 'invalid') and Message.

            issues = struct('Name', {}, 'Type', {}, 'Message', {});

            S = obj.removeEditorConfigFields(S);
            [names, values] = nansen.options.internal.flattenStruct(S);

            for i = 1:numel(obj.ParameterList)
                parameter = obj.ParameterList{i};
                [isPresent, idx] = ismember(parameter.Name, names);
                if ~isPresent
                    issues(end+1) = struct('Name', parameter.Name, ...
                        'Type', 'missing', 'Message', 'Parameter is missing'); %#ok<AGROW>
                else
                    [isParamValid, message] = parameter.validate(values{idx});
                    if ~isParamValid
                        issues(end+1) = struct('Name', parameter.Name, ...
                            'Type', 'invalid', 'Message', message); %#ok<AGROW>
                    end
                end
            end

            unknownNames = setdiff(names, obj.ParameterNames, 'stable');
            for i = 1:numel(unknownNames)
                issues(end+1) = struct('Name', unknownNames{i}, ...
                    'Type', 'unknown', 'Message', 'Parameter is not part of schema'); %#ok<AGROW>
            end

            isValid = isempty(issues);
        end

        function [S, issues] = conform(obj, S, varargin)
        %conform Make a struct of options conform to the schema
        %
        %   S = schema.conform(S) converts values to the expected class and
        %   shape, fills in missing parameters with default values and
        %   validates all values. An error is thrown if any values are
        %   invalid or if S contains fields that are not in the schema.
        %
        %   [S, issues] = schema.conform(S, Name, Value)
        %
        %   NAME-VALUE PAIRS:
        %       Unknown : How to handle fields not in the schema:
        %                 'error' (default), 'warn' (and drop), 'drop' or 'keep'
        %       Missing : How to handle missing parameters:
        %                 'fill' (default, use default value) or 'error'

            params = struct('Unknown', 'error', 'Missing', 'fill');
            params = parseNameValuePairs(params, varargin{:});

            if isempty(S); S = struct(); end
            S = obj.removeEditorConfigFields(S);
            [names, values] = nansen.options.internal.flattenStruct(S);

            conformed = struct();
            issues = struct('Name', {}, 'Type', {}, 'Message', {});

            for i = 1:numel(obj.ParameterList)
                parameter = obj.ParameterList{i};
                [isPresent, idx] = ismember(parameter.Name, names);

                if isPresent
                    value = parameter.coerce(values{idx});
                    [isValid, message] = parameter.validate(value);
                    if ~isValid
                        error('NANSEN:Options:InvalidValue', ...
                            'Invalid value for "%s": %s', parameter.Name, message)
                    end
                elseif strcmp(params.Missing, 'error')
                    error('NANSEN:Options:MissingValue', ...
                        'Missing value for parameter "%s"', parameter.Name)
                else
                    value = parameter.Default;
                    issues(end+1) = struct('Name', parameter.Name, 'Type', 'missing', ...
                        'Message', 'Filled in with default value'); %#ok<AGROW>
                end
                conformed = nansen.options.internal.setValue(conformed, parameter.Name, value);
            end

            unknownNames = setdiff(names, obj.ParameterNames, 'stable');
            if ~isempty(unknownNames)
                for i = 1:numel(unknownNames)
                    issues(end+1) = struct('Name', unknownNames{i}, 'Type', 'unknown', ...
                        'Message', 'Parameter is not part of schema'); %#ok<AGROW>
                end

                switch params.Unknown
                    case 'error'
                        error('NANSEN:Options:UnknownParameter', ...
                            'Options contain parameters that are not part of the schema "%s": %s', ...
                            obj.Name, strjoin(unknownNames, ', '))
                    case 'warn'
                        warning('NANSEN:Options:UnknownParameter', ...
                            'Ignoring parameters that are not part of the schema "%s": %s', ...
                            obj.Name, strjoin(unknownNames, ', '))
                    case 'keep'
                        [~, idx] = ismember(unknownNames, names);
                        for i = 1:numel(unknownNames)
                            conformed = nansen.options.internal.setValue( ...
                                conformed, unknownNames{i}, values{idx(i)});
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
        %   version. migrationLog is a cell array of text describing the
        %   applied migrations.

            migrationLog = {};
            currentVersion = char(fromVersion);
            compare = @nansen.options.internal.compareVersions;

            if compare(currentVersion, obj.Version) > 0
                warning('NANSEN:Options:NewerVersion', ...
                    ['Options were created with a newer version (%s) of ', ...
                    'the schema for "%s" than the current version (%s)'], ...
                    currentVersion, obj.Name, obj.Version)
                return
            end

            while compare(currentVersion, obj.Version) < 0
                % Find the migration which starts at the current version
                % (or the closest earlier version)
                candidates = find(arrayfun(@(m) compare(m.FromVersion, currentVersion) <= 0 ...
                    && compare(m.ToVersion, currentVersion) > 0, obj.Migrations));

                if isempty(candidates); break; end

                [~, order] = sort(arrayfun(@(m) compare(m.ToVersion, currentVersion), ...
                    obj.Migrations(candidates)));
                migration = obj.Migrations(candidates(order(1)));

                S = migration.Function(S);
                migrationLog{end+1} = sprintf('%s -> %s: %s', migration.FromVersion, ...
                    migration.ToVersion, migration.Description); %#ok<AGROW>
                currentVersion = migration.ToVersion;
            end
        end

        function S = getHashableValues(obj, S)
        %getHashableValues Remove transient parameters from options
            for i = 1:numel(obj.ParameterList)
                if obj.ParameterList{i}.Transient
                    S = nansen.options.internal.removeValue(S, obj.ParameterList{i}.Name);
                end
            end
        end

        function hash = computeHash(obj, S)
        %computeHash Compute fingerprint of a (conformed) struct of options
        %
        %   The hash is computed from the method name and the values of
        %   all non-transient parameters. Two runs of a method with the
        %   same hash used the same configuration.

            S = obj.getHashableValues(S);
            hash = nansen.options.internal.computeHash( ...
                struct('Method', obj.Name, 'Options', S) );
        end

        function hash = getDefaultsHash(obj)
        %getDefaultsHash Get hash of default values
        %
        %   Used to detect whether default values have changed.
            hash = nansen.options.internal.computeHash(obj.getDefaults());
        end
    end

    methods % Conversion

        function S = toEditorStruct(obj, S, includeAdvanced)
        %toEditorStruct Create struct for editing in the structeditor app
        %
        %   S = schema.toEditorStruct(S) adds configuration fields
        %   (fieldname_) which the structeditor app uses to show dropdowns,
        %   sliders, file browsers etc. S defaults to the default values.
        %
        %   This is also the format expected by the legacy
        %   nansen.manage.OptionsManager.

            if nargin < 2 || isempty(S); S = obj.getDefaults(); end
            if nargin < 3; includeAdvanced = true; end

            for i = 1:numel(obj.ParameterList)
                parameter = obj.ParameterList{i};
                config = parameter.getEditorConfig();

                if parameter.Advanced && ~includeAdvanced
                    config = 'internal';
                end

                if ~isempty(config)
                    S = nansen.options.internal.setValue(S, [parameter.Name, '_'], config);
                end
            end
        end

        function S = fromEditorStruct(obj, S)
        %fromEditorStruct Remove configuration fields and conform
            S = obj.conform(obj.removeEditorConfigFields(S));
        end

        function T = toTable(obj, includeInternal)
        %toTable Get a table with an overview of all parameters

            if nargin < 2; includeInternal = false; end

            parameters = reshape(obj.ParameterList, [], 1);
            if ~includeInternal
                parameters = parameters(~cellfun(@(p) p.Internal, parameters));
            end

            getAttribute = @(name) cellfun(@(p) p.(name), parameters, 'UniformOutput', false);

            Name = getAttribute('Name');
            Default = cellfun(@(p) nansen.options.internal.valueToString(p.Default), ...
                parameters, 'UniformOutput', false);
            Type = getAttribute('Type');
            Units = getAttribute('Units');
            Description = getAttribute('Description');

            T = table(Name, Default, Type, Units, Description);
        end

        function S = toJsonSchema(obj)
        %toJsonSchema Get a JSON Schema (https://json-schema.org) description
        %
        %   The returned containers.Map can be written to file with
        %   jsonencode, or use schema.writeJsonSchema(filePath). This
        %   makes the options understandable by other tools (e.g. Python).

            S = containers.Map();
            S('$schema') = 'https://json-schema.org/draft/2020-12/schema';
            S('$id') = obj.Name;
            S('title') = obj.getDisplayTitle();
            if ~isempty(obj.Description); S('description') = obj.Description; end
            S('version') = obj.Version;
            S('type') = 'object';

            propertyStruct = struct();
            for i = 1:numel(obj.ParameterList)
                parameter = obj.ParameterList{i};
                propertyStruct = addJsonSchemaProperty(propertyStruct, ...
                    strsplit(parameter.Name, '.'), parameter.toJsonSchema());
            end
            S('properties') = propertyStruct;
        end

        function writeJsonSchema(obj, filePath)
        %writeJsonSchema Write JSON Schema description to file
            try
                jsonStr = jsonencode(obj.toJsonSchema(), 'PrettyPrint', true);
            catch
                jsonStr = jsonencode(obj.toJsonSchema());
            end
            writeTextFile(filePath, jsonStr)
        end

        function title = getDisplayTitle(obj)
            if ~isempty(obj.Title)
                title = obj.Title;
            else
                nameParts = strsplit(obj.Name, '.');
                title = nameParts{end};
            end
        end

        function disp(obj)
            if numel(obj) ~= 1 || ~isvalid(obj)
                builtin('disp', obj); return
            end
            fprintf('  Options schema for "%s" (version %s)\n', obj.Name, obj.Version)
            if ~isempty(obj.Description)
                fprintf('  %s\n', obj.Description)
            end
            if obj.IsInferred
                fprintf('  (Inferred from legacy options definition)\n')
            end
            fprintf('\n')
            if ~isempty(obj.ParameterList)
                try
                    disp(obj.toTable())
                catch % E.g if tables are not supported
                    fprintf('  Parameters: %s\n', strjoin(obj.ParameterNames, ', '))
                end
            end
            if ~isempty(obj.Presets)
                fprintf('  Presets: %s\n\n', strjoin(obj.PresetNames, ', '))
            end
        end
    end

    methods % Set/get

        function parameters = get.Parameters(obj)
            if isempty(obj.ParameterList)
                parameters = nansen.options.Parameter.empty;
            else
                parameters = [obj.ParameterList{:}];
            end
        end

        function names = get.ParameterNames(obj)
            names = cellfun(@(p) p.Name, obj.ParameterList, 'UniformOutput', false);
            names = reshape(names, 1, []);
        end

        function names = get.PresetNames(obj)
            names = reshape({obj.Presets.Name}, 1, []);
        end

        function n = get.NumParameters(obj)
            n = numel(obj.ParameterList);
        end

        function set.Version(obj, value)
            value = char(value);
            assert(~isempty(regexp(value, '^\d+(\.\d+)*$', 'once')), ...
                'NANSEN:Options:InvalidVersion', ...
                'Version must be a version string like "1.0.0"')
            obj.Version = value;
        end
    end

    methods (Access = private)
        function idx = getParameterIndex(obj, name)
            idx = find(strcmp(obj.ParameterNames, obj.resolveName(name)));
        end
    end

    methods (Static)

        function obj = fromStruct(S, name, varargin)
        %fromStruct Infer a schema from a (legacy) struct of default options
        %
        %   schema = nansen.options.Schema.fromStruct(S, name) creates a
        %   schema where the default values are taken from S. Configuration
        %   fields (fieldname_) used by the structeditor app are converted
        %   to parameter attributes (choices, widgets, internal/transient).
        %
        %   schema = nansen.options.Schema.fromStruct(S, name, Name, Value)
        %
        %   NAME-VALUE PAIRS:
        %       Version      : Schema version (default '1.0.0')
        %       Descriptions : containers.Map with descriptions per
        %                      parameter name (see parseParameterComments)
        %       Validators   : Struct with validation functions (same
        %                      structure as S), e.g. the V struct of legacy
        %                      getDefaultParameters functions.

            if nargin < 2; name = ''; end

            params = struct('Version', '1.0.0', 'Descriptions', [], 'Validators', []);
            params = parseNameValuePairs(params, varargin{:});

            obj = nansen.options.Schema(name, 'Version', params.Version);
            obj.IsInferred = true;

            [configNames, configValues] = collectEditorConfigFields(S, '');
            S = nansen.options.Schema.removeEditorConfigFields(S);
            [names, values] = nansen.options.internal.flattenStruct(S);

            for i = 1:numel(names)
                attributes = {};

                [hasConfig, idx] = ismember([names{i}, '_'], configNames);
                if hasConfig
                    attributes = configToAttributes(configValues{idx}, values{i});
                end

                if isa(params.Descriptions, 'containers.Map') && ...
                        isKey(params.Descriptions, names{i})
                    attributes = [attributes, {'Description', params.Descriptions(names{i})}]; %#ok<AGROW>
                end

                if isstruct(params.Validators) && ...
                        nansen.options.internal.hasValue(params.Validators, names{i})
                    validatorFcn = nansen.options.internal.getValue(params.Validators, names{i});
                    if isa(validatorFcn, 'function_handle')
                        attributes = [attributes, {'Validator', validatorFcn}]; %#ok<AGROW>
                    end
                end

                try
                    obj.addParameter(names{i}, values{i}, attributes{:});
                catch ME
                    % If an inferred attribute is incompatible with default
                    % value (e.g. choices not including the default),
                    % fall back to adding the parameter without attributes
                    warning('NANSEN:Options:InferenceProblem', ...
                        'Could not infer attributes for "%s": %s', names{i}, ME.message)
                    obj.addParameter(names{i}, values{i});
                end
            end
        end

        function S = removeEditorConfigFields(S)
        %removeEditorConfigFields Remove structeditor configuration fields
        %
        %   Removes all fields ending with "_" (e.g. "name_") at any level
        %   of a nested struct.

            if ~isstruct(S) || ~isscalar(S); return; end

            fields = fieldnames(S);
            for i = 1:numel(fields)
                if strcmp(fields{i}(end), '_')
                    S = rmfield(S, fields{i});
                elseif nansen.options.internal.isGroup(S.(fields{i}))
                    S.(fields{i}) = nansen.options.Schema.removeEditorConfigFields(S.(fields{i}));
                end
            end
        end
    end
end

function [names, values] = collectEditorConfigFields(S, prefix)
%collectEditorConfigFields Get (dotted) names and values of config fields
    names = {}; values = {};
    fields = fieldnames(S);
    for i = 1:numel(fields)
        name = fields{i};
        if ~isempty(prefix); name = [prefix, '.', name]; end %#ok<AGROW>
        
        if strcmp(fields{i}(end), '_')
            names{end+1} = name; %#ok<AGROW>
            values{end+1} = S.(fields{i}); %#ok<AGROW>
        elseif nansen.options.internal.isGroup(S.(fields{i}))
            [subNames, subValues] = collectEditorConfigFields(S.(fields{i}), name);
            names = [names, subNames]; %#ok<AGROW>
            values = [values, subValues]; %#ok<AGROW>
        end
    end
end

function attributes = configToAttributes(config, defaultValue)
%configToAttributes Convert structeditor config field value to attributes

    attributes = {};

    if iscell(config)
        if ischar(defaultValue) || isnumeric(defaultValue)
            attributes = {'Choices', config};
        end
    elseif ischar(config)
        switch config
            case {'internal', 'ignore'}
                attributes = {'Internal', true};
            case 'transient'
                attributes = {'Transient', true};
            otherwise
                attributes = {'Widget', config};
        end
    elseif isstruct(config) && isfield(config, 'type')
        attributes = {'Widget', config};
        if strcmp(config.type, 'slider') && isfield(config, 'args')
            args = config.args;
            for i = 1:2:numel(args)-1
                if any(strcmpi(args{i}, {'Min', 'Max'}))
                    attributes = [attributes, {args{i}, args{i+1}}]; %#ok<AGROW>
                end
            end
        end
    elseif isa(config, 'function_handle')
        attributes = {'Widget', config};
    end
end

function S = addJsonSchemaProperty(S, nameParts, property)
    if numel(nameParts) == 1
        S.(nameParts{1}) = property;
    else
        if ~isfield(S, nameParts{1})
            S.(nameParts{1}) = struct('type', 'object', 'properties', struct());
        end
        S.(nameParts{1}).properties = addJsonSchemaProperty( ...
            S.(nameParts{1}).properties, nameParts(2:end), property);
    end
end

function params = parseNameValuePairs(params, varargin)
    names = fieldnames(params);
    for i = 1:2:numel(varargin)
        name = validatestring(char(varargin{i}), names);
        params.(name) = varargin{i+1};
    end
end

function writeTextFile(filePath, text)
    fid = fopen(filePath, 'w', 'n', 'UTF-8');
    if fid == -1
        error('NANSEN:Options:FileError', 'Could not open file "%s" for writing', filePath)
    end
    cleanupObj = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', text);
end
