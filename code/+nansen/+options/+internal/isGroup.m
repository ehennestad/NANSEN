function tf = isGroup(value)
%isGroup Check if a value is a group of options (scalar struct with fields)
    arguments
        value
    end
    tf = isstruct(value) && isscalar(value) && ~isempty(fieldnames(value));
end
