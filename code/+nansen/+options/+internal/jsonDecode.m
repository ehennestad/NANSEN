function value = jsonDecode(jsonStr)
%jsonDecode Decode JSON text created by nansen.options.internal.jsonEncode
%
%   value = nansen.options.internal.jsonDecode(jsonStr) decodes JSON text
%   and restores MATLAB types from tagged objects. Plain JSON arrays are
%   returned as row vectors (jsondecode returns column vectors).
%
%   See also nansen.options.internal.jsonEncode

    arguments
        jsonStr (1,1) string
    end

    value = decodeValue( jsondecode(jsonStr) );
end

function value = decodeValue(value)

    if isstruct(value) && isscalar(value) && isfield(value, "nansen_type")
        value = decodeTaggedValue(value);

    elseif isstruct(value) && isscalar(value)
        for field = string(fieldnames(value))'
            value.(field) = decodeValue(value.(field));
        end

    elseif isstruct(value) % Struct array from plain JSON (not from encoder)
        value = reshape(value, 1, []);

    elseif ischar(value) && isempty(value)
        value = ''; % Plain empty text is always encoded from a 0x0 char

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
    data = S.data;

    switch S.nansen_type
        case "numeric"
            if numElements == 0
                numbers = zeros(sz);
            else
                numbers = reshape(str2double(toCell(data)), sz);
            end
            if S.class == "logical"
                value = logical(numbers);
            else
                value = cast(numbers, S.class);
            end

        case "char"
            if numElements == 0
                value = reshape('', sz);
            else
                value = reshape(char(toCell(data)), sz);
            end

        case "string"
            if numElements == 0
                value = strings(sz);
            else
                elements = toCell(data);
                isMissing = cellfun(@(c) isempty(c) && isnumeric(c), elements);
                elements(isMissing) = {''};
                value = string(elements);
                value(isMissing) = missing;
                value = reshape(value, sz);
            end

        case "enumeration"
            [members, memberNames] = enumeration(S.class);
            [~, idx] = ismember(string(toCell(data)), string(memberNames));
            value = reshape(members(idx), sz);

        case "cell"
            value = cell(sz);
            for i = 1:numElements
                value{i} = decodeValue(data.(sprintf("i%d", i)));
            end

        case "struct"
            fields = toCell(S.fields);
            if numElements == 0
                args = [fields; repmat({{}}, 1, numel(fields))];
                value = reshape(struct(args{:}), sz);
            else
                elements = cell(1, numElements);
                for i = 1:numElements
                    elements{i} = decodeValue(data.(sprintf("i%d", i)));
                end
                value = reshape([elements{:}], sz);
            end

        case "datetime"
            value = datetime(string(toCell(data)), ...
                "InputFormat", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS", ...
                "TimeZone", S.timezone);
            value = reshape(value, sz);

        case "function_handle"
            value = str2func(data);

        otherwise
            error("NANSEN:Options:UnknownJsonType", ...
                "Unknown encoded type ""%s""", S.nansen_type)
    end
end

function c = toCell(c)
    if isempty(c)
        c = {};
    elseif ischar(c)
        c = {c};
    elseif iscell(c)
        c = reshape(c, 1, []);
    else
        c = num2cell(reshape(c, 1, []));
    end
end
