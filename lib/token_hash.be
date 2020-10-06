# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Cryptographic Token Hashing, Salted Digests & Authorization Signatures
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import string_util as StringUtil

class TokenHash
    # FNV-1a 64-bit Prime and Offset Basis constants
    static var FNV_OFFSET_64 = 0xCBF29CE484222325
    static var FNV_PRIME_64  = 0x100000001B3

    # Compute a 64-bit salted hash of an input string
    static def hash_salted(input_str, salt_str)
        if input_str == nil
            input_str = ""
        end
        if salt_str == nil
            salt_str = "stanchion-default-salt"
        end

        var combined = salt_str + ":" + input_str
        var n = size(combined)
        var h = TokenHash.FNV_OFFSET_64

        for i : 0 .. (n - 1)
            var b = string.byte(combined[i])
            h = h ^ b
            h = (h * TokenHash.FNV_PRIME_64) & 0xFFFFFFFFFFFFFFFF
        end

        # Avalanche mix to ensure uniform distribution
        h = h ^ (h >> 33)
        h = (h * 0xFF51AFD7ED558CCD) & 0xFFFFFFFFFFFFFFFF
        h = h ^ (h >> 33)
        h = (h * 0xC4CEB9FE1A85EC53) & 0xFFFFFFFFFFFFFFFF
        h = h ^ (h >> 33)

        return h
    end

    # Return a 16-character uppercase hex digest of the hashed token
    static def hex_digest(input_str, salt_str)
        var h = TokenHash.hash_salted(input_str, salt_str)
        return StringUtil.int_to_hex(h, 16)
    end

    # Compute message authentication tag across structured transaction payload
    static def compute_mac(payload_map, secret_key)
        if payload_map == nil
            return ""
        end
        var keys = payload_map.keys()
        # Create deterministic concatenated string
        var canon = ""
        for k : keys
            canon = canon + str(k) + "=" + str(payload_map[k]) + ";"
        end
        return TokenHash.hex_digest(canon, secret_key)
    end

    # Constant-time comparison between two hex digests to prevent timing attacks
    static def secure_compare(digest_a, digest_b)
        if digest_a == nil || digest_b == nil
            return false
        end
        var len_a = size(digest_a)
        var len_b = size(digest_b)
        if len_a != len_b
            return false
        end
        var diff = 0
        for i : 0 .. (len_a - 1)
            var b_a = string.byte(digest_a[i])
            var b_b = string.byte(digest_b[i])
            diff = diff | (b_a ^ b_b)
        end
        return (diff == 0)
    end
end

return TokenHash
