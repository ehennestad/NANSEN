classdef Migration
%nansen.options.Migration Converts options from one schema version to another
%
%   migration = nansen.options.Migration(fromVersion, toVersion, fcn, Description=text)
%
%   The function receives a struct of options and must return the
%   converted struct. The struct can be partial (e.g. only the values of a
%   profile that differ from defaults), so migration functions should only
%   modify fields that are present. The functions in nansen.options.migrate
%   (renameField, removeField, convertValue) do this.
%
%   See also nansen.options.Schema/addMigration nansen.options.migrate.renameField

    properties (SetAccess = immutable)
        FromVersion (1,1) string = "0.0.0"
        ToVersion (1,1) string = "0.0.0"
        Function (1,1) function_handle = @(S) S
        Description (1,1) string = ""
    end

    methods
        function obj = Migration(fromVersion, toVersion, fcn, options)
            arguments
                fromVersion (1,1) string {nansen.options.internal.mustBeVersion} = "0.0.0"
                toVersion (1,1) string {nansen.options.internal.mustBeVersion} = "0.0.0"
                fcn (1,1) function_handle = @(S) S
                options.Description (1,1) string = ""
            end

            if nargin == 0; return; end

            if nansen.options.internal.compareVersions(toVersion, fromVersion) <= 0
                error("NANSEN:Options:InvalidInput", ...
                    "toVersion (%s) must be greater than fromVersion (%s)", ...
                    toVersion, fromVersion)
            end

            obj.FromVersion = fromVersion;
            obj.ToVersion = toVersion;
            obj.Function = fcn;
            obj.Description = options.Description;
        end

        function S = apply(obj, S)
        %apply Apply migration to a struct of options
            arguments
                obj (1,1) nansen.options.Migration
                S (1,1) struct
            end
            S = obj.Function(S);
        end

        function str = describe(obj)
        %describe Get a short description of the migration
            arguments
                obj (1,1) nansen.options.Migration
            end
            str = sprintf("%s -> %s", obj.FromVersion, obj.ToVersion);
            if obj.Description ~= ""
                str = str + ": " + obj.Description;
            end
        end
    end
end
