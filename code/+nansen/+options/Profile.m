classdef Profile
%nansen.options.Profile A named set of options for a method
%
%   A profile stores the values of a set of options which differ from its
%   parent (Overrides). The parent is either the defaults of the schema,
%   a preset (defined in code) or another profile. Storing only the
%   differences keeps profiles small, makes it obvious what a user
%   changed, and lets profiles pick up new parameters automatically.
%
%   In addition, a profile keeps a Snapshot of all resolved values at the
%   time it was saved. The snapshot is used to detect if inherited values
%   have changed since (e.g. because the default value of a parameter was
%   changed in a newer version of NANSEN). If a profile is Frozen, the
%   snapshot is used as is, so the values never change unless the user
%   explicitly updates the profile.
%
%   Profiles are normally created and managed through nansen.options.Manager
%   and are saved as human readable JSON files by nansen.options.ProfileStore
%
%   See also nansen.options.Manager nansen.options.ProfileStore

    properties
        Name char = ''              % Name of profile
        Description char = ''       % Description of profile
        MethodName char = ''        % Name of method the profile belongs to
        Type char = 'user'          % 'user', 'preset' or 'defaults'
        Parent char = ''            % Name of parent profile or preset ('' = schema defaults)
        Overrides = struct()        % Values that differ from parent (nested struct)
        Frozen logical = false      % If true, values are taken from the Snapshot
        Tags = {}                   % Cell array of tags (for organizing profiles)
        SchemaVersion char = ''     % Version of schema profile was saved with
        DefaultsHash char = ''      % Hash of schema defaults when profile was saved
        Snapshot = struct()         % All values when profile was saved
        Created char = ''           % Time of creation (ISO 8601)
        Modified char = ''          % Time of last modification (ISO 8601)
        CreatedBy char = ''         % User who created profile
        NansenVersion char = ''     % Version of NANSEN profile was saved with
    end

    properties (Constant, Hidden)
        FORMAT_VERSION = '1.0'      % Version of the file format for profiles
    end

    methods
        function obj = Profile(name, varargin)
        %Profile Create a profile
        %
        %   profile = nansen.options.Profile(name, Name, Value, ...) where
        %   Name can be any property of the profile

            if nargin < 1; return; end
            obj.Name = char(name);

            for i = 1:2:numel(varargin)
                obj.(char(varargin{i})) = varargin{i+1};
            end
        end

        function names = getOverrideNames(obj)
        %getOverrideNames Get (dotted) names of parameters with overrides
            names = nansen.options.internal.flattenStruct(obj.Overrides);
        end

        function tf = isReadOnly(obj)
        %isReadOnly Presets and defaults are defined in code and read-only
            tf = any(strcmp(obj.Type, {'preset', 'defaults'}));
        end

        function S = toStruct(obj)
        %toStruct Convert profile to a struct (e.g. for saving)
            S = struct();
            S.FormatVersion = obj.FORMAT_VERSION;
            propertyNames = getSavedPropertyNames();
            for i = 1:numel(propertyNames)
                S.(propertyNames{i}) = obj.(propertyNames{i});
            end
            if isempty(S.Tags); S = rmfield(S, 'Tags'); end
        end
    end

    methods % Set methods
        function obj = set.Name(obj, value)
            value = strtrim(char(value));
            if ~isempty(value) && isempty(regexp(value, '^[\w][\w \-\.\(\)]*$', 'once'))
                error('NANSEN:Options:InvalidName', ...
                    ['Invalid profile name "%s". Use letters, numbers, spaces, ', ...
                    'underscores, dashes, dots and parentheses.'], value)
            end
            obj.Name = value;
        end

        function obj = set.Type(obj, value)
            obj.Type = validatestring(char(value), {'user', 'preset', 'defaults'});
        end

        function obj = set.Tags(obj, value)
            if ischar(value) || isstring(value); value = cellstr(value); end
            obj.Tags = reshape(value, 1, []);
        end

        function obj = set.Overrides(obj, value)
            if isempty(value); value = struct(); end
            obj.Overrides = value;
        end

        function obj = set.Snapshot(obj, value)
            if isempty(value); value = struct(); end
            obj.Snapshot = value;
        end
    end

    methods (Static)
        function obj = fromStruct(S)
        %fromStruct Create profile from a struct (see toStruct)
            obj = nansen.options.Profile();
            propertyNames = getSavedPropertyNames();
            for i = 1:numel(propertyNames)
                if isfield(S, propertyNames{i})
                    obj.(propertyNames{i}) = S.(propertyNames{i});
                end
            end
        end
    end
end

function names = getSavedPropertyNames()
    names = {'Name', 'Description', 'MethodName', 'Type', 'Parent', ...
        'Frozen', 'Tags', 'SchemaVersion', 'DefaultsHash', 'Created', ...
        'Modified', 'CreatedBy', 'NansenVersion', 'Overrides', 'Snapshot'};
end
