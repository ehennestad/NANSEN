function S = removeValue(S, name)
%removeValue Remove a (nested) field using a dotted name
%
%   S = nansen.options.internal.removeValue(S, 'Group.field') removes the
%   field. Groups that become empty as a result are also removed. If the
%   field does not exist, S is returned unchanged.

    parts = strsplit(name, '.');
    S = removeRecursive(S, parts);
end

function S = removeRecursive(S, parts)
    if ~isstruct(S) || ~isscalar(S) || ~isfield(S, parts{1})
        return
    end

    if numel(parts) == 1
        S = rmfield(S, parts{1});
    else
        subS = removeRecursive(S.(parts{1}), parts(2:end));
        if isstruct(subS) && isempty(fieldnames(subS))
            S = rmfield(S, parts{1});
        else
            S.(parts{1}) = subS;
        end
    end
end
