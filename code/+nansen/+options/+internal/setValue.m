function S = setValue(S, name, value)
%setValue Set value of a (nested) field using a dotted name
%
%   S = nansen.options.internal.setValue(S, 'Group.field', value) sets the
%   value of the given field. Intermediate groups are created if needed.

    if isempty(S) && ~isstruct(S); S = struct(); end

    parts = strsplit(name, '.');
    S = setValueRecursive(S, parts, value);
end

function S = setValueRecursive(S, parts, value)
    if numel(parts) == 1
        S.(parts{1}) = value;
    else
        if isfield(S, parts{1}) && isstruct(S.(parts{1})) && isscalar(S.(parts{1}))
            subS = S.(parts{1});
        else
            subS = struct();
        end
        S.(parts{1}) = setValueRecursive(subS, parts(2:end), value);
    end
end
