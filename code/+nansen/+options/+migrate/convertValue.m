function S = convertValue(S, name, conversionFcn)
%convertValue Convert the value of a field in a struct of options
%
%   S = nansen.options.migrate.convertValue(S, name, conversionFcn)
%   replaces the value of the (dotted) field name with conversionFcn(value)
%   if the field exists. Example: convert a window size from samples to
%   seconds when the meaning of a parameter changed.
%
%   See also nansen.options.Schema/addMigration

    arguments
        S (1,1) struct
        name (1,1) string
        conversionFcn (1,1) function_handle
    end

    if ~nansen.options.internal.hasValue(S, name); return; end
    value = nansen.options.internal.getValue(S, name);
    S = nansen.options.internal.setValue(S, name, conversionFcn(value));
end
