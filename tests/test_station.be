# Stanchion Test Suite: Charging Station Controller & Session Orchestration
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import connector as Connector
import evse as EVSEChannel
import controller as StationController
import session as SessionCoordinator
import telemetry as StationTelemetry
import hmi as StationHMI
import types as Types
import config as StationConfig
import math
import string
import global

var total_assertions = 0

def check(condition, desc)
    global.total_assertions = global.total_assertions + 1
    if !condition
        print("[FAIL] " + desc)
        assert(false)
    end
end

print(">>> Running test_station.be ...")

# 1. Connector Model
var conn = Connector(1, 1, Types.CONNECTOR_TYPE_TYPE2, 400.0, 32.0)
check(conn.is_available() == true, "Connector starts available")
conn.set_operational_status("Inoperative")
check(conn.is_available() == false, "Inoperative connector is unavailable")
conn.set_operational_status("Operative")
conn.set_state(Types.STATE_AVAILABLE)

# 2. EVSE Channel & FSM
var evse = EVSEChannel(1, 32.0)
check(evse.get_state() == Types.STATE_AVAILABLE, "EVSE starts in Available state")

# Plug in vehicle
evse.plug_in_vehicle()
check(evse.get_state() == Types.STATE_PREPARING, "EVSE transitioned to Preparing")

# Authorize and start
var started = evse.authorize_and_start("RFID-USER-42", 1000)
check(started == true, "Authorize and start succeeded")
check(evse.get_state() == Types.STATE_CHARGING, "EVSE transitioned to Charging")
check(evse.lock.is_connector_locked() == true, "Connector lock engaged")
check(evse.contactor.is_closed() == true, "Contactor closed for power delivery")

# Stop transaction
evse.stop_transaction("Local", 2000)
check(evse.get_state() == Types.STATE_FINISHING, "EVSE transitioned to Finishing")
check(evse.contactor.is_open() == true, "Contactor opened")
check(evse.lock.is_connector_locked() == false, "Connector lock unlocked")

# Unplug
evse.unplug_vehicle()
check(evse.get_state() == Types.STATE_AVAILABLE, "EVSE returned to Available")

# 3. Station Controller & Multi-Channel DLM
var cfg = StationConfig()
cfg.evse_count = 4
cfg.max_grid_current_a = 64.0 # 64A total depot capacity
var station = StationController(cfg)
check(station.evse_channels.size() == 4, "Station initialized with 4 EVSE channels")

# Start charging on EVSE 1 and EVSE 2
station.evse_channels[1].plug_in_vehicle()
station.evse_channels[1].authorize_and_start("TOKEN-1", 1000)
station.evse_channels[2].plug_in_vehicle()
station.evse_channels[2].authorize_and_start("TOKEN-2", 1000)

# Run controller step
station.step(1010)
# 64A split across 2 active EVSEs = 32A allocated each
check(station.evse_channels[1].current_allocated_amps == 32.0, "EVSE 1 allocated 32A")
check(station.evse_channels[2].current_allocated_amps == 32.0, "EVSE 2 allocated 32A")

# Emergency stop test
station.press_emergency_stop()
check(station.emergency_stop_active == true, "Emergency stop active")
check(station.evse_channels[1].contactor.is_open() == true, "EVSE 1 contactor forced open")
check(station.evse_channels[2].contactor.is_open() == true, "EVSE 2 contactor forced open")
station.release_emergency_stop()

# 4. Session Coordinator Automated Flow
var ch3 = station.evse_channels[3]
station.auth_manager.add_whitelist_entry("BADGE-AUTO-01", nil, Types.AUTH_ACCEPTED, 0, "Standard", nil)
var coord = SessionCoordinator(ch3, station.auth_manager)

var ok_start = coord.execute_session_start("BADGE-AUTO-01", 1500)
check(ok_start == true, "SessionCoordinator start completed")
check(ch3.get_state() == Types.STATE_CHARGING, "Channel 3 in Charging state")

var ok_stop = coord.execute_session_stop("LocalUser", 2500)
check(ok_stop == true, "SessionCoordinator stop completed")
check(ch3.get_state() == Types.STATE_AVAILABLE, "Channel 3 back in Available state")

# 5. Station Telemetry
var telem = StationTelemetry(10)
for i : 1 .. 5
    telem.sample(20.0 + real(i), 30.0, 230.0, 35.0, 50.0)
end
var summary = telem.get_summary()
check(summary["power_kw"]["current"] == 25.0, "Latest power = 25.0 kW")
check(summary["voltage_v"]["current"] == 230.0, "Latest voltage = 230.0 V")
check(summary["frequency_hz"]["current"] == 50.0, "Latest freq = 50.0 Hz")

# 6. HMI Dashboard bar rendering
var bar = StationHMI.render_bar(50.0, 100.0, 10)
check(bar == "#####-----", "Rendered 50% bar correctly")

print(string.format("[PASS] test_station.be passed with %d assertions verified.", total_assertions))
