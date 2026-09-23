classdef Profile
%nansen.options.Profile A named set of options for a method
%
%   A profile stores the values of a set of options which differ from its
%   parent (Overrides). The parent is either the defaults of the schema,
%   a preset (defined in code) or another profile. Storing only the
%   differences keeps profiles small, shows exactly what a user changed,
%   and lets profiles pick up new parameters automatically.
%
%   In addition, a profile keeps a Snapshot of all resolved values at the
%   time it was saved. The snapshot is used to detect if inherited values
%   have changed since (e.g. because the default value of a parameter was
%   changed in a newer version of NANSEN). If a profile is Frozen, the
%   snapshot is used as is, so the values never change unless the user
%   explicitly updates the profile.
%
%   Profiles are normally created and managed with nansen.options.Manager,
%   and saved as human readable JSON files by nansen.options.ProfileStore.
%
%   profile = nansen.options.Profile(name, Name=Value, ...) where Name can
%   be any public property.
%
%   See also nansen.options.Manager nansen.options.ProfileStore

    properties
        Name (1,1) string {nansen.options.internal.mustBeProfileName} = ""
        Description (1,1) string = ""
        MethodName (1,1) string = ""
        Type (1,1) nansen.options.ProfileType = nansen.options.ProfileType.User
        Parent (1,1) string = ""            % Name of parent profile or preset ("" = schema defaults)
        Overrides (1,1) struct = struct()   % Values that differ from parent (nested struct)
        Frozen (1,1) logical = false        % If true, values are taken from the Snapshot
        Tags (1,:) string = string.empty(1, 0)
        SchemaVersion (1,1) string = ""     % Version of schema profile was saved with
        DefaultsHash (1,1) string = ""      % Hash of schema defaults when profile was saved
        Snapshot (1,1) struct = struct()    % All values when profile was saved
        Created (1,1) datetime = datetime(NaN, NaN, NaN, TimeZone="UTC")
        Modified (1,1) datetime = datetime(NaN, NaN, NaN, TimeZone="UTC")
        CreatedBy (1,1) string = ""
        NansenVersion (1,1) string = ""     % Version of NANSEN profile was saved with
    end

    properties (Constant, Hidden)
        FORMAT_VERSION = "1.0"              % Version of the file format for profiles
    end

    properties (Dependent, SetAccess = private)
        IsReadOnly (1,1) logical            % Presets and defaults are defined in code
        OverrideNames (1,:) string          % (Dotted) names of overridden parameters
    end

    methods
        function obj = Profile(name, propertyValues)
            arguments
                name (1,1) string = ""
                propertyValues.?nansen.options.Profile
            end

            obj.Name = name;
            for propertyName = string(fieldnames(propertyValues))'
                obj.(propertyName) = propertyValues.(propertyName);
            end
        end

        function S = toStruct(obj)
        %toStruct Convert profile to a struct of plain values (e.g. for saving)
            arguments
                obj (1,1) nansen.options.Profile
            end

            S = struct();
            S.FormatVersion = obj.FORMAT_VERSION;
            S.Name = obj.Name;
            S.Description = obj.Description;
            S.MethodName = obj.MethodName;
            S.Type = string(obj.Type);
            S.Parent = obj.Parent;
            S.Frozen = obj.Frozen;
            if ~isempty(obj.Tags)
                S.Tags = obj.Tags;
            end
            S.SchemaVersion = obj.SchemaVersion;
            S.DefaultsHash = obj.DefaultsHash;
            S.Created = nansen.options.internal.formatTimestamp(obj.Created);
            S.Modified = nansen.options.internal.formatTimestamp(obj.Modified);
            S.CreatedBy = obj.CreatedBy;
            S.NansenVersion = obj.NansenVersion;
            S.Overrides = obj.Overrides;
            S.Snapshot = obj.Snapshot;
        end
    end

    methods % Get
        function tf = get.IsReadOnly(obj)
            tf = obj.Type ~= nansen.options.ProfileType.User;
        end

        function names = get.OverrideNames(obj)
            names = nansen.options.internal.flattenStruct(obj.Overrides);
        end
    end

    methods (Static)
        function obj = fromStruct(S)
        %fromStruct Create profile from a struct (see toStruct)
            arguments
                S (1,1) struct
            end

            obj = nansen.options.Profile(S.Name);

            textFields = ["Description", "MethodName", "Parent", ...
                "SchemaVersion", "DefaultsHash", "CreatedBy", "NansenVersion"];
            for name = textFields
                if isfield(S, name); obj.(name) = string(S.(name)); end
            end

            if isfield(S, "Type"); obj.Type = nansen.options.ProfileType.(S.Type); end
            if isfield(S, "Frozen"); obj.Frozen = logical(S.Frozen); end
            if isfield(S, "Tags"); obj.Tags = string(S.Tags); end
            if isfield(S, "Overrides"); obj.Overrides = S.Overrides; end
            if isfield(S, "Snapshot"); obj.Snapshot = S.Snapshot; end

            if isfield(S, "Created")
                obj.Created = nansen.options.internal.parseTimestamp(S.Created);
            end
            if isfield(S, "Modified")
                obj.Modified = nansen.options.internal.parseTimestamp(S.Modified);
            end
        end
    end
end
