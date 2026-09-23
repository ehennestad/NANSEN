function str = canonicalString(value)
%canonicalString Create a deterministic text representation of a value
%
%   str = nansen.options.internal.canonicalString(value) returns a
%   character vector that uniquely represents the given value. The
%   representation is independent of the order of struct fields and
%   includes the class and size of arrays, so that two values give the
%   same string if and only if they are equal (including class).
%
%   This is used for computing hashes (fingerprints) of options.
%
%   Supported types: struct, cell, char, string, logical, numeric (real)
%   and function handles.

    if isstring(value)
        if isscalar(value)
            value = char(value);
        else
            value = cellstr(value);
        end
    end

    sizeStr = sprintf('%d,', size(value));
    sizeStr = sizeStr(1:end-1);

    if isstruct(value)
        fields = sort(fieldnames(value));
        elementStr = cell(1, numel(value));
        for i = 1:numel(value)
            fieldStr = cell(1, numel(fields));
            for j = 1:numel(fields)
                fieldStr{j} = sprintf('"%s":%s', fields{j}, ...
                    nansen.options.internal.canonicalString(value(i).(fields{j})));
            end
            elementStr{i} = ['{', strjoin(fieldStr, ','), '}'];
        end
        str = sprintf('struct[%s](%s)', sizeStr, strjoin(elementStr, ','));

    elseif iscell(value)
        elementStr = cellfun(@(c) nansen.options.internal.canonicalString(c), ...
            value(:)', 'UniformOutput', false);
        str = sprintf('cell[%s](%s)', sizeStr, strjoin(elementStr, ','));

    elseif ischar(value)
        escaped = strrep(value(:)', '\', '\\');
        escaped = strrep(escaped, '"', '\"');
        str = sprintf('char[%s]("%s")', sizeStr, escaped);

    elseif islogical(value)
        str = sprintf('logical[%s](%s)', sizeStr, sprintf('%d', value(:)));

    elseif isnumeric(value)
        if ~isreal(value)
            error('NANSEN:Options:UnsupportedType', ...
                'Complex values are not supported in options')
        end
        if isinteger(value)
            numStr = sprintf('%d,', value(:));
        else
            numStr = sprintf('%.17g,', value(:));
        end
        str = sprintf('%s[%s](%s)', class(value), sizeStr, numStr(1:max(0,end-1)));

    elseif isa(value, 'function_handle')
        str = sprintf('function_handle(%s)', func2str(value));

    else
        error('NANSEN:Options:UnsupportedType', ...
            'Values of type "%s" are not supported in options', class(value))
    end
end
