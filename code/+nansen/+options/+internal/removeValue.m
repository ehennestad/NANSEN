function S = removeValue(S, name)
%removeValue Remove a (nested) field using a dotted name
%
%   S = nansen.options.internal.removeValue(S, "Group.field") removes the
%   field. Groups that become empty as a result are also removed. If the
%   field does not exist, S is returned unchanged.

    arguments
        S (1,1) struct
        name (1,1) string
    end

    S = removeRecursive(S, split(name, ".")');
end

function S = removeRecursive(S, parts)
    if ~isfield(S, parts(1))
        return
    end

    if isscalar(parts)
        S = rmfield(S, parts(1));
    elseif isstruct(S.(parts(1))) && isscalar(S.(parts(1)))
        subS = removeRecursive(S.(parts(1)), parts(2:end));
        if isempty(fieldnames(subS))
            S = rmfield(S, parts(1));
        else
            S.(parts(1)) = subS;
        end
    end
end
