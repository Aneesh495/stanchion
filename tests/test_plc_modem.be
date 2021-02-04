# Stanchion Test Suite: HomePlug Green PHY PLC Modem & SLAC Protocol
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import plc_modem as PLCModemModule
import math
import string
import global

var SLACState = PLCModemModule["SLACState"]
var HomePlugGreenPHYModem = PLCModemModule["HomePlugGreenPHYModem"]

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

print(">>> Running test_plc_modem suite...")

var modem = HomePlugGreenPHYModem("00:01:87:AA:BB:CC")

# 1. Parameter Exchange
assert_equal(modem.current_state, SLACState.IDLE, "Modem starts in IDLE")
var parm_res = modem.handle_slac_parm_req("02:00:00:11:22:33", "A1B2C3D4E5F6")
assert_equal(parm_res["mme_type"], "CM_SLAC_PARM.CNF", "Responded with CM_SLAC_PARM.CNF")
assert_equal(parm_res["num_sounds"], 10, "Specified 10 sounding bursts")
assert_equal(modem.current_state, SLACState.PARAM_EXCHANGE, "State is PARAM_EXCHANGE")

# 2. Sounding Packet Bursts (Strong Physical Coupling ~25 dB)
for i : 1 .. 10
    modem.record_sounding_packet(i, 24.5 + (real(i) * 0.1))
end
assert_equal(modem.current_state, SLACState.SOUNDING_ACTIVE, "State is SOUNDING_ACTIVE")

# 3. Attenuation Evaluation (Valid Match)
var atten_res = modem.evaluate_attenuation()
assert_true(atten_res["matched"], "Physical cable coupling matched")
assert_true(modem.average_attenuation_db < 30.0, "Average attenuation is low (< 30 dB)")
assert_equal(modem.current_state, SLACState.ATTENUATION_VERIFIED, "State is ATTENUATION_VERIFIED")

# 4. SLAC Match Request & Key Agreement
var match_res = modem.handle_slac_match_req("02:00:00:11:22:33", "A1B2C3D4E5F6")
assert_equal(match_res["status"], "Success_Matched", "SLAC matched successfully")
assert_true(match_res["nmk"] != nil, "NMK encryption key generated")
assert_equal(modem.current_state, SLACState.MATCHED, "Modem is in MATCHED state")

# 5. Cross-Talk Rejection Test (Adjacent Bay Cross-Bleed with 52 dB Attenuation)
var cross_modem = HomePlugGreenPHYModem("00:01:87:AA:BB:CC")
cross_modem.handle_slac_parm_req("02:00:00:99:88:77", "F1E2D3C4B5A6")
for i : 1 .. 10
    cross_modem.record_sounding_packet(i, 52.0 + (real(i) * 0.2)) # Attenuation > 42 dB
end
var cross_res = cross_modem.evaluate_attenuation()
assert_true(!cross_res["matched"], "Cross-talk signal rejected")
assert_equal(cross_res["reason"], "CrossTalkDetectedSignalTooWeak", "Identified CrossTalkDetectedSignalTooWeak")
assert_equal(cross_modem.current_state, SLACState.UNMATCHED, "State is UNMATCHED")

# 6. Mismatched Run ID Check
var bad_match = modem.handle_slac_match_req("02:00:00:11:22:33", "WRONG_RUN_ID")
assert_equal(bad_match["status"], "Failure_UnverifiedAttenuation", "Rejected out of state / mismatched request")

print("test_plc_modem: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
