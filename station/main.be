# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Demonstration CLI Application & Interactive Station Emulation
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import config as StationConfig
import controller as StationController
import hmi as StationHMI
import billing as BillingCalculator
import math_ext as MathExt
import types as Types
import string

def main()
    print("================================================================================")
    print("  STANCHION: Embedded EV Charging Station Controller & Energy Router")
    print("  IEC 61851-1 / ISO 15118 / OCPP 2.0.1 Multi-Channel Power Router")
    print("  Copyright (c) 2026 Aneesh Krishna. All rights reserved.")
    print("================================================================================")
    print("")

    # 1. Initialize Station Controller
    print("[INIT] Loading station configuration...")
    var cfg = StationConfig()
    cfg.station_id = "STANCHION-DEMO-01"
    cfg.model = "Stanchion-HyperCharge-150"
    cfg.evse_count = 4
    cfg.max_grid_current_a = 64.0 # 64A dynamic grid threshold
    print("[INIT] Station ID: " + cfg.station_id + " (" + cfg.model + ")")
    print("[INIT] Configured " + str(cfg.evse_count) + " EVSE channels with 64.0A aggregate grid limit")

    var station = StationController(cfg)
    print("[INIT] Subsystems initialized: DLM, PhaseBalancer, SafetyMonitor, Telemetry")
    print("")

    # 2. Simulate Vehicle 1 arrival and plug-in on EVSE 1
    print("[EVENT] EV 1 arrives at EVSE 1 (Tesla Model 3, 75 kWh pack)")
    station.evse_channels[1].plug_in_vehicle()
    print("[EVENT] EV 1 Control Pilot state: B (Vehicle Detected), Cable rating: 32A")
    print("[EVENT] Driver swipes RFID tag: RFID-DRIVER-VIP-01")
    station.evse_channels[1].authorize_and_start("RFID-DRIVER-VIP-01", 1770000000)
    print("[EVENT] RFID Authorization Accepted. Contactor closed, charging session started.")
    print("")

    # 3. Simulate Vehicle 2 arrival on EVSE 2
    print("[EVENT] EV 2 arrives at EVSE 2 (Polestar 2, 78 kWh pack)")
    station.evse_channels[2].plug_in_vehicle()
    print("[EVENT] Driver swipes RFID tag: RFID-FLEET-VAN-02")
    station.evse_channels[2].authorize_and_start("RFID-FLEET-VAN-02", 1770000000)
    print("[EVENT] RFID Authorization Accepted. Contactor closed, charging session started.")
    print("")

    # 4. Run multi-step simulation loop with live telemetry updates
    print("[RUN] Executing 5-minute accelerated charging control loop...")
    print("--------------------------------------------------------------------------------")

    var step_sec = 60
    var step = 1
    while step <= 5
        var current_time = 1770000000 + (step * step_sec)
        station.step(current_time)

        # Synthesize real-world energy meter telemetry
        var e1 = station.get_evse(1)
        var e2 = station.get_evse(2)

        # 3-phase meter measurement update
        e1.meter.update_samples(230.0, e1.current_allocated_amps, 230.0, e1.current_allocated_amps, 230.0, e1.current_allocated_amps, 0.99, 50.0, current_time)
        e2.meter.update_samples(230.0, e2.current_allocated_amps, 230.0, e2.current_allocated_amps, 230.0, e2.current_allocated_amps, 0.99, 50.0, current_time)

        var p1_kw = (e1.current_allocated_amps * 230.0 * 3.0) / 1000.0
        var p2_kw = (e2.current_allocated_amps * 230.0 * 3.0) / 1000.0
        var total_kw = p1_kw + p2_kw

        print("  [T+" + str(step * 60) + "s] EVSE 1: " + str(MathExt.round_to(e1.current_allocated_amps, 1)) + "A (" + str(MathExt.round_to(p1_kw, 2)) + " kW) | " +
              "EVSE 2: " + str(MathExt.round_to(e2.current_allocated_amps, 1)) + "A (" + str(MathExt.round_to(p2_kw, 2)) + " kW) | " +
              "Total Station Power: " + str(MathExt.round_to(total_kw, 2)) + " kW / 44.16 kW Cap")

        step = step + 1
    end
    print("--------------------------------------------------------------------------------")
    print("")

    # 5. Render Full Station HMI Dashboard
    print("[HMI] Current Station Live Status Matrix:")
    StationHMI.render_dashboard(station, 1770000300)
    print("")

    # 6. Stop EVSE 1 session and generate itemized billing receipt
    print("[EVENT] Driver 1 swipes card to conclude session.")
    station.evse_channels[1].stop_transaction("Local", 1770000300)
    station.evse_channels[1].unplug_vehicle()
    print("[EVENT] Connector unlocked. Vehicle unplugged.")
    print("")

    print("[BILLING] Generating Itemized Session Invoice:")
    var billing = BillingCalculator(0.0825, "USD")
    var inv = billing.generate_invoice("TX-9988-AA", 1, "RFID-DRIVER-VIP-01", 1.84, 0.22, 1.00, 0.0, 0.50)
    var lines = inv["line_items"]
    print("--------------------------------------------------------------------------------")
    print(string.format("  Invoice ID        : %s", inv["invoice_id"]))
    print(string.format("  Transaction Ref   : %s", inv["transaction_id"]))
    print(string.format("  Driver Badge ID   : %s", inv["id_token"]))
    print(string.format("  Active Energy     : %6.3f kWh @ $%.4f/kWh -> $%.2f", lines["energy_kwh"], lines["energy_rate"], lines["energy_subtotal"]))
    print(string.format("  Connection Fee    : $%.2f", lines["connection_fee"]))
    print(string.format("  Clean Credit Vchr : -$%.2f", lines["discount_applied"]))
    print(string.format("  Subtotal          : $%.2f", lines["subtotal"]))
    print(string.format("  Sales Tax (8.25%%) : $%.2f", lines["tax_amount"]))
    print(string.format("  GRAND TOTAL       : $%.2f %s", lines["grand_total"], inv["currency"]))
    print("--------------------------------------------------------------------------------")
    print("")

    print("================================================================================")
    print("  Stanchion Controller demonstration finished successfully.")
    print("================================================================================")
end

main()
