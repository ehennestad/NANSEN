function hash = computeHash(value)
%computeHash Compute a SHA-256 hash (fingerprint) of a MATLAB value
%
%   hash = nansen.options.internal.computeHash(value) returns a hash of
%   the canonical representation of value. Equal values (including class
%   and size) give equal hashes regardless of struct field order.
%
%   See also nansen.options.internal.canonicalString

    hash = nansen.options.internal.sha256( ...
        nansen.options.internal.canonicalString(value) );
end
