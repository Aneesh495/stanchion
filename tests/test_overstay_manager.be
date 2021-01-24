# Stanchion Test Suite: Connector Overstay & Idle Fee Policy
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import overstay_manager as OverstayModule
import math
import string
import global

var OverstaySession = OverstayModule["OverstaySession"]
var OverstayManager = OverstayModule["OverstayManager"]

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

print(">>> Running test_overstay_manager suite...")

var mgr = OverstayManager()
var t0 = 1770000000
mgr.register_charge_complete(1, "TX-1001", "RFID-USER-01", t0)

# 1. Grace Period Test (10 minutes after stop = 600s)
var res_grace = mgr.calculate_idle_fee(1, t0 + 600, 0.5)
assert_equal(res_grace["fee"], 0.0, "Fee is $0.00 inside grace period")
assert_equal(res_grace["status"], "GRACE_PERIOD", "Status is GRACE_PERIOD")
assert_equal(res_grace["remaining_grace_min"], 5.0, "5.0 minutes grace remaining")
assert_true(!res_grace["auto_unlock_triggered"], "No auto-unlock inside grace period")

# 2. Tier 1 Idle Fee Test (30 minutes after stop = 1800s)
# 15 mins billable at $0.50/min = $7.50
var res_tier1 = mgr.calculate_idle_fee(1, t0 + 1800, 0.5)
assert_equal(res_tier1["fee"], 7.50, "Accrued $7.50 Tier 1 idle fee")
assert_equal(res_tier1["status"], "IDLE_FEE_ACCRUING", "Status is IDLE_FEE_ACCRUING")
assert_true(res_tier1["auto_unlock_triggered"], "Auto-unlock triggered after grace period")

# 3. Tier 2 Idle Fee Test (60 minutes after stop = 3600s)
# 30 mins Tier 1 ($15.00) + 15 mins Tier 2 ($15.00) = $30.00
var res_tier2 = mgr.calculate_idle_fee(1, t0 + 3600, 0.5)
assert_equal(res_tier2["fee"], 30.00, "Accrued $30.00 combined Tier 1 and Tier 2 idle fee")

# 4. Congestion Multiplier (Occupancy >= 80% doubles idle fee)
var res_congested = mgr.calculate_idle_fee(1, t0 + 3600, 0.85)
assert_equal(res_congested["fee"], 60.00, "Congestion doubles fee to $60.00")
assert_equal(res_congested["congestion_multiplier"], 2.0, "Multiplier is 2.0")

# 5. Cap Enforcement ($100 cap)
# 10 hours idle = 600 mins * $1.00 * 2 = $1200 -> capped at $100.00
var res_capped = mgr.calculate_idle_fee(1, t0 + 36000, 0.90)
assert_equal(res_capped["fee"], 100.00, "Fee capped at $100.00 max")

# 6. Unplug Event & Finalization
mgr.register_unplug(1, t0 + 1800)
var res_final = mgr.calculate_idle_fee(1, t0 + 999999, 0.5)
assert_equal(res_final["fee"], 7.50, "Unplug freezes accrued fee at $7.50")

print("test_overstay_manager: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
