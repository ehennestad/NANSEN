function tf = hasValue(S, name)
%hasValue Check if a (nested) field exists using a dotted name
%
%   tf = nansen.options.internal.hasValue(S, 'Group.field')

    parts = strsplit(name, '.');
    tf = true;
    value = S;
    for i = 1:numel(parts)
        if ~isstruct(value) || ~isscalar(value) || ~isfield(value, parts{i})
            tf = false; return
        end
        value = value.(parts{i});
    end
end
