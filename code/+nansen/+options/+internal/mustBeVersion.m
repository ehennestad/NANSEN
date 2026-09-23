function mustBeVersion(value)
%mustBeVersion Validate that value is a version string like "1.2.3"
    arguments
        value (1,1) string
    end
    if isempty(regexp(value, "^\d+(\.\d+)*$", "once"))
        throwAsCaller(MException("NANSEN:Options:InvalidVersion", ...
            "Version must be a version string like ""1.0.0"", but was ""%s""", value))
    end
end
