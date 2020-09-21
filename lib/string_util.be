# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# String Utilities, Hex Encoding/Decoding, Padding & Identifier Sanitization
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string

class StringUtil
    # Trim leading and trailing whitespace characters
    static def trim(s)
        if s == nil
            return ""
        end
        var n = size(s)
        if n == 0
            return ""
        end

        var start_idx = 0
        while start_idx < n
            var ch = s[start_idx]
            if ch != " " && ch != "\t" && ch != "\r" && ch != "\n"
                break
            end
            start_idx = start_idx + 1
        end

        if start_idx >= n
            return ""
        end

        var end_idx = n - 1
        while end_idx >= start_idx
            var ch = s[end_idx]
            if ch != " " && ch != "\t" && ch != "\r" && ch != "\n"
                break
            end
            end_idx = end_idx - 1
        end

        return s[start_idx .. end_idx]
    end

    # Pad string on the left to target width with fill_char
    static def lpad(s, width, fill_char)
        s = str(s)
        if fill_char == nil || fill_char == ""
            fill_char = " "
        end
        var cur_len = size(s)
        if cur_len >= width
            return s
        end
        var pad_len = width - cur_len
        var padding = ""
        for i : 1 .. pad_len
            padding = padding + fill_char
        end
        return padding + s
    end

    # Pad string on the right to target width with fill_char
    static def rpad(s, width, fill_char)
        s = str(s)
        if fill_char == nil || fill_char == ""
            fill_char = " "
        end
        var cur_len = size(s)
        if cur_len >= width
            return s
        end
        var pad_len = width - cur_len
        var padding = ""
        for i : 1 .. pad_len
            padding = padding + fill_char
        end
        return s + padding
    end

    # Convert an integer into a fixed-width uppercase hex string
    static def int_to_hex(val, width)
        var hex_digits = "0123456789ABCDEF"
        val = int(val)
        if val == 0
            return StringUtil.lpad("0", width, "0")
        end
        var res = ""
        var temp = val
        if temp < 0
            temp = temp + 4294967296
        end
        while temp > 0
            var rem = temp % 16
            res = hex_digits[rem] + res
            temp = temp / 16
        end
        return StringUtil.lpad(res, width, "0")
    end

    # Parse a hex character to integer value (0-15), returns -1 if invalid
    static def hex_digit_value(ch)
        if ch == nil || size(ch) == 0
            return -1
        end
        var b = string.byte(ch)
        # '0'-'9' (48-57)
        if b >= 48 && b <= 57
            return b - 48
        end
        # 'A'-'F' (65-70)
        if b >= 65 && b <= 70
            return b - 65 + 10
        end
        # 'a'-'f' (97-102)
        if b >= 97 && b <= 102
            return b - 97 + 10
        end
        return -1
    end

    # Parse a hex string to integer
    static def hex_to_int(hex_str)
        if hex_str == nil
            return 0
        end
        var s = StringUtil.trim(hex_str)
        if string.startswith(s, "0x") || string.startswith(s, "0X")
            s = s[2 .. (size(s) - 1)]
        end
        var n = size(s)
        var val = 0
        for i : 0 .. (n - 1)
            var ch = s[i]
            var d = StringUtil.hex_digit_value(ch)
            if d < 0
                break
            end
            val = val * 16 + d
        end
        return val
    end

    # Convert raw bytes list (numbers 0-255) to hex string
    static def bytes_to_hex(byte_list)
        if byte_list == nil
            return ""
        end
        var res = ""
        for b : byte_list
            res = res + StringUtil.int_to_hex(b, 2)
        end
        return res
    end

    # Convert hex string to list of integer bytes
    static def hex_to_bytes(hex_str)
        var s = StringUtil.trim(hex_str)
        if string.startswith(s, "0x") || string.startswith(s, "0X")
            s = s[2 .. (size(s) - 1)]
        end
        var n = size(s)
        var bytes = []
        var i = 0
        while i < n - 1
            var high = StringUtil.hex_digit_value(s[i])
            var low = StringUtil.hex_digit_value(s[i + 1])
            if high >= 0 && low >= 0
                bytes.push(high * 16 + low)
            end
            i = i + 2
        end
        return bytes
    end

    # Convert string to list of ASCII byte integers
    static def string_to_bytes(s)
        if s == nil
            return []
        end
        var res = []
        var n = size(s)
        for i : 0 .. (n - 1)
            res.push(string.byte(s[i]))
        end
        return res
    end

    # Convert list of ASCII byte integers to string
    static def bytes_to_string(byte_list)
        if byte_list == nil
            return ""
        end
        var res = ""
        for b : byte_list
            res = res + string.char(b)
        end
        return res
    end

    # Sanitize an alphanumeric identifier (for OCPP StationId, EVSEId, IdToken)
    # Replaces invalid characters with an underscore
    static def sanitize_identifier(id_str)
        if id_str == nil
            return "UNKNOWN"
        end
        var s = StringUtil.trim(id_str)
        var n = size(s)
        var res = ""
        for i : 0 .. (n - 1)
            var ch = s[i]
            var b = string.byte(ch)
            # 0-9, A-Z, a-z, '-', '_'
            var is_valid = (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 45 || b == 95
            if is_valid
                res = res + ch
            else
                res = res + "_"
            end
        end
        return res
    end
end

return StringUtil
