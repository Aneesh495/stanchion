# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Cyclic Redundancy Check (CRC-16 Modbus & CRC-32) Telemetry Checksum Engine
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import string_util as StringUtil

class CRC
    # Compute 16-bit CRC with Modbus polynomial 0xA001 (reversed 0x8005)
    # Initial value 0xFFFF
    static def crc16_modbus(bytes_list)
        if bytes_list == nil
            return 0
        end
        var crc = 0xFFFF
        for b : bytes_list
            crc = crc ^ int(b)
            for j : 0 .. 7
                if (crc & 1) != 0
                    crc = (crc >> 1) ^ 0xA001
                else
                    crc = crc >> 1
                end
            end
        end
        return crc & 0xFFFF
    end

    # Compute CRC-16 of a string
    static def crc16_string(s)
        var b = StringUtil.string_to_bytes(s)
        return CRC.crc16_modbus(b)
    end

    # Compute 32-bit CRC with IEEE 802.3 polynomial 0xEDB88320
    # Initial value 0xFFFFFFFF, final XOR 0xFFFFFFFF
    static def crc32(bytes_list)
        if bytes_list == nil
            return 0
        end
        var crc = 0xFFFFFFFF
        for b : bytes_list
            crc = crc ^ int(b)
            for j : 0 .. 7
                if (crc & 1) != 0
                    crc = (crc >> 1) ^ 0xEDB88320
                else
                    crc = crc >> 1
                end
            end
        end
        return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF
    end

    # Compute CRC-32 of a string
    static def crc32_string(s)
        var b = StringUtil.string_to_bytes(s)
        return CRC.crc32(b)
    end

    # Return formatted hex string of CRC-16
    static def crc16_hex(bytes_list)
        var val = CRC.crc16_modbus(bytes_list)
        return StringUtil.int_to_hex(val, 4)
    end

    # Return formatted hex string of CRC-32
    static def crc32_hex(bytes_list)
        var val = CRC.crc32(bytes_list)
        return StringUtil.int_to_hex(val, 8)
    end
end

return CRC
