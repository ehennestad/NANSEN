classdef ProfileType
%nansen.options.ProfileType Type of an options profile
    enumeration
        Defaults    % The default values of a schema (defined in code)
        Preset      % A preset defined in code by developers (read-only)
        User        % A profile saved by a user
    end
end
