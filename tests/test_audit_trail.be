# Stanchion Test Suite: Tamper-Evident Chained Audit Trail
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import audit_trail as AuditModule
import math
import string
import global

var AuditCategory = AuditModule["AuditCategory"]
var AuditRecord = AuditModule["AuditRecord"]
var AuditTrailLedger = AuditModule["AuditTrailLedger"]

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

print(">>> Running test_audit_trail suite...")

var ledger = AuditTrailLedger(500)

# 1. Genesis Block Check
assert_equal(size(ledger.records), 1, "Ledger initialised with Genesis block")
assert_equal(ledger.records[0].sequence_number, 0, "Genesis sequence is 0")

# 2. Append Events
var rec1 = ledger.append_event(AuditCategory.CONFIGURATION, "CSMS-ADMIN", "SET_GRID_LIMIT", "Changed limit to 80A", 1770000010)
assert_equal(rec1.sequence_number, 1, "First appended event has seq 1")
assert_equal(rec1.previous_hash, ledger.records[0].block_hash, "Previous hash links to genesis")

var rec2 = ledger.append_event(AuditCategory.SECURITY, "CSMS-ADMIN", "INSTALL_ROOT_CERT", "Installed GlobalRootCA", 1770000020)
assert_equal(rec2.sequence_number, 2, "Second appended event has seq 2")
assert_equal(rec2.previous_hash, rec1.block_hash, "Chained to rec1 hash")

var rec3 = ledger.append_event(AuditCategory.TRANSACTION, "RFID-USER-99", "START_TRANSACTION", "EVSE 1 session started", 1770000030)
assert_equal(rec3.sequence_number, 3, "Third event has seq 3")

# 3. Complete Integrity Verification
var v_res = ledger.verify_integrity()
assert_true(v_res["valid"], "Full cryptographic chain verified valid")
assert_equal(v_res["total_blocks_verified"], 4, "Verified 4 blocks (Genesis + 3 events)")

# 4. Tamper Detection Check (Simulate malicious modification of block 2)
ledger.records[2].details = "Malicious unauthorized tampering!"
var tamper_res = ledger.verify_integrity()
assert_true(!tamper_res["valid"], "Detected cryptographic tamper mismatch")
assert_equal(tamper_res["tampered_index"], 2, "Accurately identified tampered block index 2")
assert_equal(tamper_res["tampered_sequence"], 2, "Accurately identified tampered sequence 2")

# Restore block 2 to original details and recompute hash to restore ledger state
ledger.records[2].details = "Installed GlobalRootCA"
ledger.records[2].block_hash = ledger.records[2]._compute_hash()
# Also recompute block 3 hash since previous hash changed
ledger.records[3].previous_hash = ledger.records[2].block_hash
ledger.records[3].block_hash = ledger.records[3]._compute_hash()
var restored_res = ledger.verify_integrity()
assert_true(restored_res["valid"], "Chain valid again after restoration")

# 5. Physical Tamper Switch Trip
ledger.trigger_tamper_switch(1770000050)
assert_true(ledger.is_tamper_detected, "Physical tamper state set")
var slice = ledger.get_records_slice(1, 10)
assert_true(size(slice) >= 4, "Exported audit slice contains logged events")

print("test_audit_trail: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
