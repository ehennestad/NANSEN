function value = getValue(S, name)
%getValue Get value of a (nested) field using a dotted name
%
%   value = nansen.options.internal.getValue(S, 'Group.field')

    parts = strsplit(name, '.');
    value = S;
    for i = 1:numel(parts)
        if ~isstruct(value) || ~isscalar(value) || ~isfield(value, parts{i})
            error('NANSEN:Options:FieldNotFound', ...
                'Field "%s" does not exist', name)
        end
        value = value.(parts{i});
    end
end
