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
%       [opts, record] = optionsManager.resolve("My profile");
%       ... run method ...
%       record.writeJson(fullfile(outputFolder, "options.json"))
%
%       record = nansen.options.OptionsRecord.readJson(filePath);
%       differences = record.compare(otherRecord)
%
%   See also nansen.options.Manager nansen.options.Provenance

    properties (SetAccess = private)
        MethodName (1,1) string = ""        % Name of method
        ProfileName (1,1) string = ""       % Name of profile the options were resolved from
        SchemaVersion (1,1) string = ""     % Version of options schema
        Values (1,1) struct = struct()      % Resolved values of all options
        RuntimeOverrides (1,1) struct = struct() % Values that were given at runtime
        Sources (1,1) struct = struct()     % Source of each value (same structure as Values)
        Hash (1,1) string = ""              % Fingerprint of (non-transient) values
        Created (1,1) datetime = datetime(NaN, NaN, NaN, TimeZone="UTC")
        MigrationLog (1,:) string = string.empty(1, 0) % Migrations applied to saved values
        Provenance nansen.options.Provenance {mustBeScalarOrEmpty} = nansen.options.Provenance.empty
    end

    properties (Constant, Hidden)
        FORMAT_VERSION = "1.0"
    end

    methods
        function S = toStruct(obj)
        %toStruct Convert record to a struct of plain values (e.g. for saving)
            arguments
                obj (1,1) nansen.options.OptionsRecord
            end
            S = struct();
            S.FormatVersion = obj.FORMAT_VERSION;
            S.MethodName = obj.MethodName;
            S.ProfileName = obj.ProfileName;
            S.SchemaVersion = obj.SchemaVersion;
            S.Hash = obj.Hash;
            S.Created = nansen.options.internal.formatTimestamp(obj.Created);
            S.Values = obj.Values;
            S.RuntimeOverrides = obj.RuntimeOverrides;
            S.Sources = obj.Sources;
            S.MigrationLog = obj.MigrationLog;
            if ~isempty(obj.Provenance)
                S.Provenance = obj.Provenance.toStruct();
            end
        end

        function writeJson(obj, filePath)
        %writeJson Write record to a JSON file
            arguments
                obj (1,1) nansen.options.OptionsRecord
                filePath (1,1) string
            end
            writelines(nansen.options.internal.jsonEncode(obj.toStruct()), filePath)
        end

        function differences = compare(obj, other)
        %compare Compare values with another record (or struct of options)
        %
        %   differences = record.compare(otherRecord) returns a table with
        %   variables Name, ValueA, ValueB and Change for each option value
        %   that differs.
            arguments
                obj (1,1) nansen.options.OptionsRecord
                other (1,1) {mustBeA(other, ["nansen.options.OptionsRecord", "struct"])}
            end
            if isa(other, "nansen.options.OptionsRecord")
                other = other.Values;
            end
            differences = nansen.options.internal.diffStruct(obj.Values, other);
        end

        function tf = isEquivalent(obj, other)
        %isEquivalent Check if two records have the same (non-transient) options
            arguments
                obj (1,1) nansen.options.OptionsRecord
                other (1,1) nansen.options.OptionsRecord
            end
            tf = obj.MethodName == other.MethodName && ...
                obj.Hash ~= "" && obj.Hash == other.Hash;
        end

        function source = getSource(obj, parameterName)
        %getSource Get where the value of a parameter came from
        %
        %   source = record.getSource(parameterName) returns "defaults",
        %   "preset:<name>", "profile:<name>" or "runtime".
            arguments
                obj (1,1) nansen.options.OptionsRecord
                parameterName (1,1) string
            end
            source = "";
            if nansen.options.internal.hasValue(obj.Sources, parameterName)
                source = string(nansen.options.internal.getValue(obj.Sources, parameterName));
            end
        end
    end

    methods (Static)

        function obj = create(schema, values, options)
        %create Create a record for a resolved set of options
        %
        %   record = nansen.options.OptionsRecord.create(schema, values, Name=Value)
        %
        %   NAME-VALUE ARGUMENTS:
        %       ProfileName       : Name of profile
        %       RuntimeOverrides  : Struct with values given at runtime
        %       Sources           : Struct with source of each value
        %       MigrationLog      : Migrations applied to saved values
        %       CaptureProvenance : Whether to capture provenance (default true)
            arguments
                schema (1,1) nansen.options.Schema
                values (1,1) struct
                options.ProfileName (1,1) string = ""
                options.RuntimeOverrides (1,1) struct = struct()
                options.Sources (1,1) struct = struct()
                options.MigrationLog (1,:) string = string.empty(1, 0)
                options.CaptureProvenance (1,1) logical = true
            end

            obj = nansen.options.OptionsRecord();
            obj.MethodName = schema.Name;
            obj.ProfileName = options.ProfileName;
            obj.SchemaVersion = schema.Version;
            obj.Values = values;
            obj.RuntimeOverrides = options.RuntimeOverrides;
            obj.Sources = options.Sources;
            obj.MigrationLog = options.MigrationLog;
            obj.Hash = schema.computeHash(values);
            obj.Created = datetime("now", "TimeZone", "UTC");

            if options.CaptureProvenance
                obj.Provenance = nansen.options.Provenance.capture( ...
                    MethodName=schema.Name, Dependencies=schema.Dependencies);
            end
        end

        function obj = fromStruct(S)
        %fromStruct Create record from a struct (see toStruct)
            arguments
                S (1,1) struct
            end
            obj = nansen.options.OptionsRecord();
            for name = ["MethodName", "ProfileName", "SchemaVersion", "Hash"]
                if isfield(S, name); obj.(name) = string(S.(name)); end
            end
            for name = ["Values", "RuntimeOverrides", "Sources"]
                if isfield(S, name); obj.(name) = S.(name); end
            end
            if isfield(S, "MigrationLog") && ~isempty(S.MigrationLog)
                obj.MigrationLog = reshape(string(S.MigrationLog), 1, []);
            end
            if isfield(S, "Created")
                obj.Created = nansen.options.internal.parseTimestamp(S.Created);
            end
            if isfield(S, "Provenance")
                obj.Provenance = nansen.options.Provenance.fromStruct(S.Provenance);
            end
        end

        function obj = readJson(filePath)
        %readJson Read record from a JSON file
            arguments
                filePath (1,1) string {mustBeFile}
            end
            S = nansen.options.internal.jsonDecode(fileread(filePath));
            obj = nansen.options.OptionsRecord.fromStruct(S);
        end
    end
end
