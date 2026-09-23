function schema = getSchema(methodName)
%getSchema Get the options schema for a method
%
%   schema = nansen.options.getSchema(methodName) returns the options
%   schema (nansen.options.Schema) for the method (function or class) with
%   the given name.
%
%   The schema is found using the following conventions (in order):
%
%   1) A class with a static method getOptionsSchema() which returns a
%      nansen.options.Schema. This is the recommended way to define
%      options for new methods.
%
%   For methods that define options in one of the legacy ways, a schema
%   is inferred from the default options (schema.IsInferred is true):
%
%   2) A class with a static method getDefaultOptions() (e.g. classes that
%      inherit from nansen.mixin.HasOptions).
%   3) A class with a static method getOptions() (option adapters for
%      external toolboxes, nansen.wrapper.abstract.OptionsAdapter).
%   4) A function which returns a struct of options when called with no
%      inputs (optionally in a field called DefaultOptions, like session
%      method functions).
%
%   For legacy methods, presets are collected from a +presets package
%   located in the same package as the method, and descriptions are
%   parsed from trailing comments in the file which defines the defaults.
%
%   See also nansen.options.Schema

    methodName = char(methodName);

    if exist(methodName, 'class') == 8
        mc = meta.class.fromName(methodName);
        staticMethodNames = {mc.MethodList([mc.MethodList.Static]).Name};

        if any(strcmp(staticMethodNames, 'getOptionsSchema'))
            schema = feval([methodName, '.getOptionsSchema']);
            assert(isa(schema, 'nansen.options.Schema'), ...
                'NANSEN:Options:InvalidSchema', ...
                '%s.getOptionsSchema must return a nansen.options.Schema', methodName)
            if isempty(schema.Name); schema.Name = methodName; end
            return

        elseif any(strcmp(staticMethodNames, 'getDefaultOptions'))
            defaultsFunctionName = [methodName, '.getDefaultOptions'];

        elseif any(strcmp(staticMethodNames, 'getOptions'))
            defaultsFunctionName = [methodName, '.getOptions'];

        else
            error('NANSEN:Options:SchemaNotFound', ...
                'Could not find options for class "%s"', methodName)
        end

        defaultOptions = feval(defaultsFunctionName);

    elseif any(exist(methodName, 'file') == [2, 3, 6])
        defaultsFunctionName = methodName;
        try
            defaultOptions = feval(methodName);
        catch ME
            error('NANSEN:Options:SchemaNotFound', ...
                'Could not get default options from function "%s": %s', ...
                methodName, ME.message)
        end

        if isstruct(defaultOptions) && isfield(defaultOptions, 'DefaultOptions')
            defaultOptions = defaultOptions.DefaultOptions; % Session method function
        end
    else
        error('NANSEN:Options:SchemaNotFound', ...
            'No function or class named "%s" was found', methodName)
    end

    if ~isstruct(defaultOptions) || ~isscalar(defaultOptions)
        error('NANSEN:Options:SchemaNotFound', ...
            'Default options of "%s" is not a struct', methodName)
    end

    descriptions = nansen.options.internal.parseParameterComments( ...
        which(defaultsFunctionName));

    schema = nansen.options.Schema.fromStruct(defaultOptions, methodName, ...
        'Descriptions', descriptions);

    addLegacyPresets(schema, methodName)
end

function addLegacyPresets(schema, methodName)
%addLegacyPresets Add presets from a +presets package next to the method

    nameParts = strsplit(methodName, '.');
    if numel(nameParts) < 2; return; end

    packageName = strjoin(nameParts(1:end-1), '.');
    presetPackageName = [packageName, '.presets'];

    packageInfo = meta.package.fromName(presetPackageName);
    if isempty(packageInfo); return; end

    defaults = schema.getDefaults();

    for i = 1:numel(packageInfo.ClassList)
        presetClassName = packageInfo.ClassList(i).Name;
        try
            presetObject = feval(presetClassName);
            presetValues = presetObject.getOptions();
            presetValues = nansen.options.Schema.removeEditorConfigFields(presetValues);

            differences = nansen.options.internal.diffStruct(defaults, presetValues);
            differences = differences(strcmp({differences.Change}, 'modified'));

            overrides = struct();
            for j = 1:numel(differences)
                overrides = nansen.options.internal.setValue(overrides, ...
                    differences(j).Name, differences(j).ValueB);
            end

            schema.addPreset(presetObject.Name, overrides, presetObject.Description)
        catch ME
            warning('NANSEN:Options:PresetProblem', ...
                'Could not add preset "%s": %s', presetClassName, ME.message)
        end
    end
end
