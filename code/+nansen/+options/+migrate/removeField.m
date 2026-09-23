function S = removeField(S, name)
%removeField Remove an obsolete field from a struct of options
%
%   S = nansen.options.migrate.removeField(S, name) removes the (dotted)
%   field name if it exists.
%
%   See also nansen.options.Schema/addMigration

    S = nansen.options.internal.removeValue(S, name);
end
