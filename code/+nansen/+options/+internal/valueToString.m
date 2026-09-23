function str = valueToString(value, options)
%valueToString Create a short text representation of a value for display
%
%   str = nansen.options.internal.valueToString(value)
%   str = nansen.options.internal.valueToString(value, MaxLength=40)

    arguments
        value
        options.MaxLength (1,1) double = 60
    end

    if ischar(value) && (isrow(value) || isempty(value))
        str = "'" + string(value) + "'";
    elseif isstring(value) && isscalar(value)
        if ismissing(value)
            str = "<missing>";
        else
            str = """" + value + """";
        end
    elseif (isnumeric(value) || islogical(value)) && ismatrix(value)
        if numel(value) > 100
            str = sprintf("[%s %s]", join(string(size(value)), "x"), class(value));
        else
            str = string(mat2str(value));
        end
    elseif iscell(value) || isstring(value)
        if isstring(value); value = num2cell(value); end
        elements = cellfun(@(c) nansen.options.internal.valueToString(c, MaxLength=Inf), ...
            value(:)', "UniformOutput", false);
        if isempty(elements)
            str = "{}";
        else
            str = "{" + strjoin([elements{:}], ", ") + "}";
        end
    elseif isa(value, "function_handle")
        str = string(func2str(value));
    elseif isdatetime(value) && isscalar(value)
        str = string(value);
    elseif isstruct(value)
        str = sprintf("[%s struct]", join(string(size(value)), "x"));
    else
        str = sprintf("[%s]", class(value));
    end

    str = string(str);
    if strlength(str) > options.MaxLength
        str = extractBefore(str, options.MaxLength - 2) + "...";
    end
end
