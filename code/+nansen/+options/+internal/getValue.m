function value = getValue(S, name)
%getValue Get value of a (nested) field using a dotted name
%
%   value = nansen.options.internal.getValue(S, "Group.field")

    arguments
        S (1,1) struct
        name (1,1) string
    end

    value = S;
    for part = split(name, ".")'
        if ~isstruct(value) || ~isscalar(value) || ~isfield(value, part)
            error("NANSEN:Options:FieldNotFound", ...
                "Field ""%s"" does not exist", name)
        end
        value = value.(part);
    end
end
