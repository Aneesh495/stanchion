# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# RFC 4122 Version 4 UUID Generator, Validator & Canonical Formatter
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import string_util as StringUtil

# Fast 64-bit XorShift PRNG for entropy in embedded environments
class XorShift64
    var state

    def init(seed)
        if seed == nil || seed == 0
            # Default fallback seed
            self.state = 88172645463325252
        else
            self.state = int(seed)
        end
    end

    def next_u32()
        # 64-bit xorshift: x ^= x << 13; x ^= x >> 7; x ^= x << 17;
        var x = self.state
        x = x ^ ((x << 13) & 0xFFFFFFFFFFFFFFFF)
        x = x ^ (x >> 7)
        x = x ^ ((x << 17) & 0xFFFFFFFFFFFFFFFF)
        self.state = x
        return (x >> 16) & 0xFFFFFFFF
    end

    def next_byte()
        return self.next_u32() & 0xFF
    end
end

class UUID
    static var _rng
    static var _seed_init

    static def _get_rng()
        if UUID._rng == nil
            var seed = 123456789
            # Try to grab monotonic time if host native function exists
            try
                seed = host_monotonic_us()
            except .. as e
                seed = 987654321
            end
            UUID._rng = XorShift64(seed)
        end
        return UUID._rng
    end

    # Generate a canonical RFC 4122 v4 UUID string
    # e.g. "f47ac10b-58cc-4372-a567-0e02b2c3d479"
    static def v4()
        var rng = UUID._get_rng()
        var bytes = []
        for i : 0 .. 15
            bytes.push(rng.next_byte())
        end

        # Set version to 4: byte 6 bits 4-7 = 0100
        bytes[6] = (bytes[6] & 0x0F) | 0x40

        # Set variant to RFC 4122: byte 8 bits 6-7 = 10
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        var hex_str = StringUtil.bytes_to_hex(bytes)
        hex_str = string.tolower(hex_str)

        # Format 8-4-4-4-12
        var p1 = hex_str[0 .. 7]
        var p2 = hex_str[8 .. 11]
        var p3 = hex_str[12 .. 15]
        var p4 = hex_str[16 .. 19]
        var p5 = hex_str[20 .. 31]

        return string.format("%s-%s-%s-%s-%s", p1, p2, p3, p4, p5)
    end

    # Check whether a string matches canonical UUID format
    static def is_valid(uuid_str)
        if uuid_str == nil || size(uuid_str) != 36
            return false
        end
        if uuid_str[8] != "-" || uuid_str[13] != "-" || uuid_str[18] != "-" || uuid_str[23] != "-"
            return false
        end
        for i : 0 .. 35
            if i == 8 || i == 13 || i == 18 || i == 23
                continue
            end
            var ch = uuid_str[i]
            var b = string.byte(ch)
            var is_hex = (b >= 48 && b <= 57) || (b >= 97 && b <= 102) || (b >= 65 && b <= 70)
            if !is_hex
                return false
            end
        end
        return true
    end

    # Nil UUID constant
    static def nil_uuid()
        return "00000000-0000-0000-0000-000000000000"
    end
end

return UUID
