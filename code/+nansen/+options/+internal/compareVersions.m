function result = compareVersions(versionA, versionB)
%compareVersions Compare two semantic version strings
%
%   result = nansen.options.internal.compareVersions(versionA, versionB)
%   returns -1 if versionA < versionB, 0 if they are equal and 1 if
%   versionA > versionB. Versions are strings like "1.2.3". Missing
%   components are treated as 0 and an empty version is treated as "0".

    arguments
        versionA (1,1) string
        versionB (1,1) string
    end

    a = parseVersion(versionA);
    b = parseVersion(versionB);

    n = max(numel(a), numel(b));
    a(end+1:n) = 0;
    b(end+1:n) = 0;

    idx = find(a ~= b, 1, "first");
    if isempty(idx)
        result = 0;
    else
        result = sign(a(idx) - b(idx));
    end
end

function numbers = parseVersion(versionStr)
    if strlength(versionStr) == 0; versionStr = "0"; end
    versionStr = regexprep(versionStr, "^[vV]", "");
    versionStr = regexprep(versionStr, "[-+].*$", ""); % Drop pre-release/build info
    numbers = str2double(split(versionStr, "."))';
    numbers(isnan(numbers)) = 0;
end
