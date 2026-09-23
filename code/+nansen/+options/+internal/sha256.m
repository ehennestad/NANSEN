function hash = sha256(data)
%sha256 Compute SHA-256 hash of text or bytes
%
%   hash = nansen.options.internal.sha256(data) returns the SHA-256 hash of
%   data as a lowercase hexadecimal string. data can be text (encoded as
%   UTF-8) or a uint8 array.

    arguments
        data {mustBeA(data, ["char", "string", "uint8"])}
    end

    if isa(data, "uint8")
        bytes = data(:)';
    else
        bytes = unicode2native(char(data), "UTF-8");
    end

    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(typecast(bytes, "int8")); % int8 maps exactly to Java byte
    digest = typecast(md.digest(), "uint8");
    hash = string(lower(reshape(dec2hex(digest, 2)', 1, [])));
end
