function str = valueToString(value, maxLength)
%valueToString Create a short text representation of a value for display
%
%   str = nansen.options.internal.valueToString(value)
%   str = nansen.options.internal.valueToString(value, maxLength)

    if nargin < 2; maxLength = 60; end

    if isstring(value); value = char(value); end

    if ischar(value) && (isrow(value) || isempty(value))
        str = sprintf('''%s''', value);
    elseif (isnumeric(value) || islogical(value)) && ismatrix(value)
        if numel(value) > 100
            str = sprintf('[%s %s]', strjoin(strsplit(num2str(size(value))), 'x'), class(value));
        else
            str = mat2str(value);
        end
    elseif iscell(value)
        elements = cellfun(@(c) nansen.options.internal.valueToString(c, Inf), ...
            value(:)', 'UniformOutput', false);
        str = sprintf('{%s}', strjoin(elements, ', '));
    elseif isa(value, 'function_handle')
        str = func2str(value);
    elseif isstruct(value)
        str = sprintf('[%s struct]', strjoin(strsplit(num2str(size(value))), 'x'));
    else
        str = sprintf('[%s]', class(value));
    end

    if numel(str) > maxLength
        str = [str(1:maxLength-3), '...'];
    end
end
