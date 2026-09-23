function schema = inferSchema(S, methodName, options)
%inferSchema Infer a schema from a legacy struct of default options
%
%   schema = nansen.options.legacy.inferSchema(S, methodName) creates a
%   schema where the default values are taken from S. Configuration
%   fields (fieldname_) used by the legacy structeditor app are converted
%   to parameter attributes:
%
%       {'a', 'b'}                 -> Choices
%       'internal' / 'ignore'      -> Internal = true
%       'transient'                -> Transient = true
%       'uigetdir'                 -> Widget = "folder"
%       'uigetfile' / 'uiputfile'  -> Widget = "file"
%       'uisetcolor'               -> Widget = "color"
%       struct('type', 'slider')   -> Widget = "slider" (+ Min/Max)
%       struct('type', 'multilinechar') -> Widget = "multiline"
%
%   schema = nansen.options.legacy.inferSchema(S, methodName, Name=Value)
%
%   NAME-VALUE ARGUMENTS:
%       Version      : Schema version (default "1.0.0")
%       Descriptions : Struct with descriptions (same structure as S), see
%                      nansen.options.legacy.parseParameterComments
%       Validators   : Struct with validation functions (same structure as
%                      S), e.g. the V struct of legacy getDefaultParameters
%                      functions.

    arguments
        S (1,1) struct
        methodName (1,1) string = ""
        options.Version (1,1) string = "1.0.0"
        options.Descriptions (1,1) struct = struct()
        options.Validators (1,1) struct = struct()
    end

    schema = nansen.options.Schema(methodName, Version=options.Version);
    schema.markAsInferred()

    [configNames, configValues] = collectConfigFields(S, "");
    S = nansen.options.legacy.removeConfigFields(S);
    [names, values] = nansen.options.internal.flattenStruct(S);

    for i = 1:numel(names)
        attributes = struct();

        [hasConfig, idx] = ismember(names(i) + "_", configNames);
        if hasConfig
            attributes = configToAttributes(configValues{idx}, values{i});
        end

        if nansen.options.internal.hasValue(options.Descriptions, names(i))
            attributes.Description = string( ...
                nansen.options.internal.getValue(options.Descriptions, names(i)));
        end

        if nansen.options.internal.hasValue(options.Validators, names(i))
            validatorFcn = nansen.options.internal.getValue(options.Validators, names(i));
            if isa(validatorFcn, "function_handle")
                attributes.Validator = validatorFcn;
            end
        end

        attributeArgs = namedargs2cell(attributes);
        try
            schema.addParameter(names(i), values{i}, attributeArgs{:});
        catch ME
            % If an inferred attribute is incompatible with the default
            % value (e.g. choices that do not include the default), add the
            % parameter without attributes
            warning("NANSEN:Options:InferenceProblem", ...
                "Could not infer attributes for ""%s"" of ""%s"": %s", ...
                names(i), methodName, ME.message)
            schema.addParameter(names(i), values{i});
        end
    end
end

function [names, values] = collectConfigFields(S, prefix)
%collectConfigFields Get (dotted) names and values of legacy config fields
    names = string.empty(1, 0);
    values = cell(1, 0);
    for field = string(fieldnames(S))'
        name = field;
        if prefix ~= ""; name = prefix + "." + field; end

        if endsWith(field, "_")
            names(end+1) = name; %#ok<AGROW>
            values{end+1} = S.(field); %#ok<AGROW>
        elseif nansen.options.internal.isGroup(S.(field))
            [subNames, subValues] = collectConfigFields(S.(field), name);
            names = [names, subNames]; %#ok<AGROW>
            values = [values, subValues]; %#ok<AGROW>
        end
    end
end

function attributes = configToAttributes(config, defaultValue)
%configToAttributes Convert structeditor config field value to attributes

    attributes = struct();

    if iscell(config)
        if ischar(defaultValue) || isstring(defaultValue) || isnumeric(defaultValue)
            attributes.Choices = reshape(config, 1, []);
        end

    elseif ischar(config) || isstring(config)
        switch string(config)
            case {"internal", "ignore"}
                attributes.Internal = true;
            case "transient"
                attributes.Transient = true;
            case "uigetdir"
                attributes.Widget = "folder";
            case {"uigetfile", "uiputfile"}
                attributes.Widget = "file";
            case "uisetcolor"
                attributes.Widget = "color";
        end

    elseif isstruct(config) && isfield(config, "type")
        switch string(config.type)
            case "slider"
                attributes.Widget = "slider";
                if isfield(config, "args")
                    args = config.args;
                    for i = 1:2:numel(args)-1
                        if strcmpi(args{i}, "Min")
                            attributes.Min = args{i+1};
                        elseif strcmpi(args{i}, "Max")
                            attributes.Max = args{i+1};
                        end
                    end
                end
            case "multilinechar"
                attributes.Widget = "multiline";
        end
    end
end
