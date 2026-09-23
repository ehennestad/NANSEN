function str = canonicalString(value)
%canonicalString Create a deterministic text representation of a value
%
%   str = nansen.options.internal.canonicalString(value) returns a string
%   that uniquely represents the given value. The representation does not
%   depend on the order of struct fields, and includes the class and size
%   of arrays, so that two values give the same string if and only if
%   they are equal (including class).
%
%   Exception: text is represented by its content only, i.e. a character
%   vector and a string scalar with the same text are considered equal.
%
%   This is used for computing hashes (fingerprints) of options.

    arguments
        value
    end

    if isstring(value) && isscalar(value) && ~ismissing(value)
        value = char(value);
    end

    sizeStr = join(string(size(value)), "x");

    if isstruct(value)
        fields = sort(string(fieldnames(value)))';
        elementStr = strings(1, numel(value));
        for i = 1:numel(value)
            fieldStr = arrayfun(@(f) sprintf('"%s":%s', f, ...
                nansen.options.internal.canonicalString(value(i).(f))), ...
                fields, 'UniformOutput', false);
            elementStr(i) = "{" + safeJoin(string(fieldStr)) + "}";
        end
        str = sprintf("struct[%s](%s)", sizeStr, safeJoin(elementStr));

    elseif iscell(value)
        elementStr = cellfun(@nansen.options.internal.canonicalString, ...
            value(:)', 'UniformOutput', false);
        str = sprintf("cell[%s](%s)", sizeStr, safeJoin(string(elementStr)));

    elseif ischar(value)
        str = sprintf("text[%s](%s)", sizeStr, escape(string(value(:)')));

    elseif isstring(value)
        elementStr = string(arrayfun(@escapeStringElement, value(:)', UniformOutput=false));
        str = sprintf("string[%s](%s)", sizeStr, safeJoin(elementStr));

    elseif islogical(value)
        str = sprintf("logical[%s](%s)", sizeStr, sprintf('%d', value(:)));

    elseif isenum(value)
        str = sprintf("%s[%s](%s)", class(value), sizeStr, ...
            safeJoin(string(value(:)')));

    elseif isnumeric(value)
        if ~isreal(value)
            error("NANSEN:Options:UnsupportedType", ...
                "Complex values are not supported in options")
        end
        if isempty(value)
            numStr = string.empty(1, 0);
        elseif isinteger(value)
            numStr = compose("%d", value(:)');
        else
            numStr = compose("%.17g", value(:)');
        end
        str = sprintf("%s[%s](%s)", class(value), sizeStr, safeJoin(numStr));

    elseif isdatetime(value)
        str = sprintf("datetime[%s](%s)", sizeStr, ...
            safeJoin(string(value(:)', "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS")));

    elseif isa(value, 'function_handle')
        str = sprintf("function_handle(%s)", func2str(value));

    else
        error("NANSEN:Options:UnsupportedType", ...
            "Values of type ""%s"" are not supported in options", class(value))
    end

    str = string(str);
end

function str = escape(str)
    str = """" + replace(replace(str, "\", "\\"), """", "\""") + """";
end

function str = escapeStringElement(str)
    if ismissing(str)
        str = "<missing>";
    else
        str = escape(str);
    end
end

function tf = isenum(value)
    mc = meta.class.fromName(class(value));
    tf = ~isempty(mc) && mc.Enumeration;
end

function str = safeJoin(strs)
%safeJoin Join strings with commas (also for empty arrays)
    if isempty(strs)
        str = "";
    else
        str = strjoin(strs, ",");
    end
end
