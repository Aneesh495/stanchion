# Stanchion Test Suite: Diagnostics, Offline Store & Telemetry Metrics
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import offline_store as OfflineStore
import network as NetworkManager
import metrics as MetricsRegistry
import fault_recorder as FaultRecorderModule
import health as HealthSupervisor
import math
import string
import global

var FaultRecorder = FaultRecorderModule["Recorder"]

var total_assertions = 0

def check(condition, desc)
    global.total_assertions = global.total_assertions + 1
    if !condition
        print("[FAIL] " + desc)
        assert(false)
    end
end

print(">>> Running test_diag.be ...")

# 1. Offline Store & Replay Spooler
var store = OfflineStore(10)
store.append_entry("MeterValues", {"power": 22.0}, 1000)
store.append_entry("StatusNotification", {"status": "Charging"}, 1005)
check(store.pending_count() == 2, "OfflineStore has 2 pending entries")

# Replay messages
var replayed_messages = []
var dispatch_fn = def(action, payload)
    replayed_messages.push(action)
    return true # Dispatch succeeded
end

var replayed_cnt = store.replay_all(dispatch_fn)
check(replayed_cnt == 2, "Replayed 2 spooled messages")
check(store.pending_count() == 0, "Spool queue empty after full replay")
check(replayed_messages[0] == "MeterValues", "First replayed message is MeterValues")
check(replayed_messages[1] == "StatusNotification", "Second replayed message is StatusNotification")

# 2. Network Manager & Exponential Backoff
var net = NetworkManager("wss://csms.stanchion.com/ocpp201", 2, 60)
check(net.is_connected() == false, "Starts disconnected")
net.connect_success()
check(net.is_connected() == true, "Connected status confirmed")

# Drop connection at t=1000
net.trigger_disconnect(1000)
check(net.current_backoff_sec == 2, "First backoff is 2s (base)")
check(net.next_reconnect_epoch_sec == 1002, "Reconnect scheduled at 1002")
check(!net.check_reconnect(1001), "Cannot reconnect before 1002")
check(net.check_reconnect(1002), "Reconnect allowed at 1002")

# Second drop -> exponential backoff doubles
net.trigger_disconnect(1002)
check(net.current_backoff_sec == 4, "Second backoff is 4s (doubled)")
check(net.next_reconnect_epoch_sec == 1006, "Reconnect scheduled at 1006")

# 3. Metrics Registry & Prometheus Export
var metrics = MetricsRegistry()
var c_sessions = metrics.get_counter("stanchion_charging_sessions_total")
c_sessions.inc(1.0)
c_sessions.inc(2.0)
check(c_sessions.get() == 3.0, "Counter accumulated to 3")

var g_power = metrics.get_gauge("stanchion_grid_power_kw")
g_power.set(45.5)
g_power.inc(5.0)
check(g_power.get() == 50.5, "Gauge updated to 50.5 kW")

var prom_text = metrics.export_prometheus_text()
check(string.find(prom_text, "stanchion_charging_sessions_total 3") >= 0, "Prometheus export has sessions total")
check(string.find(prom_text, "stanchion_grid_power_kw 50.5") >= 0, "Prometheus export has grid power")

# 4. Fault Freeze-Frame Recorder
var recorder = FaultRecorder(16)
var fid = recorder.capture_freeze_frame(
    1, "GroundFailure", 1000,
    [230.0, 229.5, 230.2], [32.0, 31.8, 32.1],
    6.0, "C", "Closed",
    45.0, 42.0, 35.5, 0.0
)
check(fid == 1, "Captured freeze frame #1")
check(recorder.count() == 1, "Recorder holds 1 frame")
var latest = recorder.get_latest_fault()
check(latest.error_code == "GroundFailure", "Error code recorded")
check(latest.rcd_ac_ma == 35.5, "RCD AC leakage 35.5mA recorded")

# 5. Health Supervisor & Watchdog
var health = HealthSupervisor()
health.register_subsystem("DLM_Worker", 5) # 5s timeout
health.register_subsystem("HAL_Worker", 5)

health.ping("DLM_Worker", 100)
health.ping("HAL_Worker", 100)
check(health.evaluate_all(102) == true, "Subsystems healthy within threshold")

# Stall HAL_Worker (no ping at 107)
health.ping("DLM_Worker", 106)
var ok = health.evaluate_all(107)
check(ok == false, "Watchdog detected stalled HAL_Worker")
var rep = health.get_status_report()
check(rep["HAL_Worker"]["healthy"] == false, "HAL_Worker flagged unhealthy")
check(rep["DLM_Worker"]["healthy"] == true, "DLM_Worker remains healthy")

print(string.format("[PASS] test_diag.be passed with %d assertions verified.", total_assertions))
