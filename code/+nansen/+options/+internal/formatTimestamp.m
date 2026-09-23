function str = formatTimestamp(t)
%formatTimestamp Format a datetime as an ISO 8601 string in UTC
%
%   str = nansen.options.internal.formatTimestamp(t) returns a string like
%   "2024-01-31T13:45:00Z". Returns "" for NaT.
%
%   See also nansen.options.internal.parseTimestamp

    arguments
        t (1,1) datetime
    end

    if isnat(t)
        str = ""; return
    end
    if isempty(t.TimeZone)
        t.TimeZone = "local";
    end
    t.TimeZone = "UTC";
    str = string(t, "yyyy-MM-dd'T'HH:mm:ss'Z'");
end
