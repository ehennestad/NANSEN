function descriptions = parseParameterComments(filePath)
%parseParameterComments Parse descriptions of options from code comments
%
%   descriptions = nansen.options.legacy.parseParameterComments(filePath)
%   reads a function file where options are defined as
%
%       P.Group.name = value;    % Description of parameter
%
%   and returns a struct with the same structure as the options, where
%   values are the descriptions given in trailing comments. Configuration
%   fields (names ending with _) are ignored.

    arguments
        filePath (1,1) string
    end

    descriptions = struct();
    if filePath == "" || ~isfile(filePath); return; end

    lines = readlines(filePath);
    expression = "^\s*[A-Za-z]\w*\.([\w\.]+)\s*=.*?;\s*%\s*(.*\S)\s*$";
    tokens = regexp(lines, expression, "tokens", "once");

    for i = 1:numel(tokens)
        if isempty(tokens{i}); continue; end

        name = tokens{i}(1);
        if endsWith(name, "_"); continue; end

        try
            descriptions = nansen.options.internal.setValue(descriptions, name, tokens{i}(2));
        catch
            % Skip names that conflict with earlier names
        end
    end
end
