function descriptions = parseParameterComments(filePath)
%parseParameterComments Parse descriptions of options from code comments
%
%   descriptions = nansen.options.internal.parseParameterComments(filePath)
%   reads a function file where options are defined as
%
%       P.Group.name = value;    % Description of parameter
%
%   and returns a containers.Map where keys are option names (without the
%   struct variable prefix, e.g. 'Group.name') and values are the
%   descriptions given in trailing comments. Configuration fields (names
%   ending with _) are ignored.
%
%   This is used for inferring schemas from legacy default options files.

    descriptions = containers.Map('KeyType', 'char', 'ValueType', 'char');

    if isempty(filePath) || ~isfile(filePath); return; end

    lines = strsplit(fileread(filePath), {'\r\n', '\n'});
    expression = '^\s*[A-Za-z]\w*\.([\w\.]+)\s*=.*?;\s*%\s*(.*\S)\s*$';

    for i = 1:numel(lines)
        tokens = regexp(lines{i}, expression, 'tokens', 'once');
        if isempty(tokens); continue; end

        name = tokens{1};
        if strcmp(name(end), '_'); continue; end

        descriptions(name) = tokens{2};
    end
end
