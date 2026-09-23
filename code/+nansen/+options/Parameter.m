classdef Parameter
%nansen.options.Parameter Definition of a single parameter in an options schema
%
%   A Parameter describes one field of an options struct: its name,
%   default value, data type, allowed values and documentation, as well as
%   metadata that controls how it is displayed in user interfaces and
%   whether it contributes to the fingerprint (hash) of an options set.
%
%   Parameters are normally created with nansen.options.Schema/addParameter
%
%   p = nansen.options.Parameter(name, defaultValue, Name=Value, ...)
%
%   INPUTS:
%       name         : Name of parameter. Use dots for parameters that
%                      belong to a group, e.g. "Preprocessing.binSize"
%       defaultValue : Default value of parameter. The class of the
%                      default value is the class of the parameter, i.e.
%                      values are converted to this class.
%
%   NAME-VALUE ARGUMENTS (all optional, any public property):
%       Description : Text describing what the parameter does.
%       Units       : Unit of the parameter value, e.g. "s" or "pixels".
%       Label       : Short human readable label for user interfaces.
%       Choices     : Cell array of allowed values (enumeration).
%       Min, Max    : Inclusive numeric bounds.
%       Integer     : true if value must be integer valued.
%       Size        : Required size, e.g. [1 1] for scalars. NaN in a
%                     dimension means any length, e.g. [1 NaN] for row vectors.
%       Validator   : Function handle which either returns false or throws
%                     an error if a value is invalid (e.g. @mustBePositive).
%       Widget      : User interface hint: "slider", "folder", "file",
%                     "multiline" or "color".
%       Transient   : true if the parameter does not affect the result of
%                     a method (e.g. verbosity or number of workers).
%                     Transient parameters are excluded from options hashes.
%       Internal    : true if the parameter should be hidden from users.
%       Advanced    : true if the parameter is only shown in advanced views.
%       Since       : Schema version where the parameter was introduced.
%       Deprecated  : Text explaining why parameter is deprecated/what
%                     to use instead. Empty if not deprecated.
%
%   Example:
%       p = nansen.options.Parameter("binSize", 5, Min=1, Integer=true, ...
%           Description="Number of frames to bin", Units="frames");
%       [isValid, message] = p.validate(0)
%
%   See also nansen.options.Schema nansen.options.ParameterType

    properties
        Name (1,1) string = ""
        Default = []
        Description (1,1) string = ""
        Units (1,1) string = ""
        Label (1,1) string = ""
        Choices (1,:) cell = cell(1, 0)
        Min (1,1) double = -Inf
        Max (1,1) double = Inf
        Integer (1,1) logical = false
        Size (1,:) double = double.empty(1, 0)
        Validator {nansen.options.internal.mustBeFunctionHandleOrEmpty} = []
        Widget (1,1) string {mustBeMember(Widget, ["", "slider", "folder", "file", "multiline", "color"])} = ""
        Transient (1,1) logical = false
        Internal (1,1) logical = false
        Advanced (1,1) logical = false
        Since (1,1) string = ""
        Deprecated (1,1) string = ""
    end

    properties (SetAccess = private)
        Class (1,1) string = "double"   % Class of value (from default value)
    end

    properties (Dependent, SetAccess = private)
        Type (1,1) nansen.options.ParameterType   % Type of parameter
        GroupName (1,1) string          % Name of group ("" if not in a group)
        ShortName (1,1) string          % Name without group
        DisplayLabel (1,1) string       % Label, or label generated from name
        IsDeprecated (1,1) logical
    end

    methods % Constructor

        function obj = Parameter(name, defaultValue, attributes)
            arguments
                name (1,1) string = ""
                defaultValue = []
                attributes.?nansen.options.Parameter
            end

            if nargin == 0; return; end

            nansen.options.Parameter.mustBeValidName(name)
            nansen.options.Parameter.mustNotBeGroup(name, defaultValue)
            obj.Name = name;
            obj.Default = defaultValue;
            obj.Class = class(defaultValue);

            obj = obj.applyAttributes(attributes);
            obj.assertValidDefault()
        end
    end

    methods

        function obj = modify(obj, attributes)
        %modify Modify attributes (incl. Default) of the parameter
        %
        %   p = p.modify(Name=Value, ...)
        %
        %   Example:
        %       p = p.modify(Default=10, Max=100)

            arguments
                obj (1,1) nansen.options.Parameter
                attributes.?nansen.options.Parameter
            end

            if isfield(attributes, "Default")
                nansen.options.Parameter.mustNotBeGroup(obj.Name, attributes.Default)
                obj.Default = attributes.Default;
                obj.Class = class(attributes.Default);
            end

            obj = obj.applyAttributes(attributes);
            obj.assertValidDefault()
        end

        function [isValid, message] = validate(obj, value)
        %validate Check if a value is valid for this parameter
        %
        %   [isValid, message] = p.validate(value) returns true if value is
        %   valid. If not, message describes the problem.

            arguments
                obj (1,1) nansen.options.Parameter
                value
            end

            import nansen.options.ParameterType

            message = "";

            switch obj.Type
                case ParameterType.Logical
                    isValid = islogical(value) || ( isnumeric(value) && ...
                        all(value(:) == 0 | value(:) == 1) );
                    message = "Value must be logical (true/false)";
                case ParameterType.Numeric
                    isValid = isnumeric(value) && isreal(value);
                    message = "Value must be numeric";
                case ParameterType.Text
                    isValid = nansen.options.internal.isText(value) && (isscalar(string(value)) || isempty(value));
                    message = "Value must be text";
                case ParameterType.List
                    isValid = iscell(value) || isstring(value);
                    message = "Value must be a list (cell array or string array)";
                case ParameterType.Function
                    isValid = isa(value, "function_handle") || ...
                        (nansen.options.internal.isText(value) && strlength(string(value)) > 0);
                    message = "Value must be a function handle or function name";
                case ParameterType.Choice
                    isValid = obj.isValidChoice(value);
                    message = "Value must be one of: " + ...
                        nansen.options.internal.valueToString(obj.Choices, MaxLength=Inf);
                case ParameterType.Struct
                    isValid = isstruct(value);
                    message = "Value must be a struct";
                otherwise
                    isValid = true;
            end

            if ~isValid; return; end
            message = "";

            if isnumeric(value) && ~isempty(value)
                if any(value(:) < obj.Min)
                    isValid = false;
                    message = sprintf("Value must be greater than or equal to %g", obj.Min);
                elseif any(value(:) > obj.Max)
                    isValid = false;
                    message = sprintf("Value must be less than or equal to %g", obj.Max);
                elseif obj.Integer && any(round(value(:)) ~= value(:))
                    isValid = false;
                    message = "Value must be integer valued";
                end
                if ~isValid; return; end
            end

            if ~isempty(obj.Size)
                valueSize = size(value);
                isValid = numel(valueSize) == numel(obj.Size) && ...
                    all( isnan(obj.Size) | valueSize == obj.Size );
                if ~isValid
                    message = "Value must have size " + ...
                        replace(mat2str(obj.Size), "NaN", "n");
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
        %   read from JSON files (numbers as double, arrays as columns,
        %   text as char).

            arguments
                obj (1,1) nansen.options.Parameter
                value
            end

            switch obj.Class
                case "logical"
                    if isnumeric(value) && all(value(:) == 0 | value(:) == 1)
                        value = logical(value);
                    end
                case {'double', 'single', 'int8', 'uint8', 'int16', ...
                        'uint16', 'int32', 'uint32', 'int64', 'uint64'}
                    if (isnumeric(value) || islogical(value)) && class(value) ~= obj.Class
                        value = cast(value, obj.Class);
                    end
                case "char"
                    if isstring(value) && isscalar(value)
                        value = char(value);
                    elseif iscellstr(value) && isscalar(value)
                        value = value{1};
                    end
                case "string"
                    if ischar(value) || iscellstr(value)
                        value = string(value);
                    end
                case "cell"
                    if isstring(value)
                        value = cellstr(value);
                    elseif isempty(value) && ~iscell(value)
                        value = {};
                    end
                case "function_handle"
                    if nansen.options.internal.isText(value) && strlength(string(value)) > 0
                        value = str2func(value);
                    end
            end

            % Match orientation of vectors
            if isvector(value) && ~isscalar(value) && ...
                    isvector(obj.Default) && ~isscalar(obj.Default) && ...
                    isrow(obj.Default) ~= isrow(value)
                value = value.';
            end
        end

        function S = toJsonSchema(obj)
        %toJsonSchema Get a JSON Schema (https://json-schema.org) description

            arguments
                obj (1,1) nansen.options.Parameter
            end

            import nansen.options.ParameterType

            S = struct();

            switch obj.Type
                case ParameterType.Logical
                    S.type = "boolean";
                case ParameterType.Numeric
                    if obj.Integer; S.type = "integer"; else; S.type = "number"; end
                case {ParameterType.Text, ParameterType.Function}
                    S.type = "string";
                case ParameterType.List
                    S.type = "array";
                case ParameterType.Struct
                    S.type = "object";
            end

            if obj.Type == ParameterType.Numeric && ~isscalar(obj.Default)
                S.items = struct("type", S.type);
                S.type = "array";
            end

            S.title = obj.DisplayLabel;
            if obj.Description ~= ""; S.description = obj.Description; end
            if ~isempty(obj.Choices); S.enum = obj.Choices; end
            if isfinite(obj.Min); S.minimum = obj.Min; end
            if isfinite(obj.Max); S.maximum = obj.Max; end
            if obj.Units ~= ""; S.units = obj.Units; end

            if isa(obj.Default, "function_handle")
                S.default = func2str(obj.Default);
            else
                S.default = obj.Default;
            end

            if obj.Transient; S.transient = true; end
            if obj.Internal; S.internal = true; end
            if obj.Advanced; S.advanced = true; end
            if obj.IsDeprecated
                S.deprecated = true;
                S.deprecationMessage = obj.Deprecated;
            end
        end
    end

    methods % Set/get

        function type = get.Type(obj)
            type = nansen.options.ParameterType.fromValue( ...
                obj.Default, ~isempty(obj.Choices));
        end

        function name = get.GroupName(obj)
            if contains(obj.Name, ".")
                name = extractBefore(obj.Name, ...
                    strlength(obj.Name) - strlength(obj.ShortName));
            else
                name = "";
            end
        end

        function name = get.ShortName(obj)
            parts = split(obj.Name, ".");
            name = parts(end);
        end

        function label = get.DisplayLabel(obj)
            if obj.Label ~= ""
                label = obj.Label;
            else
                % Convert camelCase to words: "binSize" -> "Bin size"
                label = regexprep(obj.ShortName, "([a-z0-9])([A-Z])", "$1 $2");
                label = lower(label);
                label = upper(extractBefore(label, 2)) + extractAfter(label, 1);
            end
        end

        function tf = get.IsDeprecated(obj)
            tf = obj.Deprecated ~= "";
        end
    end

    methods (Access = private)

        function obj = applyAttributes(obj, attributes)
            ignoredNames = intersect(fieldnames(attributes), {'Name', 'Default'});
            if ~isempty(ignoredNames)
                attributes = rmfield(attributes, ignoredNames);
            end
            for name = string(fieldnames(attributes))'
                obj.(name) = attributes.(name);
            end
        end

        function assertValidDefault(obj)
            [isValid, message] = obj.validate(obj.Default);
            if ~isValid
                error("NANSEN:Options:InvalidDefault", ...
                    "Invalid default value for parameter ""%s"": %s", ...
                    obj.Name, message)
            end
        end

        function tf = isValidChoice(obj, value)
            if nansen.options.internal.isText(value) && isscalar(string(value))
                isTextChoice = cellfun(@(c) nansen.options.internal.isText(c) && isscalar(string(c)), obj.Choices);
                textChoices = string(obj.Choices(isTextChoice));
                tf = any(textChoices == string(value));
            elseif iscell(value) || (isstring(value) && ~isscalar(value)) % Multiple selection
                if isstring(value); value = num2cell(value); end
                tf = all(cellfun(@(v) obj.isValidChoice(v), value));
            else
                tf = any(cellfun(@(c) isequal(c, value), obj.Choices));
            end
        end
    end

    methods (Static)
        function mustNotBeGroup(name, value)
        %mustNotBeGroup Validate that a default value is not a group
        %
        %   Scalar structs with fields represent groups of parameters, so
        %   each field must be defined as a separate parameter instead.
            if nansen.options.internal.isGroup(value)
                fields = string(fieldnames(value));
                throwAsCaller(MException("NANSEN:Options:InvalidDefault", ...
                    "The default value of ""%s"" is a struct with fields. Define " + ...
                    "each field as a separate parameter (e.g. ""%s.%s"") instead.", ...
                    name, name, fields(1)))
            end
        end
        
        function mustBeValidName(name)
        %mustBeValidName Validate that a parameter name is valid
        %
        %   Names must be valid variable names, optionally separated by
        %   dots, and can not end with an underscore (reserved for legacy
        %   configuration fields).
            arguments
                name (1,1) string
            end
            parts = split(name, ".");
            isValid = all(arrayfun(@isvarname, parts)) && ~endsWith(name, "_");
            if ~isValid
                throwAsCaller(MException("NANSEN:Options:InvalidName", ...
                    """%s"" is not a valid parameter name. Names must be " + ...
                    "valid variable names, optionally separated by dots, " + ...
                    "and can not end with an underscore.", name))
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
    message = "";

    try
        numOutputs = nargout(validatorFcn);
    catch
        numOutputs = -1; % Unknown
    end

    try
        if numOutputs == 0
            validatorFcn(value);
            return
        end

        try
            result = validatorFcn(value);
        catch ME
            % Anonymous functions report nargout = -1 (varargout) even if
            % the function they call has no output, e.g. @(x) assert(...)
            if any(strcmp(ME.identifier, ["MATLAB:maxlhs", "MATLAB:TooManyOutputs"])) ...
                    || ~isempty(regexpi(ME.message, "too many output", "once"))
                validatorFcn(value);
                return
            end
            rethrow(ME)
        end

        if (islogical(result) || isnumeric(result)) && ~isempty(result) && ~all(result(:))
            isValid = false;
            message = "Value failed validation by " + func2str(validatorFcn);
        end
    catch ME
        isValid = false;
        message = string(ME.message);
    end
end
