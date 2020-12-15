# Stanchion Test Suite: SAE J1939 CAN Bus Diagnostics & PGN/SPN Decoder
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import can_diagnostics as CANModule
import math
import string
import global

var J1939PGN = CANModule["J1939PGN"]
var CANIdentifier29Bit = CANModule["CANIdentifier29Bit"]
var DiagnosticTroubleCode = CANModule["DiagnosticTroubleCode"]
var CANDiagnosticEngine = CANModule["CANDiagnosticEngine"]

var test_passed = 0
var test_failed = 0

def assert_true(cond, msg)
    if cond
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg))
    end
end

def assert_equal(a, b, msg)
    if a == b
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg) + " (expected " + str(b) + ", got " + str(a) + ")")
    end
end

print(">>> Running test_can_diagnostics suite...")

# 1. 29-Bit CAN Identifier Decomposition Tests
# Priority 6, PGN 65110 (0xFE56: DP=0, PF=254, PS=86), SA=0xF4 (EVSE)
# CAN ID = (6 << 26) | (0 << 24) | (254 << 16) | (86 << 8) | 244 = 0x18FE56F4
var can_id = CANIdentifier29Bit(0x18FE56F4)
assert_equal(can_id.priority, 6, "Priority == 6")
assert_equal(can_id.pdu_format, 254, "PDU Format == 254")
assert_equal(can_id.pdu_specific, 86, "PDU Specific == 86")
assert_equal(can_id.source_address, 244, "Source Address == 244")
assert_equal(can_id.pgn, 65110, "Calculated PGN == 65110 (BATT_STATUS)")

# Build CAN ID test
var built_id = CANIdentifier29Bit.build_id(6, 65110, 86, 244)
assert_equal(built_id.raw_id, 0x18FE56F4, "build_id reconstructed 0x18FE56F4")

# 2. CAN Diagnostic Engine & Battery Status Decoding
var engine = CANDiagnosticEngine()

# PGN 65110: 400.0V (raw = 8000 = 0x1F40), 100.0A (raw = (100 + 3200)/0.1 = 33000 = 0x80E8), SoC 80% (raw = 200 = 0xC8), SoH 98% (raw = 245 = 0xF5)
var batt_status_payload = [0x40, 0x1F, 0xE8, 0x80, 0xC8, 0xF5, 0xFF, 0xFF]
var status_res = engine.process_can_frame(0x18FE56F4, batt_status_payload)

assert_true(status_res["handled"], "Handled BATT_STATUS frame")
assert_equal(status_res["voltage_v"], 400.0, "Decoded 400.0 V pack voltage")
assert_equal(status_res["current_a"], 100.0, "Decoded 100.0 A charge current")
assert_equal(status_res["soc_pct"], 80.0, "Decoded 80.0% SoC")
assert_equal(status_res["soh_pct"], 98.0, "Decoded 98.0% SoH")

# 3. Battery Charging Limits Decoding (PGN 65111)
# Max V = 450.0V (raw = 9000 = 0x2328), Max I = 250.0A (raw = 2500 = 0x09C4), Max P = 100 kW (raw = 1000 = 0x03E8)
var batt_limits_payload = [0x28, 0x23, 0xC4, 0x09, 0xE8, 0x03, 0xFF, 0xFF]
var limits_res = engine.process_can_frame(0x18FE57F4, batt_limits_payload)

assert_true(limits_res["handled"], "Handled BATT_LIMITS frame")
assert_equal(limits_res["max_charge_voltage_v"], 450.0, "Max voltage 450V")
assert_equal(limits_res["max_charge_current_a"], 250.0, "Max current 250A")
assert_equal(limits_res["max_charge_power_kw"], 100.0, "Max power 100 kW")

# 4. Battery Thermal Status Decoding (PGN 65112)
# Max Cell Temp = 35 C (raw = 35 + 40 = 75), Min Cell Temp = 28 C (raw = 28 + 40 = 68), Avg = 31 C (raw = 31 + 40 = 71)
var batt_thermal_payload = [75, 68, 71, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
var thermal_res = engine.process_can_frame(0x18FE58F4, batt_thermal_payload)

assert_true(thermal_res["handled"], "Handled BATT_THERMAL frame")
assert_equal(thermal_res["max_cell_temp_c"], 35, "Max cell temp 35 C")
assert_equal(thermal_res["min_cell_temp_c"], 28, "Min cell temp 28 C")
assert_equal(thermal_res["avg_cell_temp_c"], 31, "Avg cell temp 31 C")
assert_equal(thermal_res["cell_temp_spread_c"], 7, "Cell temp delta is 7 C")

# 5. High Voltage Isolation Monitor Decoding (PGN 65113)
# Isolation resistance = 50 kOhm (critical fault < 100 kOhm, raw = 50 = 0x0032), Flag = 2
var iso_fault_payload = [0x32, 0x00, 2, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
var iso_res = engine.process_can_frame(0x18FE59F4, iso_fault_payload)

assert_true(iso_res["handled"], "Handled ISOLATION_MONITOR frame")
assert_equal(iso_res["isolation_kohm"], 50, "Isolation is 50 kOhm")
assert_true(iso_res["is_isolation_fault"], "Detected critical isolation fault")

# 6. Active Diagnostic Trouble Codes DM1 (PGN 65226)
# SPN = 520208 (0x07F010: High Voltage Isolation Fault), FMI = 1 (Below Valid Range), Count = 3
# Byte 2: SPN LSB = 0x10
# Byte 3: SPN Mid = 0xF0
# Byte 4: (SPN MSB << 5) | FMI = (0x03 << 5) | 1 = 0x61
# Byte 5: Occurrence Count = 3
var dm1_payload = [0x00, 0x00, 0x10, 0xF0, 0x61, 0x03, 0xFF, 0xFF]
var dm1_res = engine.process_can_frame(0x18FECAF4, dm1_payload)

assert_true(dm1_res["handled"], "Handled DM1 active DTC frame")
var dtc = dm1_res["dtc"]
assert_equal(dtc["fmi"], 1, "DTC FMI == 1")
assert_equal(dtc["occurrence_count"], 3, "DTC occurrence count == 3")
assert_true(size(engine.active_dtcs) == 1, "Recorded active DTC")

# 7. Unhandled PGN
var unknown_res = engine.process_can_frame(0x18FFAAF4, [0, 0, 0, 0, 0, 0, 0, 0])
assert_true(!unknown_res["handled"], "Unknown PGN reports handled: false")

print("test_can_diagnostics: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
