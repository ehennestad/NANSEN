function hash = sha256(data)
%sha256 Compute SHA-256 hash of text or bytes
%
%   hash = nansen.options.internal.sha256(data) returns the SHA-256 hash of
%   data as a lowercase hexadecimal character vector. data can be a
%   character vector (encoded as UTF-8) or a uint8 array.
%
%   Uses Java when available (MATLAB) and the builtin hash function
%   otherwise (Octave). Returns an empty char if neither is available.

    if ischar(data) || isstring(data)
        bytes = unicode2native(char(data), 'UTF-8');
    else
        bytes = uint8(data);
    end
    bytes = bytes(:)';

    hash = '';

    if exist('OCTAVE_VERSION', 'builtin')
        hash = feval('hash', 'sha256', char(bytes));
        
    elseif usejava('jvm')
        md = javaMethod('getInstance', 'java.security.MessageDigest', 'SHA-256');
        md.update(bytes);
        digest = typecast(md.digest(), 'uint8');
        hash = lower(reshape(dec2hex(digest, 2)', 1, []));
    end
end
