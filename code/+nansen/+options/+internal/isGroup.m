function tf = isGroup(value)
%isGroup Check if a value is a group (scalar struct with fields) of options
    tf = isstruct(value) && isscalar(value) && ~isempty(fieldnames(value));
end
