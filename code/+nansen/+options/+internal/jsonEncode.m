function jsonStr = jsonEncode(value, options)
%jsonEncode Encode a MATLAB value as JSON text, preserving MATLAB types
%
%   jsonStr = nansen.options.internal.jsonEncode(value) encodes value as
%   JSON. Values that do not survive a plain jsonencode/jsondecode round
%   trip (e.g. NaN/Inf, matrices, column vectors, integer types, empty or
%   mixed cell arrays, struct arrays, string arrays, datetimes,
%   enumerations and function handles) are encoded as tagged objects which
%   are restored by nansen.options.internal.jsonDecode.
%
%   Common option values (scalars, row vectors, text, cell arrays of
%   character vectors and nested structs) are encoded as plain JSON, so
%   that files remain easy to read and edit by hand.
%
%   jsonStr = nansen.options.internal.jsonEncode(value, PrettyPrint=false)
%
%   See also nansen.options.internal.jsonDecode

    arguments
        value
        options.PrettyPrint (1,1) logical = true
    end

    jsonStr = string(jsonencode(encodeValue(value), ...
        "PrettyPrint", options.PrettyPrint));
end

function out = encodeValue(value)

    if isstruct(value)
        if isscalar(value)
            out = struct();
            for field = string(fieldnames(value))'
                out.(field) = encodeValue(value.(field));
            end
        else
            out = createTaggedValue("struct", value, encodeElements(value));
            out.fields = string(fieldnames(value))';
        end

    elseif iscell(value)
        if ~isempty(value) && isrow(value) && iscellstr(value)
            out = value;
        else
            out = createTaggedValue("cell", value, encodeElements(value));
        end

    elseif ischar(value)
        if isequal(size(value), [0, 0]) || (isrow(value) && ~isempty(value))
            out = value;
        else
            out = createTaggedValue("char", value, cellstr(value));
        end

    elseif isstring(value)
        if isscalar(value) && ~ismissing(value)
            out = value;
        else
            % Missing strings are stored as "" and listed by index
            isMissing = ismissing(value(:)');
            elements = value(:)';
            elements(isMissing) = "";
            out = createTaggedValue("string", value, cellstr(elements));
            out.missing = find(isMissing);
        end

    elseif isenumeration(value)
        out = createTaggedValue("enumeration", value, cellstr(string(value(:)')));

    elseif isnumeric(value) || islogical(value)
        if ~isreal(value)
            error("NANSEN:Options:UnsupportedType", ...
                "Complex values are not supported in options")
        end

        isPlain = ( isa(value, "double") || islogical(value) ) ...
            && ~isempty(value) && isrow(value) && all(isfinite(double(value)));

        if isPlain
            out = value;
        elseif isempty(value)
            out = createTaggedValue("numeric", value, {});
        elseif isinteger(value) || islogical(value)
            out = createTaggedValue("numeric", value, cellstr(compose("%d", value(:)')));
        else
            out = createTaggedValue("numeric", value, cellstr(compose("%.17g", value(:)')));
        end

    elseif isdatetime(value)
        out = createTaggedValue("datetime", value, ...
            cellstr(string(value(:)', "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS")));
        out.timezone = value.TimeZone;

    elseif isa(value, "function_handle")
        out = createTaggedValue("function_handle", value, func2str(value));

    else
        error("NANSEN:Options:UnsupportedType", ...
            "Values of type ""%s"" can not be saved as options", class(value))
    end
end

function data = encodeElements(value)
%encodeElements Encode elements of an array as fields i1, i2, ... of a struct
%
%   Elements are stored in an object (not a JSON array) because jsondecode
%   would otherwise merge compatible elements into arrays.
    data = struct();
    for i = 1:numel(value)
        if iscell(value)
            data.(sprintf("i%d", i)) = encodeValue(value{i});
        else
            data.(sprintf("i%d", i)) = encodeValue(value(i));
        end
    end
end

function out = createTaggedValue(typeName, value, data)
    out = struct();
    out.nansen_type = typeName;
    out.class = class(value);
    out.size = size(value);
    out.data = data;
end

function tf = isenumeration(value)
    mc = meta.class.fromName(class(value));
    tf = ~isempty(mc) && mc.Enumeration;
end
