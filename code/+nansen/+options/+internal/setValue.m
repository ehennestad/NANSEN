function S = setValue(S, name, value)
%setValue Set value of a (nested) field using a dotted name
%
%   S = nansen.options.internal.setValue(S, "Group.field", value) sets the
%   value of the given field. Intermediate groups are created if needed.

    arguments
        S (1,1) struct
        name (1,1) string
        value
    end

    S = setValueRecursive(S, split(name, ".")', value);
end

function S = setValueRecursive(S, parts, value)
    if isscalar(parts)
        S.(parts(1)) = value;
    else
        if isfield(S, parts(1)) && isstruct(S.(parts(1))) && isscalar(S.(parts(1)))
            subS = S.(parts(1));
        else
            subS = struct();
        end
        S.(parts(1)) = setValueRecursive(subS, parts(2:end), value);
    end
end
