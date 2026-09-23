classdef OptionsRecord
%nansen.options.OptionsRecord Record of the options used to run a method
%
%   An options record is meant to be saved together with the results of a
%   method. It contains everything needed to know how a result was made:
%
%       - The complete, resolved values of all options (not only the ones
%         that differ from defaults, since defaults can change over time)
%       - Where each value came from (defaults, preset, profile or given
%         at runtime)
%       - The name and version of the method's options schema
%       - A hash (fingerprint) of the options, excluding transient
%         parameters, which can be used to quickly check whether two
%         results were produced with the same configuration
%       - Provenance: versions of NANSEN, MATLAB and dependencies
%
%   Records can be converted to plain structs (toStruct) for saving in
%   MAT files, so they can be loaded without NANSEN, or written to JSON.
%
%   USAGE:
%       [opts, record] = optionsManager.resolve('My profile');
%       ... run method ...
%       S = record.toStruct();   % save alongside results
%
%       record = nansen.options.OptionsRecord.fromStruct(S);
%       differences = record.compare(otherRecord)
%
%   See also nansen.options.Manager nansen.options.Provenance

    properties
        MethodName char = ''        % Name of method
        ProfileName char = ''       % Name of profile the options were resolved from
        SchemaVersion char = ''     % Version of options schema
        Values = struct()           % Resolved values of all options
        RuntimeOverrides = struct() % Values that were given at runtime
        Sources = struct()          % Source of each value (same structure as Values)
        Hash char = ''              % Fingerprint of (non-transient) values
        Created char = ''           % Time of creation (ISO 8601)
        MigrationLog = {}           % Migrations applied to saved values
        Provenance = struct()       % See nansen.options.Provenance
    end

    properties (Constant, Hidden)
        FORMAT_VERSION = '1.0'
    end

    methods
        function S = toStruct(obj)
        %toStruct Convert record to a plain struct (e.g. for saving)
            S = struct();
            S.FormatVersion = obj.FORMAT_VERSION;
            names = getSavedPropertyNames();
            for i = 1:numel(names)
                S.(names{i}) = obj.(names{i});
            end
        end

        function writeJson(obj, filePath)
        %writeJson Write record to a JSON file
            jsonStr = nansen.options.internal.jsonEncode(obj.toStruct());
            fid = fopen(filePath, 'w', 'n', 'UTF-8');
            if fid == -1
                error('NANSEN:Options:FileError', 'Could not write to "%s"', filePath)
            end
            fprintf(fid, '%s', jsonStr);
            fclose(fid);
        end

        function differences = compare(obj, other)
        %compare Compare values with another record (or struct of options)
        %
        %   differences = record.compare(otherRecord) returns a struct
        %   array with fields Name, ValueA, ValueB and Change for each
        %   option value that differs.

            if isa(other, 'nansen.options.OptionsRecord')
                otherValues = other.Values;
            else
                otherValues = other;
            end
            differences = nansen.options.internal.diffStruct(obj.Values, otherValues);
        end

        function tf = isEquivalent(obj, other)
        %isEquivalent Check if two records have the same (non-transient) options
            tf = strcmp(obj.MethodName, other.MethodName) && ...
                ~isempty(obj.Hash) && strcmp(obj.Hash, other.Hash);
        end

        function source = getSource(obj, parameterName)
        %getSource Get where the value of a parameter came from
            if nansen.options.internal.hasValue(obj.Sources, parameterName)
                source = nansen.options.internal.getValue(obj.Sources, parameterName);
            else
                source = '';
            end
        end
    end

    methods (Static)

        function obj = create(schema, values, varargin)
        %create Create a record for a resolved set of options
        %
        %   record = nansen.options.OptionsRecord.create(schema, values, Name, Value)
        %
        %   NAME-VALUE PAIRS:
        %       ProfileName       : Name of profile
        %       RuntimeOverrides  : Struct with values given at runtime
        %       Sources           : Struct with source of each value
        %       MigrationLog      : Cell array of applied migrations
        %       CaptureProvenance : Whether to capture provenance (default true)

            params = struct('ProfileName', '', 'RuntimeOverrides', struct(), ...
                'Sources', struct(), ...
                'MigrationLog', {{}}, 'CaptureProvenance', true);
            for i = 1:2:numel(varargin)
                name = validatestring(char(varargin{i}), fieldnames(params));
                params.(name) = varargin{i+1};
            end

            obj = nansen.options.OptionsRecord();
            obj.MethodName = schema.Name;
            obj.ProfileName = params.ProfileName;
            obj.SchemaVersion = schema.Version;
            obj.Values = values;
            obj.RuntimeOverrides = params.RuntimeOverrides;
            obj.Sources = params.Sources;
            obj.MigrationLog = params.MigrationLog;
            obj.Hash = schema.computeHash(values);
            obj.Created = nansen.options.internal.isoTimestamp();

            if params.CaptureProvenance
                obj.Provenance = nansen.options.Provenance.capture( ...
                    'MethodName', schema.Name, ...
                    'Dependencies', schema.Dependencies);
            end
        end

        function obj = fromStruct(S)
        %fromStruct Create record from a struct (see toStruct)
            obj = nansen.options.OptionsRecord();
            names = getSavedPropertyNames();
            for i = 1:numel(names)
                if isfield(S, names{i})
                    obj.(names{i}) = S.(names{i});
                end
            end
        end

        function obj = readJson(filePath)
        %readJson Read record from a JSON file
            S = nansen.options.internal.jsonDecode(fileread(filePath));
            obj = nansen.options.OptionsRecord.fromStruct(S);
        end
    end
end

function names = getSavedPropertyNames()
    names = {'MethodName', 'ProfileName', 'SchemaVersion', 'Hash', ...
        'Created', 'Values', 'RuntimeOverrides', 'Sources', ...
        'MigrationLog', 'Provenance'};
end
