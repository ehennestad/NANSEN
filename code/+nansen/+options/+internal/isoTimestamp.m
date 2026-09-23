function str = isoTimestamp()
%isoTimestamp Get current time as an ISO 8601 string in UTC
%
%   str = nansen.options.internal.isoTimestamp() returns a string like
%   '2024-01-31T13:45:00Z'

    try
        t = datetime('now', 'TimeZone', 'UTC', ...
            'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z''');
        str = char(t);
    catch % E.g. Octave, where datetime is not available.
        str = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>
    end
end
