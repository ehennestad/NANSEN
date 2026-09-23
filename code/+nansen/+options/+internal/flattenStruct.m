function [names, values] = flattenStruct(S, prefix)
%flattenStruct Flatten a nested struct into dotted names and leaf values
%
%   [names, values] = nansen.options.internal.flattenStruct(S) returns a
%   string array of dotted field paths (e.g. "Group.field") for all leaf
%   fields of the scalar struct S, together with a cell array of the
%   corresponding values.
%
%   Nested scalar structs with at least one field are traversed and
%   treated as groups. Struct arrays and structs without fields are
%   treated as leaf values.
%
%   Example:
%       S.A.b = 1; S.c = 'x';
%       [names, values] = nansen.options.internal.flattenStruct(S)
%       % names = ["A.b", "c"], values = {1, 'x'}

    arguments
        S (1,1) struct
        prefix (1,1) string = ""
    end

    names = string.empty(1, 0);
    values = cell(1, 0);

    fields = string(fieldnames(S))';

    for field = fields
        if prefix == ""
            name = field;
        else
            name = prefix + "." + field;
        end

        value = S.(field);

        if nansen.options.internal.isGroup(value)
            [subNames, subValues] = nansen.options.internal.flattenStruct(value, name);
            names = [names, subNames]; %#ok<AGROW>
            values = [values, subValues]; %#ok<AGROW>
        else
            names(end+1) = name; %#ok<AGROW>
            values{end+1} = value; %#ok<AGROW>
        end
    end
end
