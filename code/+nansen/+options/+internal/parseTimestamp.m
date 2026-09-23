function t = parseTimestamp(str)
%parseTimestamp Parse an ISO 8601 string created by formatTimestamp
%
%   t = nansen.options.internal.parseTimestamp(str) returns a datetime in
%   UTC. Returns NaT for empty text.
%
%   See also nansen.options.internal.formatTimestamp

    arguments
        str (1,1) string
    end

    if strlength(str) == 0
        t = NaT("TimeZone", "UTC"); return
    end
    t = datetime(str, "InputFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'", "TimeZone", "UTC");
end
