# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# SAE J1939 / ISO 11898 CAN Bus Diagnostic Frame Parser & PGN/SPN Decoder
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt
import string_util as StringUtil

# Standard SAE J1939 Parameter Group Numbers (PGNs) for Commercial EV Charging
class J1939PGN
    static var DM1_ACTIVE_DTC         = 65226 # 0xFECA: Active Diagnostic Trouble Codes
    static var BATT_STATUS            = 65110 # 0xFE56: Battery Voltage, Current, SoC
    static var BATT_LIMITS            = 65111 # 0xFE57: Max Allowed Charge Voltage/Current
    static var BATT_THERMAL           = 65112 # 0xFE58: Cell Temperatures & Thermal State
    static var ISOLATION_MONITOR      = 65113 # 0xFE59: High Voltage Isolation Resistance
    static var CHARGER_STATUS         = 65114 # 0xFE5A: EVSE Output Telemetry
end

# CAN 29-bit Identifier Decomposition
class CANIdentifier29Bit
    var raw_id
    var priority
    var extended_data_page
    var data_page
    var pdu_format
    var pdu_specific
    var source_address
    var pgn

    def init(can_id_u32)
        var id = int(can_id_u32) & 0x1FFFFFFF
        self.raw_id = id
        self.priority = (id >> 26) & 0x07
        self.extended_data_page = (id >> 25) & 0x01
        self.data_page = (id >> 24) & 0x01
        self.pdu_format = (id >> 16) & 0xFF
        self.pdu_specific = (id >> 8) & 0xFF
        self.source_address = id & 0xFF

        # Calculate 18-bit PGN
        # If PDU Format < 240 (PDU1, destination specific), PGN = (DP << 16) | (PF << 8)
        # If PDU Format >= 240 (PDU2, broadcast), PGN = (DP << 16) | (PF << 8) | PS
        if self.pdu_format < 240
            self.pgn = (self.data_page << 16) | (self.pdu_format << 8)
        else
            self.pgn = (self.data_page << 16) | (self.pdu_format << 8) | self.pdu_specific
        end
    end

    static def build_id(prio, pgn, dest_or_group, src_addr)
        var p = (int(prio) & 0x07) << 26
        var pgn_val = int(pgn)
        var dp = (pgn_val >> 16) & 0x01
        var pf = (pgn_val >> 8) & 0xFF
        var ps = (pf < 240) ? (int(dest_or_group) & 0xFF) : (pgn_val & 0xFF)
        var sa = int(src_addr) & 0xFF

        var id = p | (dp << 24) | (pf << 16) | (ps << 8) | sa
        return CANIdentifier29Bit(id)
    end
end

# J1939 Diagnostic Trouble Code (DTC)
class DiagnosticTroubleCode
    var spn
    var fmi
    var occurrence_count
    var conversion_method

    def init(spn_val, fmi_val, count)
        self.spn = int(spn_val) # Suspect Parameter Number
        self.fmi = int(fmi_val) # Failure Mode Identifier
        self.occurrence_count = (count != nil) ? int(count) : 1
        self.conversion_method = 0
    end

    def to_map()
        return {
            "spn": self.spn,
            "fmi": self.fmi,
            "occurrence_count": self.occurrence_count
        }
    end
end

# CAN Diagnostic Frame Decoder Engine
class CANDiagnosticEngine
    var active_dtcs
    var last_battery_status
    var last_battery_limits
    var last_thermal_status
    var last_isolation_kohm
    var received_frame_count

    def init()
        self.active_dtcs = []
        self.last_battery_status = nil
        self.last_battery_limits = nil
        self.last_thermal_status = nil
        self.last_isolation_kohm = nil
        self.received_frame_count = 0
    end

    # Decode an 8-byte CAN payload according to the 29-bit CAN ID's PGN
    def process_can_frame(can_id_u32, data_bytes)
        self.received_frame_count = self.received_frame_count + 1
        var can_id = CANIdentifier29Bit(can_id_u32)
        var pgn = can_id.pgn

        if pgn == J1939PGN.BATT_STATUS
            return self._decode_battery_status(data_bytes)
        elif pgn == J1939PGN.BATT_LIMITS
            return self._decode_battery_limits(data_bytes)
        elif pgn == J1939PGN.BATT_THERMAL
            return self._decode_battery_thermal(data_bytes)
        elif pgn == J1939PGN.ISOLATION_MONITOR
            return self._decode_isolation_monitor(data_bytes)
        elif pgn == J1939PGN.DM1_ACTIVE_DTC
            return self._decode_dm1(data_bytes)
        end

        return {"pgn": pgn, "handled": false}
    end

    # Decode PGN 65110: Battery Status (Voltage, Current, SoC)
    # Byte 0-1: Pack Voltage (0.05 V/bit)
    # Byte 2-3: Pack Current (0.1 A/bit, offset -3200A)
    # Byte 4: State of Charge (0.4 %/bit, 0..100%)
    # Byte 5: State of Health (0.4 %/bit)
    def _decode_battery_status(d)
        if size(d) < 6 return nil end
        var raw_v = d[0] | (d[1] << 8)
        var voltage_v = real(raw_v) * 0.05

        var raw_i = d[2] | (d[3] << 8)
        var current_a = (real(raw_i) * 0.1) - 3200.0

        var soc_pct = real(d[4]) * 0.4
        var soh_pct = real(d[5]) * 0.4

        self.last_battery_status = {
            "pgn": J1939PGN.BATT_STATUS,
            "handled": true,
            "voltage_v": MathExt.round_to(voltage_v, 2),
            "current_a": MathExt.round_to(current_a, 2),
            "soc_pct": MathExt.round_to(soc_pct, 1),
            "soh_pct": MathExt.round_to(soh_pct, 1)
        }
        return self.last_battery_status
    end

    # Decode PGN 65111: Battery Charging Limits
    # Byte 0-1: Maximum Charge Voltage Limit (0.05 V/bit)
    # Byte 2-3: Maximum Charge Current Limit (0.1 A/bit, offset -3200A or positive offset 0..600A)
    # Byte 4-5: Maximum Charge Power Limit (100 W/bit)
    def _decode_battery_limits(d)
        if size(d) < 6 return nil end
        var raw_v = d[0] | (d[1] << 8)
        var max_v = real(raw_v) * 0.05

        var raw_i = d[2] | (d[3] << 8)
        var max_i = real(raw_i) * 0.1

        var raw_p = d[4] | (d[5] << 8)
        var max_kw = (real(raw_p) * 100.0) / 1000.0

        self.last_battery_limits = {
            "pgn": J1939PGN.BATT_LIMITS,
            "handled": true,
            "max_charge_voltage_v": MathExt.round_to(max_v, 2),
            "max_charge_current_a": MathExt.round_to(max_i, 1),
            "max_charge_power_kw": MathExt.round_to(max_kw, 1)
        }
        return self.last_battery_limits
    end

    # Decode PGN 65112: Battery Thermal State
    # Byte 0: Highest Cell Temperature (1 degC/bit, offset -40 degC)
    # Byte 1: Lowest Cell Temperature (1 degC/bit, offset -40 degC)
    # Byte 2: Average Cell Temperature (1 degC/bit, offset -40 degC)
    def _decode_battery_thermal(d)
        if size(d) < 3 return nil end
        var max_t = int(d[0]) - 40
        var min_t = int(d[1]) - 40
        var avg_t = int(d[2]) - 40

        self.last_thermal_status = {
            "pgn": J1939PGN.BATT_THERMAL,
            "handled": true,
            "max_cell_temp_c": max_t,
            "min_cell_temp_c": min_t,
            "avg_cell_temp_c": avg_t,
            "cell_temp_spread_c": (max_t - min_t)
        }
        return self.last_thermal_status
    end

    # Decode PGN 65113: High Voltage Isolation Monitor
    # Byte 0-1: DC Isolation Resistance (1 kOhm/bit, 0..65535 kOhm)
    # Byte 2: Isolation Warning Flag (0 = OK, 1 = Warning < 500 Ohm/V, 2 = Critical Fault < 100 Ohm/V)
    def _decode_isolation_monitor(d)
        if size(d) < 3 return nil end
        var r_kohm = d[0] | (d[1] << 8)
        var status_flag = d[2]

        self.last_isolation_kohm = r_kohm
        var is_fault = (r_kohm < 100 || status_flag == 2)
        var is_warning = (r_kohm < 500 || status_flag == 1)

        return {
            "pgn": J1939PGN.ISOLATION_MONITOR,
            "handled": true,
            "isolation_kohm": r_kohm,
            "status_flag": status_flag,
            "is_warning": is_warning,
            "is_isolation_fault": is_fault
        }
    end

    # Decode PGN 65226: Diagnostic Trouble Codes (DM1)
    # Byte 0-1: Lamp status
    # Byte 2-5: First DTC:
    #   SPN: (Byte 4 & 0xE0) << 11 | (Byte 3 << 8) | Byte 2
    #   FMI: Byte 4 & 0x1F
    #   Occurrence Count: Byte 5 & 0x7F
    def _decode_dm1(d)
        if size(d) < 6 return nil end
        var raw_spn = d[2] | (d[3] << 8) | ((d[4] & 0xE0) << 11)
        var fmi = d[4] & 0x1F
        var oc = d[5] & 0x7F

        var dtc = DiagnosticTroubleCode(raw_spn, fmi, oc)
        self.active_dtcs.push(dtc)

        return {
            "pgn": J1939PGN.DM1_ACTIVE_DTC,
            "handled": true,
            "dtc": dtc.to_map()
        }
    end
end

return {
    "J1939PGN": J1939PGN,
    "CANIdentifier29Bit": CANIdentifier29Bit,
    "DiagnosticTroubleCode": DiagnosticTroubleCode,
    "CANDiagnosticEngine": CANDiagnosticEngine
}
