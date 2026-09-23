function mustBeFunctionHandleOrEmpty(value)
%mustBeFunctionHandleOrEmpty Validate that value is a function handle or empty
    if ~(isempty(value) || (isscalar(value) && isa(value, "function_handle")))
        throwAsCaller(MException("NANSEN:Options:InvalidAttribute", ...
            "Value must be a function handle or empty"))
    end
end
