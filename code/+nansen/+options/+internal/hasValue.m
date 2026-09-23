function tf = hasValue(S, name)
%hasValue Check if a (nested) field exists using a dotted name
%
%   tf = nansen.options.internal.hasValue(S, "Group.field")

    arguments
        S (1,1) struct
        name (1,1) string
    end

    tf = true;
    value = S;
    for part = split(name, ".")'
        if ~isstruct(value) || ~isscalar(value) || ~isfield(value, part)
            tf = false;
            return
        end
        value = value.(part);
    end
end
