function mustBeProfileName(value)
%mustBeProfileName Validate that value can be used as a profile name
%
%   Profile names can contain letters, numbers, spaces, underscores,
%   dashes, dots and parentheses, and must start with a letter or number.
    arguments
        value (1,1) string
    end
    if value ~= "" && isempty(regexp(value, "^[A-Za-z0-9][\w \-\.\(\)]*$", "once"))
        throwAsCaller(MException("NANSEN:Options:InvalidName", ...
            "Invalid profile name ""%s"". Use letters, numbers, spaces, " + ...
            "underscores, dashes, dots and parentheses.", value))
    end
end
