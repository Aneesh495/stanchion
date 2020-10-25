# Stanchion Test Suite: OCPP 2.0.1 Protocol Subsystem
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import frame as OCPPFrame
import messages as OCPPMessages
import handlers as OCPPHandlers
import transaction as Transaction
import auth as AuthManager
import variables as DeviceModel
import security as SecurityManager
import charging_profile as ChargingProfileModule
import types as Types
import math
import string
import global

var Profile = ChargingProfileModule["Profile"]
var CompositeCalc = ChargingProfileModule["CompositeCalculator"]

var total_assertions = 0

def check(condition, desc)
    global.total_assertions = global.total_assertions + 1
    if !condition
        print("[FAIL] " + desc)
        assert(false)
    end
end

print(">>> Running test_ocpp.be ...")

# 1. OCPPFrame Serialization & Parsing
var call_frame = OCPPFrame.create_call("Heartbeat", {})
var json_str = call_frame.serialize()
check(string.startswith(json_str, "[2,"), "CALL frame serialized with MessageTypeId 2")
var parsed_frame = OCPPFrame.parse(json_str)
check(parsed_frame != nil, "Parsed frame successfully")
check(parsed_frame.message_type_id == 2, "Parsed messageTypeId == 2")
check(parsed_frame.action == "Heartbeat", "Parsed action == Heartbeat")

var res_frame = OCPPFrame.create_call_result(call_frame.message_id, {"currentTime": "2026-05-01T12:00:00Z"})
var res_json = res_frame.serialize()
check(string.startswith(res_json, "[3,"), "CALLRESULT serialized with MessageTypeId 3")

var err_frame = OCPPFrame.create_call_error(call_frame.message_id, "NotImplemented", "Feature disabled", {})
var err_json = err_frame.serialize()
check(string.startswith(err_json, "[4,"), "CALLERROR serialized with MessageTypeId 4")

# 2. OCPPMessages Builders
var boot_req = OCPPMessages.boot_notification_req("Stanchion", "Model-X", "SN123", "1.0.0", "PowerUp")
check(boot_req["chargingStation"]["vendorName"] == "Stanchion", "BootNotification vendorName correct")
check(boot_req["reason"] == "PowerUp", "BootNotification reason correct")

var auth_req = OCPPMessages.authorize_req("TAG-ABC-123", "ISO14443")
check(auth_req["idToken"]["idToken"] == "TAG-ABC-123", "Authorize idToken correct")

# 3. Transaction State Manager
var tx = Transaction(1, 1, "RFID-007", 100.5, 1000)
check(tx.is_active == true, "Transaction starts active")
check(tx.seq_no == 0, "Sequence number starts at 0")
check(tx.next_seq_no() == 0, "next_seq_no returns current and increments")
check(tx.seq_no == 1, "Sequence number incremented to 1")

tx.update_energy(112.5) # Consumed 12.0 kWh
check(math.abs(tx.get_energy_consumed_kwh() - 12.0) < 0.001, "Energy consumed = 12.0 kWh")
tx.stop(2800, 112.5, "Local")
check(tx.is_active == false, "Transaction marked stopped")
check(tx.stopped_reason == "Local", "Stopped reason is Local")
check(tx.get_duration_sec(3000) == 1800, "Transaction duration = 1800 sec")

# 4. AuthManager & Whitelist
var auth_mgr = AuthManager(3600)
auth_mgr.add_whitelist_entry("BADGE-VIP-01", nil, Types.AUTH_ACCEPTED, 0, "FleetVIP", 50.0)
auth_mgr.add_whitelist_entry("BADGE-EXPIRED", nil, Types.AUTH_ACCEPTED, 1000, "Standard", nil)

var res_vip = auth_mgr.verify_token_locally("BADGE-VIP-01", 2000)
check(res_vip["status"] == Types.AUTH_ACCEPTED, "VIP badge accepted")
check(res_vip["group"] == "FleetVIP", "VIP user group identified")
check(res_vip["max_power_kw"] == 50.0, "VIP max power override returned")

var res_exp = auth_mgr.verify_token_locally("BADGE-EXPIRED", 2000) # Expired at t=1000
check(res_exp["status"] == Types.AUTH_EXPIRED, "Expired badge flagged")

# Cache test
auth_mgr.cache_authorization("BADGE-CACHED", Types.AUTH_ACCEPTED, 1000)
var res_cached = auth_mgr.verify_token_locally("BADGE-CACHED", 1500)
check(res_cached["status"] == Types.AUTH_ACCEPTED, "Cached token accepted within TTL")

# 5. DeviceModel Variables
var dev_model = DeviceModel()
check(dev_model.get_variable("Controller", "HeartbeatInterval") == 60, "Default HeartbeatInterval == 60")
var set_res = dev_model.set_variable("Controller", "HeartbeatInterval", 120)
check(set_res["status"] == "Accepted", "SetVariable accepted for ReadWrite variable")
check(dev_model.get_variable("Controller", "HeartbeatInterval") == 120, "Updated to 120")

var ro_res = dev_model.set_variable("ChargingStation", "VendorName", "HackedVendor")
check(ro_res["status"] == "Rejected", "ReadOnly variable cannot be mutated")

# 6. SecurityManager & Rate Limiting
var sec_mgr = SecurityManager(2)
sec_mgr.log_security_event("TamperAlert", "Cabinet door sensor opened", 1000)
check(sec_mgr.get_audit_trail().size() == 1, "Security event recorded in audit trail")

# Brute force attempt
for i : 1 .. 4
    sec_mgr.record_failed_auth("BADGE-INVALID", 1000 + i)
end
check(!sec_mgr.is_rate_limited(1005), "4 failures under limit not yet locked out")
sec_mgr.record_failed_auth("BADGE-INVALID", 1006) # 5th attempt
check(sec_mgr.is_rate_limited(1007), "5th failure within window triggers lockout")

# 7. Smart Charging Profile & Composite Schedule
var prof_max = Profile(1, 0, Types.PROFILE_PURPOSE_CHARGE_POINT_MAX, Types.PROFILE_KIND_ABSOLUTE, Types.RATE_UNIT_AMPERES)
prof_max.add_period(0, 32.0, 3)     # 0-3600 sec: 32A limit
prof_max.add_period(3600, 16.0, 3)  # 3600-7200 sec: 16A limit

var prof_tx = Profile(2, 1, Types.PROFILE_PURPOSE_TX_PROFILE, Types.PROFILE_KIND_ABSOLUTE, Types.RATE_UNIT_AMPERES)
prof_tx.add_period(0, 24.0, 3)      # 24A limit

var profiles = [prof_max, prof_tx]
# At offset 1000: min(32A, 24A) = 24A
var comp_1000 = CompositeCalc.calculate_composite_limit(profiles, 1000, 32.0)
check(math.abs(comp_1000 - 24.0) < 0.01, "Composite at t=1000 is 24A")

# At offset 4000: min(16A, 24A) = 16A
var comp_4000 = CompositeCalc.calculate_composite_limit(profiles, 4000, 32.0)
check(math.abs(comp_4000 - 16.0) < 0.01, "Composite at t=4000 is 16A")

# 8. OCPP Inbound Handlers
var handlers = OCPPHandlers(nil, nil)
var req_reset = OCPPFrame.create_call("Reset", {"type": "Soft"})
var resp_reset = handlers.dispatch(req_reset)
check(resp_reset.message_type_id == 3, "Reset returns CALLRESULT")
check(resp_reset.payload["status"] == "Accepted", "Reset accepted")

var req_unknown = OCPPFrame.create_call("NonExistentAction", {})
var resp_unknown = handlers.dispatch(req_unknown)
check(resp_unknown.message_type_id == 4, "Unknown action returns CALLERROR")
check(resp_unknown.error_code == "NotImplemented", "Error code is NotImplemented")

print(string.format("[PASS] test_ocpp.be passed with %d assertions verified.", total_assertions))
