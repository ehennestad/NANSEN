function info = getGitInfo(folderPath, options)
%getGitInfo Get commit information for the git repository containing a folder
%
%   info = nansen.options.internal.getGitInfo(folderPath) returns a struct
%   with the following fields:
%       RepositoryPath : Root folder of the repository ("" if not in a repository)
%       Commit         : Full hash of the checked out commit
%       Branch         : Name of checked out branch ("" if detached HEAD)
%       RemoteUrl      : Url of the "origin" remote, if any (without credentials)
%       IsDirty        : true if there are uncommitted changes or untracked
%                        files, false if not, [] if unknown.
%
%   The commit, branch and remote are read directly from the .git folder,
%   so git does not need to be installed.
%
%   info = nansen.options.internal.getGitInfo(folderPath, IncludeStatus=true)
%   also computes IsDirty. This requires git to be installed.

    arguments
        folderPath (1,1) string {mustBeFolder}
        options.IncludeStatus (1,1) logical = false
    end

    info = struct("RepositoryPath", "", "Commit", "", "Branch", "", ...
        "RemoteUrl", "", "IsDirty", []);

    [repoPath, gitDir] = findRepositoryRoot(folderPath);
    if repoPath == ""; return; end

    info.RepositoryPath = repoPath;
    commonDir = getCommonDir(gitDir);

    try
        headStr = strtrim(string(fileread(fullfile(gitDir, "HEAD"))));
        if startsWith(headStr, "ref:")
            refName = strtrim(extractAfter(headStr, "ref:"));
            info.Branch = replace(refName, "refs/heads/", "");
            info.Commit = resolveRef([gitDir, commonDir], refName);
        else
            info.Commit = headStr; % Detached HEAD
        end
    catch
        % Leave fields empty
    end

    info.RemoteUrl = getRemoteUrl(commonDir);

    if options.IncludeStatus
        info.IsDirty = getDirtyStatus(repoPath);
    end
end

function [repoPath, gitDir] = findRepositoryRoot(currentPath)

    repoPath = ""; gitDir = "";

    while true
        candidate = fullfile(currentPath, ".git");
        if isfolder(candidate)
            repoPath = currentPath; gitDir = candidate;
            return
        elseif isfile(candidate) % Worktree or submodule: "gitdir: <path>"
            txt = strtrim(string(fileread(candidate)));
            if startsWith(txt, "gitdir:")
                gitDir = makeAbsolute(strtrim(extractAfter(txt, "gitdir:")), currentPath);
                repoPath = currentPath;
            end
            return
        end

        parentPath = string(fileparts(currentPath));
        if parentPath == "" || parentPath == currentPath
            return
        end
        currentPath = parentPath;
    end
end

function commonDir = getCommonDir(gitDir)
%getCommonDir Worktrees keep refs and config in a common git dir
    commonDir = gitDir;
    commonDirFile = fullfile(gitDir, "commondir");
    if isfile(commonDirFile)
        commonDir = makeAbsolute(strtrim(string(fileread(commonDirFile))), gitDir);
    end
end

function commit = resolveRef(searchDirs, refName)
    commit = "";
    for searchDir = unique(searchDirs, "stable")
        refFile = fullfile(searchDir, replace(refName, "/", filesep));
        if isfile(refFile)
            commit = strtrim(string(fileread(refFile)));
            return
        end

        packedRefsFile = fullfile(searchDir, "packed-refs");
        if isfile(packedRefsFile)
            lines = splitlines(string(fileread(packedRefsFile)));
            tokens = regexp(lines, "^([0-9a-f]{40})\s+(\S+)$", "tokens", "once");
            for i = 1:numel(tokens)
                if ~isempty(tokens{i}) && tokens{i}(2) == refName
                    commit = tokens{i}(1);
                    return
                end
            end
        end
    end
end

function url = getRemoteUrl(gitDir)
    url = "";
    configFile = fullfile(gitDir, "config");
    if ~isfile(configFile); return; end

    txt = string(fileread(configFile));
    tokens = regexp(txt, "\[remote ""origin""\][^\[]*?url\s*=\s*(\S+)", "tokens", "once");
    if ~isempty(tokens)
        % Remove credentials, if any (https://user:token@host/...)
        url = regexprep(tokens(1), "^(\w+://)[^/@]+@", "$1");
    end
end

function isDirty = getDirtyStatus(repoPath)
    isDirty = [];
    try
        % Note: untracked files are included, because new (untracked)
        % code files on the path may also affect results.
        [status, output] = system(sprintf('git -C "%s" status --porcelain', repoPath));
        if status == 0
            isDirty = strtrim(output) ~= "";
        end
    catch
        % git not available
    end
end

function pathStr = makeAbsolute(pathStr, basePath)
    isAbsolute = startsWith(pathStr, ["/", "\\"]) || ...
        ~isempty(regexp(pathStr, "^[A-Za-z]:[\\/]", "once"));
    if ~isAbsolute
        pathStr = string(fullfile(basePath, pathStr));
    end
end
