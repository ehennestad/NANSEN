function info = getGitInfo(folderPath, includeStatus)
%getGitInfo Get commit information for the git repository containing a folder
%
%   info = nansen.options.internal.getGitInfo(folderPath) returns a struct
%   with the following fields:
%       RepositoryPath : Root folder of the repository ('' if not in a repository)
%       Commit         : Full hash of the checked out commit
%       Branch         : Name of checked out branch ('' if detached HEAD)
%       RemoteUrl      : Url of the "origin" remote, if any
%       IsDirty        : true if there are uncommitted changes or untracked
%                        files, false if not, [] if unknown.
%
%   The commit, branch and remote are read directly from the .git folder,
%   so git does not need to be installed. The IsDirty flag requires git and
%   is only computed if includeStatus is true (default = false).

    if nargin < 2; includeStatus = false; end

    info = struct('RepositoryPath', '', 'Commit', '', 'Branch', '', ...
        'RemoteUrl', '', 'IsDirty', []);

    [repoPath, gitDir] = findRepositoryRoot(folderPath);
    if isempty(repoPath); return; end

    info.RepositoryPath = repoPath;

    try
        headStr = strtrim(fileread(fullfile(gitDir, 'HEAD')));

        if strncmp(headStr, 'ref:', 4)
            refName = strtrim(headStr(5:end));
            info.Branch = regexprep(refName, '^refs/heads/', '');
            info.Commit = resolveRef(gitDir, refName);
        else
            info.Commit = headStr; % Detached HEAD
        end
    catch
        % Leave fields empty
    end

    info.RemoteUrl = getRemoteUrl(gitDir);

    if includeStatus
        info.IsDirty = getDirtyStatus(repoPath);
    end
end

function [repoPath, gitDir] = findRepositoryRoot(folderPath)

    repoPath = ''; gitDir = '';
    currentPath = char(folderPath);

    while true
        candidate = fullfile(currentPath, '.git');
        if isfolder(candidate)
            repoPath = currentPath; gitDir = candidate;
            return
        elseif isfile(candidate) % Worktree or submodule: "gitdir: <path>"
            txt = strtrim(fileread(candidate));
            if strncmp(txt, 'gitdir:', 7)
                gitDir = strtrim(txt(8:end));
                if ~isAbsolutePath(gitDir)
                    gitDir = fullfile(currentPath, gitDir);
                end
                repoPath = currentPath;
            end
            return
        end

        parentPath = fileparts(currentPath);
        if isempty(parentPath) || strcmp(parentPath, currentPath)
            return
        end
        currentPath = parentPath;
    end
end

function commit = resolveRef(gitDir, refName)

    commit = '';

    % Worktrees keep refs in the common git dir
    searchDirs = {gitDir};
    commonDirFile = fullfile(gitDir, 'commondir');
    if isfile(commonDirFile)
        commonDir = strtrim(fileread(commonDirFile));
        if ~isAbsolutePath(commonDir)
            commonDir = fullfile(gitDir, commonDir);
        end
        searchDirs{end+1} = commonDir;
    end

    for i = 1:numel(searchDirs)
        refFile = fullfile(searchDirs{i}, strrep(refName, '/', filesep));
        if isfile(refFile)
            commit = strtrim(fileread(refFile));
            return
        end

        packedRefsFile = fullfile(searchDirs{i}, 'packed-refs');
        if isfile(packedRefsFile)
            lines = strsplit(fileread(packedRefsFile), {'\r\n', '\n'});
            for j = 1:numel(lines)
                parts = strsplit(strtrim(lines{j}), ' ');
                if numel(parts) == 2 && strcmp(parts{2}, refName)
                    commit = parts{1};
                    return
                end
            end
        end
    end
end

function url = getRemoteUrl(gitDir)
    url = '';
    configFile = fullfile(gitDir, 'config');
    if ~isfile(configFile)
        commonDirFile = fullfile(gitDir, 'commondir');
        if isfile(commonDirFile)
            configFile = fullfile(gitDir, strtrim(fileread(commonDirFile)), 'config');
        end
    end
    if ~isfile(configFile); return; end

    txt = fileread(configFile);
    tokens = regexp(txt, '\[remote "origin"\][^\[]*?url\s*=\s*(\S+)', 'tokens', 'once');
    if ~isempty(tokens)
        % Remove credentials, if any (https://user:token@host/...)
        url = regexprep(tokens{1}, '^(\w+://)[^/@]+@', '$1');
    end
end

function isDirty = getDirtyStatus(repoPath)
    isDirty = [];
    try
        % Note: untracked files are included, because new (untracked) 
        % code files on the path may also affect results.
        command = sprintf('git -C "%s" status --porcelain', repoPath);
        [status, output] = system(command);
        if status == 0
            isDirty = ~isempty(strtrim(output));
        end
    catch
        % git not available
    end
end

function tf = isAbsolutePath(pathStr)
    tf = strncmp(pathStr, '/', 1) || ~isempty(regexp(pathStr, '^[A-Za-z]:[\\/]', 'once')) ...
        || strncmp(pathStr, '\\', 2);
end
