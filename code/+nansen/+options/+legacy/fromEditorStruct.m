function values = fromEditorStruct(schema, S)
%fromEditorStruct Get conformed values from a legacy structeditor struct
%
%   values = nansen.options.legacy.fromEditorStruct(schema, S) removes
%   configuration fields (fieldname_) and conforms the values to the schema.
%
%   See also nansen.options.legacy.toEditorStruct

    arguments
        schema (1,1) nansen.options.Schema
        S (1,1) struct
    end

    values = schema.conform(nansen.options.legacy.removeConfigFields(S));
end
