classdef Parameter
%nansen.options.Parameter Definition of a single parameter in an options schema
%
%   A Parameter describes one field of an options struct: its name,
%   default value, data type, allowed values and documentation, as well as
%   metadata that controls how it is displayed in user interfaces and
%   whether it contributes to the fingerprint (hash) of an options set.
%
%   Parameters are normally created through nansen.options.Schema/addParameter.
%
%   p = nansen.options.Parameter(name, defaultValue, Name, Value, ...)
%
%   INPUTS:
%       name         : Name of parameter. Use dots for parameters that
%                      belong to a group, e.g. 'Preprocessing.binSize'
%       defaultValue : Default value of parameter. The class of the
%                      default value determines the class of the parameter.
%
%   NAME-VALUE PAIRS (all optional):
%       Description : Text describing what the parameter does.
%       Units       : Unit of the parameter value, e.g. 's' or 'pixels'.
%       Label       : Short human readable label for user interfaces.
%       Choices     : Cell array of allowed values (enumeration).
%       Min, Max    : Inclusive numeric bounds.
%       Integer     : true if value must be integer valued.
%       Size        : Required size, e.g. [1 1] for scalars. NaN in a
%                     dimension means any length, e.g. [1 NaN] for row vectors.
%       Validator   : Function handle which either returns false or throws
%                     an error if a value is invalid (e.g. @mustBePositive).
%       Widget      : User interface hint for the options editor, e.g.
%                     'slider', 'uigetdir', 'uigetfile', 'multilinechar'.
%       Transient   : true if the parameter does not affect the result of
%                     a method (e.g. verbosity or number of workers).
%                     Transient parameters are excluded from options hashes.
%       Internal    : true if the parameter should be hidden from users.
%       Advanced    : true if the parameter is only shown in advanced views.
%       Since       : Schema version where the parameter was introduced.
%       Deprecated  : Text explaining why parameter is deprecated/what
%                     to use instead. Empty if not deprecated.
%
%   See also nansen.options.Schema

    properties
        Name char = ''              % Full (dotted) name of parameter
        Default = []                % Default value
        Description char = ''       % Description of parameter
        Units char = ''             % Units of parameter value
        Label char = ''             % Label to show in user interfaces
        Choices cell = {}           % Allowed values (if enumeration)
        Min double = -inf           % Minimum value (numeric parameters)
        Max double = inf            % Maximum value (numeric parameters)
        Integer logical = false     % Whether value must be integer valued
        Size double = []            % Required size of value
        Validator = []              % Custom validation function
        Widget = ''                 % User interface hint
        Transient logical = false   % Parameter does not affect results
        Internal logical = false    % Parameter is hidden from users
        Advanced logical = false    % Parameter is an advanced setting
        Since char = ''             % Schema version parameter was added in
        Deprecated char = ''        % Deprecation message
    end

    properties (SetAccess = private)
        Class char = ''             % Class of value (from default value)
    end

    properties (Dependent)
        Type                        % Type of parameter (derived)
        GroupName                   % Name of group (derived from name)
        ShortName                   % Name without group (derived from name)
    end

    properties (Constant, Hidden)
        NUMERIC_CLASSES = {'double', 'single', 'int8', 'uint8', 'int16', ...
            'uint16', 'int32', 'uint32', 'int64', 'uint64'}
    end

    methods % Constructor

        function obj = Parameter(name, defaultValue, varargin)

            if nargin == 0; return; end

            name = char(name);
            nansen.options.Parameter.validateName(name)

            obj.Name = name;
            obj.Default = nansen.options.Parameter.normalizeValue(defaultValue);
            obj.Class = class(obj.Default);

            obj = obj.applyNameValuePairs(varargin{:});
            obj.assertValidDefault()
        end
    end

    methods

        function obj = modify(obj, varargin)
        %modify Modify attributes of the parameter
        %
        %   p = p.modify(Name, Value, ...) modifies attributes of the
        %   parameter. Accepts the same name-value pairs as the
        %   constructor, and additionally 'Default'.

            [defaultValue, varargin] = popNameValue(varargin, 'Default');

            if ~isempty(defaultValue)
                obj.Default = nansen.options.Parameter.normalizeValue(defaultValue{1});
                obj.Class = class(obj.Default);
            end

            obj = obj.applyNameValuePairs(varargin{:});
            obj.assertValidDefault()
        end

        function [isValid, message] = validate(obj, value)
        %validate Check if a value is valid for this parameter
        %
        %   [isValid, message] = p.validate(value) returns true if value is
        %   valid. If not, message contains a description of the problem.

            message = '';
            value = nansen.options.Parameter.normalizeValue(value);

            switch obj.Type
                case 'logical'
                    isValid = islogical(value) || ( isnumeric(value) && ...
                        all(value(:) == 0 | value(:) == 1) );
                    if ~isValid; message = 'Value must be logical (true/false)'; end
                case 'numeric'
                    isValid = isnumeric(value) && isreal(value);
                    if ~isValid; message = 'Value must be numeric'; end
                case 'text'
                    isValid = ischar(value) && (isrow(value) || isempty(value));
                    if ~isValid; message = 'Value must be a character vector'; end
                case 'list'
                    isValid = iscell(value);
                    if ~isValid; message = 'Value must be a cell array'; end
                case 'function'
                    isValid = isa(value, 'function_handle') || ...
                        (ischar(value) && ~isempty(value));
                    if ~isValid; message = 'Value must be a function handle or function name'; end
                case 'choice'
                    isValid = obj.isValidChoice(value);
                    if ~isValid
                        message = sprintf('Value must be one of: %s', ...
                            nansen.options.internal.valueToString(obj.Choices, Inf));
                    end
                otherwise
                    isValid = true;
            end

            if ~isValid; return; end

            if isnumeric(value) && ~isempty(value)
                if any(value(:) < obj.Min)
                    isValid = false;
                    message = sprintf('Value must be greater than or equal to %g', obj.Min);
                elseif any(value(:) > obj.Max)
                    isValid = false;
                    message = sprintf('Value must be less than or equal to %g', obj.Max);
                elseif obj.Integer && any(round(value(:)) ~= value(:))
                    isValid = false;
                    message = 'Value must be integer valued';
                end
                if ~isValid; return; end
            end

            if ~isempty(obj.Size)
                requiredSize = obj.Size;
                valueSize = size(value);
                isValid = numel(valueSize) == numel(requiredSize) && ...
                    all( isnan(requiredSize) | valueSize == requiredSize );
                if ~isValid
                    sizeStr = strrep(mat2str(requiredSize), 'NaN', 'n');
                    message = sprintf('Value must have size %s', sizeStr);
                    return
                end
            end

            if ~isempty(obj.Validator)
                [isValid, message] = runValidator(obj.Validator, value);
            end
        end

        function value = coerce(obj, value)
        %coerce Convert a value to the class and orientation of the default
        %
        %   value = p.coerce(value) converts values that are equivalent
        %   but differ in class or shape from the default value, e.g. values
        %   read from JSON files (numbers as double, arrays as columns) or
        %   given as strings instead of character vectors.

            value = nansen.options.Parameter.normalizeValue(value);
            defaultValue = obj.Default;

            if strcmp(obj.Class, 'logical') && isnumeric(value) && ...
                    all(value(:) == 0 | value(:) == 1)
                value = logical(value);

            elseif any(strcmp(obj.Class, obj.NUMERIC_CLASSES)) && ...
                    (isnumeric(value) || islogical(value)) && ...
                    ~strcmp(class(value), obj.Class)
                value = cast(value, obj.Class);

            elseif strcmp(obj.Class, 'cell') && isempty(value) && ~iscell(value)
                value = {};

            elseif strcmp(obj.Class, 'char') && iscell(value) && isscalar(value) ...
                    && ischar(value{1})
                value = value{1};
            end

            % Match orientation of vectors
            if isvector(value) && ~isscalar(value) && ...
                    isvector(defaultValue) && ~isscalar(defaultValue)
                if isrow(defaultValue) && iscolumn(value)
                    value = value';
                elseif iscolumn(defaultValue) && isrow(value)
                    value = value';
                end
            end
        end

        function config = getEditorConfig(obj)
        %getEditorConfig Get configuration value for the structeditor app
        %
        %   The structeditor app (and the legacy options manager) supports
        %   configuration fields in option structs: For a field "name", a
        %   field "name_" specifies how the field should be displayed. This
        %   method returns the value of such a configuration field, or []
        %   if no configuration is needed.

            config = [];

            if obj.Internal
                config = 'internal';
            elseif ~isempty(obj.Choices)
                config = obj.Choices;
            elseif isstruct(obj.Widget) || isa(obj.Widget, 'function_handle')
                config = obj.Widget;
            elseif strcmp(obj.Widget, 'slider')
                args = {'Min', obj.Min, 'Max', obj.Max};
                if obj.Integer && isfinite(obj.Min) && isfinite(obj.Max)
                    args = [args, {'nTicks', obj.Max - obj.Min + 1, 'TooltipPrecision', 0}];
                end
                config = struct('type', 'slider', 'args', {args});
            elseif any(strcmp(obj.Widget, {'button', 'togglebutton', 'multilinechar'}))
                config = struct('type', obj.Widget, 'args', {{}});
            elseif ~isempty(obj.Widget)
                config = obj.Widget;
            elseif obj.Transient
                config = 'transient';
            end
        end

        function S = toJsonSchema(obj)
        %toJsonSchema Get a JSON Schema (https://json-schema.org) description

            S = struct();

            switch obj.Type
                case 'logical'
                    S.type = 'boolean';
                case 'numeric'
                    if obj.Integer; S.type = 'integer'; else; S.type = 'number'; end
                case 'text'
                    S.type = 'string';
                case 'list'
                    S.type = 'array';
                case 'function'
                    S.type = 'string';
            end

            if isnumeric(obj.Default) && ~isscalar(obj.Default)
                itemType = S.type;
                S.type = 'array';
                S.items = struct('type', itemType);
            end

            if ~isempty(obj.Label); S.title = obj.Label; end
            if ~isempty(obj.Description); S.description = obj.Description; end
            if ~isempty(obj.Choices); S.enum = obj.Choices; end
            if isfinite(obj.Min); S.minimum = obj.Min; end
            if isfinite(obj.Max); S.maximum = obj.Max; end
            if ~isempty(obj.Units); S.units = obj.Units; end

            if ~isa(obj.Default, 'function_handle')
                S.default = obj.Default;
            else
                S.default = func2str(obj.Default);
            end

            if obj.Transient; S.transient = true; end
            if obj.Internal; S.internal = true; end
            if obj.Advanced; S.advanced = true; end
            if ~isempty(obj.Deprecated)
                S.deprecated = true;
                S.deprecationMessage = obj.Deprecated;
            end
        end
    end

    methods % Set/get

        function type = get.Type(obj)
            if ~isempty(obj.Choices)
                type = 'choice';
            elseif strcmp(obj.Class, 'logical')
                type = 'logical';
            elseif any(strcmp(obj.Class, obj.NUMERIC_CLASSES))
                type = 'numeric';
            elseif strcmp(obj.Class, 'char')
                type = 'text';
            elseif strcmp(obj.Class, 'cell')
                type = 'list';
            elseif strcmp(obj.Class, 'function_handle')
                type = 'function';
            else
                type = 'any';
            end
        end

        function name = get.GroupName(obj)
            idx = find(obj.Name == '.', 1, 'last');
            if isempty(idx)
                name = '';
            else
                name = obj.Name(1:idx-1);
            end
        end

        function name = get.ShortName(obj)
            idx = find(obj.Name == '.', 1, 'last');
            if isempty(idx)
                name = obj.Name;
            else
                name = obj.Name(idx+1:end);
            end
        end

        function obj = set.Validator(obj, value)
            assert(isempty(value) || isa(value, 'function_handle'), ...
                'NANSEN:Options:InvalidAttribute', ...
                'Validator must be a function handle')
            obj.Validator = value;
        end

        function obj = set.Choices(obj, value)
            if isstring(value); value = cellstr(value); end
            obj.Choices = reshape(value, 1, []);
        end
    end

    methods (Access = private)

        function obj = applyNameValuePairs(obj, varargin)

            if mod(numel(varargin), 2) ~= 0
                error('NANSEN:Options:InvalidInput', ...
                    'Attributes must be given as name-value pairs')
            end

            allowedNames = {'Description', 'Units', 'Label', 'Choices', ...
                'Min', 'Max', 'Integer', 'Size', 'Validator', 'Widget', ...
                'Transient', 'Internal', 'Advanced', 'Since', 'Deprecated'};

            for i = 1:2:numel(varargin)
                attributeName = validatestring(char(varargin{i}), allowedNames);
                value = varargin{i+1};
                if isstring(value) && isscalar(value)
                    value = char(value);
                end
                obj.(attributeName) = value;
            end
        end

        function assertValidDefault(obj)
            [isValid, message] = obj.validate(obj.Default);
            if ~isValid
                error('NANSEN:Options:InvalidDefault', ...
                    'Invalid default value for parameter "%s": %s', ...
                    obj.Name, message)
            end
        end

        function tf = isValidChoice(obj, value)
            if ischar(value)
                tf = any(cellfun(@(c) ischar(c) && strcmp(c, value), obj.Choices));
            elseif iscell(value) % Multiple selection
                tf = all(cellfun(@(v) obj.isValidChoice(v), value));
            else
                tf = any(cellfun(@(c) isequal(c, value), obj.Choices));
            end
        end
    end

    methods (Static)

        function value = normalizeValue(value)
        %normalizeValue Convert string types to char / cellstr
            if isstring(value)
                if isscalar(value)
                    value = char(value);
                else
                    value = cellstr(value);
                end
            end
        end

        function validateName(name)
        %validateName Check that a parameter name is valid
            parts = strsplit(name, '.');
            isValid = all(cellfun(@isvarname, parts)) && ~strcmp(name(end), '_');
            if ~isValid
                error('NANSEN:Options:InvalidName', ...
                    ['"%s" is not a valid parameter name. Names must be ', ...
                    'valid variable names, optionally separated by dots, ', ...
                    'and can not end with an underscore.'], name)
            end
        end
    end
end

function [isValid, message] = runValidator(validatorFcn, value)
%runValidator Run a validation function
%
%   Supports functions that return a logical and functions that throw an
%   error for invalid values (like mustBePositive or @(x) assert(...))

    isValid = true;
    message = '';

    try
        try
            result = validatorFcn(value);
        catch ME
            if any(strcmp(ME.identifier, {'MATLAB:maxlhs', 'MATLAB:TooManyOutputs'})) ...
                    || ~isempty(regexpi(ME.message, 'too many output', 'once'))
                validatorFcn(value);
                result = true;
            else
                rethrow(ME)
            end
        end

        if (islogical(result) || isnumeric(result)) && ~isempty(result) && ~all(result(:))
            isValid = false;
            message = sprintf('Value failed validation by %s', func2str(validatorFcn));
        end
    catch ME
        isValid = false;
        message = ME.message;
    end
end

function [value, args] = popNameValue(args, name)
%popNameValue Remove a name-value pair from a list and return its value
    value = {};
    for i = numel(args)-1:-2:1
        if (ischar(args{i}) || isstring(args{i})) && strcmpi(args{i}, name)
            value = args(i+1);
            args(i:i+1) = [];
            return
        end
    end
end
