function jsonStr = jsonEncode(value, prettyPrint)
%jsonEncode Encode a MATLAB value as JSON text, preserving MATLAB types
%
%   jsonStr = nansen.options.internal.jsonEncode(value) encodes value as
%   JSON. Values that do not survive a plain jsonencode/jsondecode round
%   trip (e.g. NaN/Inf, matrices, column vectors, integer types, empty or
%   mixed cell arrays, struct arrays and function handles) are encoded as
%   tagged objects which are restored by nansen.options.internal.jsonDecode.
%
%   Common option values (scalars, row vectors, character vectors, cell
%   arrays of character vectors and nested structs) are encoded as plain
%   JSON so that files remain easy to read and edit by hand.
%
%   jsonStr = nansen.options.internal.jsonEncode(value, prettyPrint)
%   specifies whether to pretty print (default = true).
%
%   See also nansen.options.internal.jsonDecode

    if nargin < 2; prettyPrint = true; end

    encoded = encodeValue(value);

    if prettyPrint
        try
            jsonStr = jsonencode(encoded, 'PrettyPrint', true);
        catch % PrettyPrint requires R2021a
            jsonStr = jsonencode(encoded);
        end
    else
        jsonStr = jsonencode(encoded);
    end
end

function out = encodeValue(value)

    if isstring(value)
        if isscalar(value)
            value = char(value);
        else
            value = cellstr(value);
        end
    end

    if isstruct(value)
        if isscalar(value)
            out = struct();
            fields = fieldnames(value);
            for i = 1:numel(fields)
                out.(fields{i}) = encodeValue(value.(fields{i}));
            end
        else
            data = struct();
            for i = 1:numel(value)
                data.(sprintf('i%d', i)) = encodeValue(value(i));
            end
            out = createTaggedValue('struct', value, data);
            out.fields = fieldnames(value)';
        end

    elseif iscell(value)
        if ~isempty(value) && isrow(value) && iscellstr(value) %#ok<ISCLSTR>
            out = value;
        else
            data = struct();
            for i = 1:numel(value)
                data.(sprintf('i%d', i)) = encodeValue(value{i});
            end
            out = createTaggedValue('cell', value, data);
        end

    elseif ischar(value)
        if isequal(size(value), [0, 0]) || (isrow(value) && ~isempty(value))
            out = value;
        else
            out = createTaggedValue('char', value, cellstr(value));
        end

    elseif isnumeric(value) || islogical(value)
        if ~isreal(value)
            error('NANSEN:Options:UnsupportedType', ...
                'Complex values are not supported in options')
        end

        isPlain = ( isa(value, 'double') || islogical(value) ) ...
            && ~isempty(value) && isrow(value) && all(isfinite(double(value)));

        if isPlain
            out = value;
        else
            if isinteger(value) || islogical(value)
                data = arrayfun(@(x) sprintf('%d', x), value(:)', 'UniformOutput', false);
            else
                data = arrayfun(@(x) sprintf('%.17g', x), value(:)', 'UniformOutput', false);
            end
            out = createTaggedValue('numeric', value, data);
        end

    elseif isa(value, 'function_handle')
        out = createTaggedValue('function_handle', value, func2str(value));

    else
        error('NANSEN:Options:UnsupportedType', ...
            'Values of type "%s" can not be saved as options', class(value))
    end
end

function out = createTaggedValue(typeName, value, data)
    out = struct();
    out.nansen_type = typeName;
    out.class = class(value);
    out.size = size(value);
    out.data = data;
end
