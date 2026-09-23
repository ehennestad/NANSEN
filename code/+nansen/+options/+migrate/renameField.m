function S = renameField(S, oldName, newName, conversionFcn)
%renameField Rename (move) a field in a struct of options
%
%   S = nansen.options.migrate.renameField(S, oldName, newName) moves the
%   value of field oldName to newName. Names can be dotted, e.g.
%   'Group.name'. If oldName does not exist, S is returned unchanged, so
%   this is safe to use on partial structs (e.g. profile overrides).
%
%   S = nansen.options.migrate.renameField(S, oldName, newName, conversionFcn)
%   also converts the value using conversionFcn, e.g. for changing units.
%
%   Intended for use in schema migrations:
%       schema.addMigration('1.0.0', '1.1.0', ...
%           @(S) nansen.options.migrate.renameField(S, 'binSize', 'Preprocessing.binSize'))
%
%   See also nansen.options.Schema/addMigration

    if ~nansen.options.internal.hasValue(S, oldName); return; end

    value = nansen.options.internal.getValue(S, oldName);
    if nargin >= 4 && ~isempty(conversionFcn)
        value = conversionFcn(value);
    end

    S = nansen.options.internal.removeValue(S, oldName);
    S = nansen.options.internal.setValue(S, newName, value);
end
