function S = diffToStruct(reference, values)
%diffToStruct Get the values that differ from a reference as a nested struct
%
%   S = nansen.options.internal.diffToStruct(reference, values) returns a
%   (partial) nested struct containing all leaf values of values that are
%   different from, or not present in, reference.

    arguments
        reference (1,1) struct
        values (1,1) struct
    end

    differences = nansen.options.internal.diffStruct(reference, values);
    differences = differences(differences.Change ~= "removed", :);

    S = struct();
    for i = 1:height(differences)
        S = nansen.options.internal.setValue(S, ...
            differences.Name(i), differences.ValueB{i});
    end
end
