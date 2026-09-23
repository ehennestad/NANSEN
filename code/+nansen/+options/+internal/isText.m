function tf = isText(value)
%isText Check if a value is text (character array or string array)
    tf = ischar(value) || isstring(value);
end
