function differences = diffStruct(structA, structB)
%diffStruct Find differences between two (nested) option structs
%
%   differences = nansen.options.internal.diffStruct(structA, structB)
%   returns a struct array with fields Name, ValueA, ValueB and Change for
%   each leaf field that differs between the two structs. Change is one of
%   'modified', 'added' (only in B) or 'removed' (only in A).

    [namesA, valuesA] = nansen.options.internal.flattenStruct(structA);
    [namesB, valuesB] = nansen.options.internal.flattenStruct(structB);

    differences = struct('Name', {}, 'ValueA', {}, 'ValueB', {}, 'Change', {});

    allNames = [namesA, setdiff(namesB, namesA, 'stable')];

    for i = 1:numel(allNames)
        name = allNames{i};
        [isInA, idxA] = ismember(name, namesA);
        [isInB, idxB] = ismember(name, namesB);

        if isInA && isInB
            if ~isequaln(valuesA{idxA}, valuesB{idxB}) || ...
                    ~strcmp(class(valuesA{idxA}), class(valuesB{idxB}))
                differences(end+1) = createEntry(name, valuesA{idxA}, valuesB{idxB}, 'modified'); %#ok<AGROW>
            end
        elseif isInA
            differences(end+1) = createEntry(name, valuesA{idxA}, [], 'removed'); %#ok<AGROW>
        else
            differences(end+1) = createEntry(name, [], valuesB{idxB}, 'added'); %#ok<AGROW>
        end
    end
end

function entry = createEntry(name, valueA, valueB, change)
    entry = struct('Name', name, 'ValueA', {valueA}, 'ValueB', {valueB}, 'Change', change);
end
