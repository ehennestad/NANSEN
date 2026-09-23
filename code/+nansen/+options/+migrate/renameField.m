function S = renameField(S, oldName, newName, options)
%renameField Rename (move) a field in a struct of options
%
%   S = nansen.options.migrate.renameField(S, oldName, newName) moves the
%   value of field oldName to newName. Names can be dotted, e.g.
%   "Group.name". If oldName does not exist, S is returned unchanged, so
%   this is safe to use on partial structs (e.g. profile overrides).
%
%   S = nansen.options.migrate.renameField(S, oldName, newName, Convert=fcn)
%   also converts the value, e.g. for changing units.
%
%   Intended for use in schema migrations:
%       schema.addMigration("1.0.0", "2.0.0", @(S) nansen.options.migrate.renameField( ...
%           S, "binSize", "Preprocessing.binSize"))
%
%   See also nansen.options.Schema/addMigration

    arguments
        S (1,1) struct
        oldName (1,1) string
        newName (1,1) string
        options.Convert {nansen.options.internal.mustBeFunctionHandleOrEmpty} = []
    end

    if ~nansen.options.internal.hasValue(S, oldName); return; end

    value = nansen.options.internal.getValue(S, oldName);
    if ~isempty(options.Convert)
        value = options.Convert(value);
    end

    S = nansen.options.internal.removeValue(S, oldName);
    S = nansen.options.internal.setValue(S, newName, value);
end
