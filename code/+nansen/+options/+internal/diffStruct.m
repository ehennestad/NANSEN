function differences = diffStruct(structA, structB)
%diffStruct Find differences between two (nested) option structs
%
%   differences = nansen.options.internal.diffStruct(structA, structB)
%   returns a table with variables Name, ValueA, ValueB and Change for each
%   leaf field that differs between the two structs. Change is a
%   categorical: "modified", "added" (only in B) or "removed" (only in A).

    arguments
        structA (1,1) struct
        structB (1,1) struct
    end

    [namesA, valuesA] = nansen.options.internal.flattenStruct(structA);
    [namesB, valuesB] = nansen.options.internal.flattenStruct(structB);

    allNames = [namesA, setdiff(namesB, namesA, "stable")];

    Name = string.empty(0, 1);
    ValueA = cell(0, 1);
    ValueB = cell(0, 1);
    Change = strings(0, 1);

    for name = allNames
        [isInA, idxA] = ismember(name, namesA);
        [isInB, idxB] = ismember(name, namesB);

        if isInA && isInB
            a = valuesA{idxA}; b = valuesB{idxB};
            if isequaln(a, b) && strcmp(class(a), class(b))
                continue
            end
            change = "modified";
        elseif isInA
            a = valuesA{idxA}; b = [];
            change = "removed";
        else
            a = []; b = valuesB{idxB};
            change = "added";
        end

        Name(end+1, 1) = name; %#ok<AGROW>
        ValueA{end+1, 1} = a; %#ok<AGROW>
        ValueB{end+1, 1} = b; %#ok<AGROW>
        Change(end+1, 1) = change; %#ok<AGROW>
    end

    Change = categorical(Change, ["modified", "added", "removed"]);
    differences = table(Name, ValueA, ValueB, Change);
end
