function schema = getSchema(methodName)
%getSchema Get the options schema for a method
%
%   schema = nansen.options.getSchema(methodName) returns the options
%   schema (nansen.options.Schema) for the method (function or class) with
%   the given name.
%
%   The recommended way to define options is a static method
%   getOptionsSchema() of the method class, which returns the schema:
%
%       methods (Static)
%           function schema = getOptionsSchema()
%               schema = nansen.options.Schema(mfilename("class"), Version="1.0.0");
%               schema.addParameter("binSize", 5, Min=1, Integer=true)
%           end
%       end
%
%   For methods that define options in one of the legacy ways, a schema
%   is inferred from the default options (schema.IsInferred is true):
%
%   - a class with a static method getDefaultOptions() (e.g. classes that
%     inherit from nansen.mixin.HasOptions)
%   - a class with a static method getOptions() (option adapters for
%     external toolboxes, nansen.wrapper.abstract.OptionsAdapter)
%   - a function which returns a struct of options when called with no
%     inputs (optionally in a field called DefaultOptions, like session
%     method functions)
%
%   For legacy methods, presets are collected from a +presets package in
%   the same package as the method, and descriptions are parsed from
%   trailing comments in the file which defines the defaults.
%
%   See also nansen.options.Schema nansen.options.legacy.inferSchema

    arguments
        methodName (1,1) string {mustBeNonzeroLengthText}
    end

    mc = meta.class.fromName(char(methodName));

    if ~isempty(mc)
        staticMethods = mc.MethodList([mc.MethodList.Static]);
        staticMethodNames = string({staticMethods.Name});

        if ismember("getOptionsSchema", staticMethodNames)
            schema = feval(methodName + ".getOptionsSchema");
            if ~isa(schema, "nansen.options.Schema")
                error("NANSEN:Options:InvalidSchema", ...
                    "%s.getOptionsSchema must return a nansen.options.Schema", methodName)
            end
            if schema.Name == ""; schema.Name = methodName; end
            return

        elseif ismember("getDefaultOptions", staticMethodNames)
            defaultsFunctionName = methodName + ".getDefaultOptions";

        elseif ismember("getOptions", staticMethodNames)
            defaultsFunctionName = methodName + ".getOptions";

        else
            error("NANSEN:Options:SchemaNotFound", ...
                "Class ""%s"" does not define options", methodName)
        end

        defaultOptions = feval(defaultsFunctionName);

    elseif any(exist(methodName, "file") == [2, 3, 6])
        defaultsFunctionName = methodName;
        try
            defaultOptions = feval(methodName);
        catch ME
            error("NANSEN:Options:SchemaNotFound", ...
                "Could not get default options from function ""%s"": %s", ...
                methodName, ME.message)
        end

        if isstruct(defaultOptions) && isfield(defaultOptions, "DefaultOptions")
            defaultOptions = defaultOptions.DefaultOptions; % Session method function
        end
    else
        error("NANSEN:Options:SchemaNotFound", ...
            "No function or class named ""%s"" was found", methodName)
    end

    if ~isstruct(defaultOptions) || ~isscalar(defaultOptions)
        error("NANSEN:Options:SchemaNotFound", ...
            "Default options of ""%s"" is not a struct", methodName)
    end

    descriptions = nansen.options.legacy.parseParameterComments( ...
        string(which(defaultsFunctionName)));

    schema = nansen.options.legacy.inferSchema(defaultOptions, methodName, ...
        Descriptions=descriptions);

    nansen.options.legacy.addPresetsFromPackage(schema, methodName)
end
