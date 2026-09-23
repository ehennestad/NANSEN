function S = removeConfigFields(S)
%removeConfigFields Remove legacy structeditor configuration fields
%
%   S = nansen.options.legacy.removeConfigFields(S) removes all fields
%   ending with "_" (e.g. "name_") at any level of a nested struct.

    arguments
        S (1,1) struct
    end

    for field = string(fieldnames(S))'
        if endsWith(field, "_")
            S = rmfield(S, field);
        elseif nansen.options.internal.isGroup(S.(field))
            S.(field) = nansen.options.legacy.removeConfigFields(S.(field));
        end
    end
end
