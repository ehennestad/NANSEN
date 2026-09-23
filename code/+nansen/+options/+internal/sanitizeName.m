function name = sanitizeName(name)
%sanitizeName Convert a name to a string that is safe to use as a filename
    arguments
        name (1,1) string
    end
    name = regexprep(name, "[^\w\.\-]", "_");
end
