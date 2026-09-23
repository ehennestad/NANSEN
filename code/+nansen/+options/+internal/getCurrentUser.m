function userName = getCurrentUser()
%getCurrentUser Get the name of the current operating system user
    userName = getenv('USER');
    if isempty(userName)
        userName = getenv('USERNAME'); % Windows
    end
end
