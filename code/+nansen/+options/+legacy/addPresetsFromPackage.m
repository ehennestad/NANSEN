function addPresetsFromPackage(schema, methodName)
%addPresetsFromPackage Add presets from a legacy +presets package
%
%   nansen.options.legacy.addPresetsFromPackage(schema, methodName) looks
%   for a +presets package in the same package as the method. Each class in
%   that package is a legacy preset with constant properties Name and
%   Description and a method getOptions. The presets are added to the
%   schema, with the values that differ from the defaults as overrides.

    arguments
        schema (1,1) nansen.options.Schema
        methodName (1,1) string
    end

    nameParts = split(methodName, ".");
    if numel(nameParts) < 2; return; end

    presetPackage = meta.package.fromName(char(strjoin([nameParts(1:end-1); "presets"], ".")));
    if isempty(presetPackage); return; end

    defaults = schema.getDefaults();

    for presetClass = reshape(presetPackage.ClassList, 1, [])
        try
            presetObject = feval(presetClass.Name);
            presetValues = nansen.options.legacy.removeConfigFields(presetObject.getOptions());
            presetValues = schema.conform(presetValues, Unknown="drop");

            overrides = nansen.options.internal.diffToStruct(defaults, presetValues);
            schema.addPreset(presetObject.Name, overrides, ...
                Description=presetObject.Description)
        catch ME
            warning("NANSEN:Options:PresetProblem", ...
                "Could not add preset ""%s"": %s", presetClass.Name, ME.message)
        end
    end
end
