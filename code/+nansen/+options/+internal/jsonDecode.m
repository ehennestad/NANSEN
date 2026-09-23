function value = jsonDecode(jsonStr)
%jsonDecode Decode JSON text created by nansen.options.internal.jsonEncode
%
%   value = nansen.options.internal.jsonDecode(jsonStr) decodes JSON text
%   and restores MATLAB types from tagged objects. Plain JSON arrays are
%   returned as row vectors (jsondecode returns column vectors).
%
%   See also nansen.options.internal.jsonEncode

    value = decodeValue( jsondecode(jsonStr) );
end

function value = decodeValue(value)

    if isstruct(value) && isscalar(value) && isfield(value, 'nansen_type')
        value = decodeTaggedValue(value);

    elseif isstruct(value) && isscalar(value)
        fields = fieldnames(value);
        for i = 1:numel(fields)
            value.(fields{i}) = decodeValue(value.(fields{i}));
        end

    elseif isstruct(value) % Struct array from plain JSON (not from encoder)
        value = reshape(value, 1, []);

    elseif ischar(value) && isempty(value)
        value = ''; % Plain empty strings are always encoded from 0x0 char

    elseif iscell(value)
        value = reshape(value, 1, []);
        for i = 1:numel(value)
            value{i} = decodeValue(value{i});
        end

    elseif (isnumeric(value) || islogical(value)) && isvector(value) && ~isscalar(value)
        value = reshape(value, 1, []);
    end
end

function value = decodeTaggedValue(S)

    sz = reshape(double(S.size), 1, []);
    numElements = prod(sz);

    switch S.nansen_type
        case 'numeric'
            if numElements == 0
                data = zeros(sz);
            else
                data = str2double(ensureCell(S.data));
            end
            data = reshape(data, sz);
            if strcmp(S.class, 'logical')
                value = logical(data);
            else
                value = cast(data, S.class);
            end

        case 'char'
            if numElements == 0
                value = reshape('', sz);
            else
                value = char(ensureCell(S.data));
                value = reshape(value, sz);
            end

        case 'cell'
            value = cell(sz);
            for i = 1:numElements
                value{i} = decodeValue(S.data.(sprintf('i%d', i)));
            end

        case 'struct'
            fields = ensureCell(S.fields);
            if numElements == 0
                args = [fields; repmat({{}}, 1, numel(fields))];
                value = reshape(struct(args{:}), sz);
            else
                elements = cell(1, numElements);
                for i = 1:numElements
                    elements{i} = decodeValue(S.data.(sprintf('i%d', i)));
                end
                value = reshape([elements{:}], sz);
            end

        case 'function_handle'
            value = str2func(S.data);

        otherwise
            error('NANSEN:Options:UnknownJsonType', ...
                'Unknown encoded type "%s"', S.nansen_type)
    end
end

function c = ensureCell(c)
    if isempty(c)
        c = {};
    elseif ischar(c)
        c = {c};
    else
        c = reshape(c, 1, []);
    end
end
