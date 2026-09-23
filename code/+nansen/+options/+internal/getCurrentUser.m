function userName = getCurrentUser()
%getCurrentUser Get the name of the current operating system user
    userName = string(getenv("USER"));
    if userName == ""
        userName = string(getenv("USERNAME")); % Windows
    end
end
