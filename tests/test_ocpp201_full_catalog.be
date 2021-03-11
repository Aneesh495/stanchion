# Stanchion Test Suite: OCPP 2.0.1 Full Action Catalog & PDU Validation
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import ocpp201_full_catalog as CatalogModule
import math
import string
import global

var FunctionalBlock = CatalogModule["FunctionalBlock"]
var InitiatorRole = CatalogModule["InitiatorRole"]
var OCPP201ActionCatalog = CatalogModule["OCPP201ActionCatalog"]

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

print(">>> Running test_ocpp201_full_catalog suite...")

var cat = OCPP201ActionCatalog()
var all_actions = cat.list_actions()
assert_true(size(all_actions) >= 25, "Catalog contains at least 25 standard actions")

# 1. Action Query & Metadata Tests
var boot_act = cat.get_action("BootNotification")
assert_true(boot_act != nil, "Retrieved BootNotification action")
assert_equal(boot_act.functional_block, FunctionalBlock.PROVISIONING, "BootNotification block is Provisioning")
assert_equal(boot_act.initiator, InitiatorRole.CHARGING_STATION, "Initiator is ChargingStation")

var tx_act = cat.get_action("TransactionEvent")
assert_equal(tx_act.functional_block, FunctionalBlock.TRANSACTIONS, "TransactionEvent block is Transactions")

# 2. Functional Block Filtering
var sc_actions = cat.list_by_block(FunctionalBlock.SMART_CHARGING)
assert_true(size(sc_actions) >= 4, "SmartCharging block has at least 4 actions")

var sec_actions = cat.list_by_block(FunctionalBlock.SECURITY)
assert_true(size(sec_actions) >= 4, "Security block has at least 4 actions")

# 3. PDU Request Validation (Valid Cases)
var valid_boot_req = {
    "reason": "PowerUp",
    "chargingStation": {"model": "Stanchion-3P", "vendorName": "Stanchion"}
}
var v1 = cat.validate_pdu("BootNotification", true, valid_boot_req)
assert_true(v1["valid"], "Valid BootNotification request accepted")
assert_equal(size(v1["missing_fields"]), 0, "No missing fields")

var valid_auth_req = {
    "idToken": {"idToken": "RFID-VIP-001", "type": "ISO14443"}
}
var v2 = cat.validate_pdu("Authorize", true, valid_auth_req)
assert_true(v2["valid"], "Valid Authorize request accepted")

# 4. PDU Request Validation (Invalid Cases)
# Missing 'chargingStation'
var bad_boot_req = {"reason": "PowerUp"}
var v3 = cat.validate_pdu("BootNotification", true, bad_boot_req)
assert_true(!v3["valid"], "Rejected incomplete BootNotification request")
assert_equal(v3["reason"], "MissingRequiredFields", "Reason is MissingRequiredFields")
assert_equal(v3["missing_fields"][0], "chargingStation", "Identified missing chargingStation field")

# Missing 'type' in Reset request
var bad_reset_req = {"evseId": 1}
var v4 = cat.validate_pdu("Reset", true, bad_reset_req)
assert_true(!v4["valid"], "Rejected Reset request missing type")
assert_equal(v4["missing_fields"][0], "type", "Identified missing type")

# 5. Response PDU Validation
var valid_boot_res = {
    "currentTime": "2026-05-01T12:00:00Z",
    "interval": 60,
    "status": "Accepted"
}
var v5 = cat.validate_pdu("BootNotification", false, valid_boot_res)
assert_true(v5["valid"], "Valid BootNotification response accepted")

# Missing 'status' in response
var bad_boot_res = {"currentTime": "2026-05-01T12:00:00Z", "interval": 60}
var v6 = cat.validate_pdu("BootNotification", false, bad_boot_res)
assert_true(!v6["valid"], "Rejected BootNotification response missing status")

# 6. Unknown Action Check
var v_unk = cat.validate_pdu("TeleportVehicle", true, {})
assert_true(!v_unk["valid"], "Rejected unknown action")
assert_equal(v_unk["reason"], "UnknownAction", "Reason is UnknownAction")

print("test_ocpp201_full_catalog: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
