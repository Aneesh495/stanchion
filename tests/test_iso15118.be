# Stanchion Test Suite: ISO 15118-2 / ISO 15118-20 V2G Protocol Engine
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import iso15118 as ISO15118Module
import math
import string
import global

var V2GTP = ISO15118Module["V2GTP"]
var V2GResponseCode = ISO15118Module["V2GResponseCode"]
var EnergyTransferMode = ISO15118Module["EnergyTransferMode"]
var PhysicalValue = ISO15118Module["PhysicalValue"]
var ISO15118Session = ISO15118Module["ISO15118Session"]

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

print(">>> Running test_iso15118 suite...")

# 1. V2GTP Header Packing & Parsing
var header_bytes = ISO15118Session.pack_v2gtp_header(V2GTP.PAYLOAD_TYPE_EXI, 256)
assert_equal(size(header_bytes), 8, "Header is exactly 8 bytes")
assert_equal(header_bytes[0], 0x01, "Sync byte 0 is 0x01")
assert_equal(header_bytes[1], 0xFE, "Sync byte 1 is 0xFE")
assert_equal(header_bytes[2], 0x80, "Payload type high byte is 0x80")
assert_equal(header_bytes[3], 0x01, "Payload type low byte is 0x01")
assert_equal(header_bytes[7], 0x00, "Length low byte")
assert_equal(header_bytes[6], 0x01, "Length byte 6 is 1 (256 length)")

var parsed_header = ISO15118Session.parse_v2gtp_header(header_bytes)
assert_true(parsed_header["ok"], "Parsed valid V2GTP header")
assert_equal(parsed_header["payload_type"], 0x8001, "Parsed payload type is 0x8001")
assert_equal(parsed_header["payload_length"], 256, "Parsed payload length is 256")

# Short header error check
var short_header = [0x01, 0xFE, 0x80]
var bad_res = ISO15118Session.parse_v2gtp_header(short_header)
assert_true(!bad_res["ok"], "Rejected short header")

# Corrupt sync bytes check
var corrupt_header = [0x02, 0xAA, 0x80, 0x01, 0x00, 0x00, 0x01, 0x00]
var corrupt_res = ISO15118Session.parse_v2gtp_header(corrupt_header)
assert_true(!corrupt_res["ok"], "Rejected corrupt sync bytes")

# 2. Physical Value Scaler Tests
var pv1 = PhysicalValue(320, -1, "A")
assert_equal(pv1.get_actual_value(), 32.0, "320 * 10^-1 == 32.0 A")

var pv2 = PhysicalValue.from_actual(400.0, "V")
assert_true(math.abs(pv2.get_actual_value() - 400.0) < 0.1, "from_actual reconstructed 400V")

# 3. ISO 15118 Handshake Sequence Tests
var session = ISO15118Session("US-STN-EVSE-01")

# Step A: SupportedAppProtocol negotiation
var protocols = [
    {"protocolNamespace": "urn:unknown:schema", "priority": 1},
    {"protocolNamespace": "urn:iso:15118:2:2013:MsgDef", "priority": 2}
]
var sap_res = session.handle_supported_app_protocol_req(protocols)
assert_equal(sap_res["response_code"], "OK_SuccessfulNegotiation", "Negotiated supported app protocol")
assert_equal(sap_res["negotiated_namespace"], "urn:iso:15118:2:2013:MsgDef", "Matched ISO 15118-2 namespace")

# Step B: SessionSetupReq
var setup_res = session.handle_session_setup_req(nil, "02:00:00:00:00:01")
assert_equal(setup_res["response_code"], V2GResponseCode.OK_NEW_SESSION_ESTABLISHED, "Established new session")
assert_true(setup_res["session_id"] != nil, "Generated valid session ID")

# Step C: Sequence Error Check (Attempting ChargeParameterDiscovery before ServiceDiscovery)
var out_of_order = session.handle_charge_parameter_discovery_req({"max_current_a": 32.0})
assert_equal(out_of_order["response_code"], V2GResponseCode.FAILED_SEQUENCE_ERROR, "Detected sequence error")

# Step D: ServiceDiscoveryReq
var disco_res = session.handle_service_discovery_req()
assert_equal(disco_res["response_code"], V2GResponseCode.OK, "Service discovery OK")
assert_equal(size(disco_res["payment_options"]), 2, "Returned 2 payment options")

# Step E: ServicePaymentSelectionReq
var pay_res = session.handle_payment_selection_req("Contract", 1)
assert_equal(pay_res["response_code"], V2GResponseCode.OK, "Payment selection OK")

# Step F: ChargeParameterDiscoveryReq with V2G BPT
var param_req = {
    "max_voltage_v": 400.0,
    "max_current_a": 32.0,
    "max_power_w": 22000.0,
    "bpt_supported": true
}
var param_res = session.handle_charge_parameter_discovery_req(param_req)
assert_equal(param_res["response_code"], V2GResponseCode.OK, "Charge parameters agreed")
assert_equal(param_res["evse_max_current_a"], 32.0, "Agreed 32A charging limit")
assert_true(param_res["bpt_active"], "Bidirectional Power Transfer activated")

# Step G: PowerDeliveryReq Start & Stop
var pwr_start = session.handle_power_delivery_req("Start")
assert_equal(pwr_start["response_code"], V2GResponseCode.OK, "Power delivery started")
assert_equal(session.current_state, "STATE_CHARGING_ACTIVE", "Session is in active charging state")

var pwr_stop = session.handle_power_delivery_req("Stop")
assert_equal(pwr_stop["response_code"], V2GResponseCode.OK, "Power delivery stopped")
assert_equal(session.current_state, "STATE_POWER_STOPPED", "Session is in stopped power state")

# Step H: SessionStopReq
var stop_res = session.handle_session_stop_req(true)
assert_equal(stop_res["response_code"], V2GResponseCode.OK, "Session stopped cleanly")
assert_equal(session.current_state, "STATE_SESSION_TERMINATED", "Session state is terminated")

print("test_iso15118: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
