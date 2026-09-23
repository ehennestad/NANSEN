classdef ParameterType
%nansen.options.ParameterType Kind of value a parameter holds
%
%   The type of a parameter is derived from its default value (and
%   choices), and determines how values are validated and edited.

    enumeration
        Logical     % true/false
        Numeric     % Numbers (scalars or arrays)
        Text        % Character vector or string scalar
        Choice      % One of a list of allowed values
        List        % Cell array or string array
        Function    % Function handle
        Struct      % Struct (edited as a whole)
        Any         % Any other value
    end

    methods (Static)
        function type = fromValue(value, hasChoices)
        %fromValue Get the type of parameter for a value
            arguments
                value
                hasChoices (1,1) logical = false
            end

            import nansen.options.ParameterType

            if hasChoices
                type = ParameterType.Choice;
            elseif islogical(value)
                type = ParameterType.Logical;
            elseif isnumeric(value)
                type = ParameterType.Numeric;
            elseif (ischar(value) && (isrow(value) || isempty(value))) || ...
                    (isstring(value) && isscalar(value))
                type = ParameterType.Text;
            elseif iscell(value) || isstring(value)
                type = ParameterType.List;
            elseif isa(value, "function_handle")
                type = ParameterType.Function;
            elseif isstruct(value)
                type = ParameterType.Struct;
            else
                type = ParameterType.Any;
            end
        end
    end
end
