function S = toEditorStruct(schema, values)
%toEditorStruct Create a struct for the legacy structeditor app
%
%   S = nansen.options.legacy.toEditorStruct(schema, values) adds
%   configuration fields (fieldname_) which the structeditor app uses to
%   show dropdowns, sliders, file browsers etc. values defaults to the
%   default values of the schema.
%
%   This is also the format of options used by nansen.manage.OptionsManager
%   and by methods that define options in the legacy way.
%
%   See also nansen.options.legacy.fromEditorStruct

    arguments
        schema (1,1) nansen.options.Schema
        values (1,1) struct = schema.getDefaults()
    end

    S = values;
    for parameter = schema.Parameters
        config = getEditorConfig(parameter);
        if ~isempty(config)
            S = nansen.options.internal.setValue(S, parameter.Name + "_", config);
        end
    end
end

function config = getEditorConfig(parameter)
%getEditorConfig Get value of the structeditor config field for a parameter

    config = [];

    if parameter.Internal
        config = 'internal';
    elseif ~isempty(parameter.Choices)
        config = parameter.Choices;
    else
        switch parameter.Widget
            case "slider"
                args = {'Min', parameter.Min, 'Max', parameter.Max};
                if parameter.Integer && isfinite(parameter.Min) && isfinite(parameter.Max)
                    args = [args, {'nTicks', parameter.Max - parameter.Min + 1, ...
                        'TooltipPrecision', 0}];
                end
                config = struct('type', 'slider', 'args', {args});
            case "multiline"
                config = struct('type', 'multilinechar', 'args', {{}});
            case "folder"
                config = 'uigetdir';
            case "file"
                config = 'uigetfile';
            case "color"
                config = 'uisetcolor';
            otherwise
                if parameter.Transient
                    config = 'transient';
                end
        end
    end
end
