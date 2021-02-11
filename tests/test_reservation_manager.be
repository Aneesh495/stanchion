# Stanchion Test Suite: EVSE Bay Reservation & Collision Detection
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import reservation_manager as ResModule
import math
import string
import global

var ReserveNowStatus = ResModule["ReserveNowStatus"]
var ReservationEntry = ResModule["ReservationEntry"]
var ReservationManager = ResModule["ReservationManager"]

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

print(">>> Running test_reservation_manager suite...")

var mgr = ReservationManager(4) # 4 EVSEs

# 1. Valid Reservation on EVSE 1
var res1 = mgr.reserve_now(101, 1, "RFID-USER-A", "GROUP-DEPOT", 1000, 2000, false)
assert_equal(res1["status"], ReserveNowStatus.ACCEPTED, "Reservation 101 accepted on EVSE 1")
assert_equal(size(mgr.active_reservations), 1, "Recorded 1 active reservation")

# 2. Collision Detection (Overlapping interval [1500, 2500] on same EVSE 1)
var res_coll = mgr.reserve_now(102, 1, "RFID-USER-B", nil, 1500, 2500, false)
assert_equal(res_coll["status"], ReserveNowStatus.OCCUPIED, "Collision detected, rejected with Occupied")
assert_equal(size(mgr.active_reservations), 1, "Active reservation count remains 1")

# 3. Non-Overlapping Reservation on EVSE 2
var res_evse2 = mgr.reserve_now(103, 2, "RFID-USER-C", nil, 1000, 2000, false)
assert_equal(res_evse2["status"], ReserveNowStatus.ACCEPTED, "Accepted reservation on EVSE 2")

# 4. Driver Authorization Check for Bay
# Correct driver swipes at t=1200
var auth_ok = mgr.check_authorization_for_bay(1, "RFID-USER-A", nil, 1200)
assert_true(auth_ok["authorized"], "Matching reserved driver authorized")

# Wrong driver swipes at t=1200 on reserved EVSE 1
var auth_bad = mgr.check_authorization_for_bay(1, "RFID-INTRUDER-99", nil, 1200)
assert_true(!auth_bad["authorized"], "Unauthorized driver rejected on reserved bay")
assert_equal(auth_bad["reason"], "ReservedForDifferentDriver", "Reported ReservedForDifferentDriver")

# Free bay (EVSE 3) allows anyone
var auth_free = mgr.check_authorization_for_bay(3, "RFID-ANY-DRIVER", nil, 1200)
assert_true(auth_free["authorized"], "Unreserved bay allows any driver")

# 5. Priority Preemption Test
# Emergency vehicle arrives with emergency flag = true on EVSE 1
var res_emerg = mgr.reserve_now(999, 1, "RFID-POLICE-EMERGENCY", "EMERGENCY_SERVICES", 1100, 1800, true)
assert_equal(res_emerg["status"], ReserveNowStatus.ACCEPTED, "Emergency reservation preempts standard booking")

# 6. Expiration Purging
# Advance time to t=3000 (both EVSE 1 and EVSE 2 reservations expired)
var purged_count = mgr.purge_expired(3000)
assert_true(purged_count >= 1, "Purged expired reservations")
assert_equal(size(mgr.active_reservations), 0, "No active reservations remaining after expiry")

print("test_reservation_manager: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
