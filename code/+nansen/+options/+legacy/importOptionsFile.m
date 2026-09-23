function imported = importOptionsFile(manager, filePath)
%importOptionsFile Import custom options saved by nansen.manage.OptionsManager
%
%   imported = nansen.options.legacy.importOptionsFile(manager, filePath)
%   imports all custom options sets from a MAT file saved by the legacy
%   options manager as profiles, and returns the names of the imported
%   profiles. Options sets with names that already exist are skipped.
%   If the default options set of the legacy file was imported, it is set
%   as the default profile.

    arguments
        manager (1,1) nansen.options.Manager
        filePath (1,1) string
    end

    imported = string.empty(1, 0);
    if filePath == "" || ~isfile(filePath); return; end

    S = load(filePath);
    if ~isfield(S, "OptionsEntries"); return; end

    for entry = reshape(S.OptionsEntries, 1, [])
        name = string(entry.Name);
        if entry.Type ~= "Custom" || manager.hasProfile(name)
            continue
        end

        try
            values = nansen.options.legacy.removeConfigFields(entry.Options);
            values = manager.Schema.conform(values, Unknown="warn");

            description = string(entry.Description);
            if description == ""
                description = "Imported from legacy options (created " + ...
                    string(entry.DateCreated) + ")";
            end

            manager.createProfile(name, values, Description=description);
            imported(end+1) = name; %#ok<AGROW>
        catch ME
            warning("NANSEN:Options:ImportFailed", ...
                "Could not import options ""%s"": %s", name, ME.message)
        end
    end

    if isfield(S, "DefaultOptionsName") && ismember(string(S.DefaultOptionsName), imported)
        manager.setDefaultProfile(S.DefaultOptionsName)
    end
end
