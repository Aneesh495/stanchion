# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# EVSE Channel Controller, Hardware Integration & Periodic Safety Loop
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import pilot as ControlPilot
import meter as EnergyMeter
import contactor as Contactor
import safety as SafetySupervisor
import lock as ConnectorLock
import display as StationDisplay
import connector as Connector
import transaction as Transaction
import fsm as FSM

class EVSEChannel
    var evse_id
    var connector
    var pilot
    var meter
    var contactor
    var safety
    var lock
    var display
    var fsm
    var active_transaction
    var current_allocated_amps
    var is_operational

    def init(evse_id, rated_current_a)
        self.evse_id = int(evse_id)
        rated_current_a = (rated_current_a != nil) ? real(rated_current_a) : 32.0

        self.connector = Connector(self.evse_id, 1, Types.CONNECTOR_TYPE_TYPE2, 400.0, rated_current_a)
        self.pilot = ControlPilot(self.evse_id)
        self.meter = EnergyMeter(self.evse_id)
        self.contactor = Contactor(self.evse_id)
        self.safety = SafetySupervisor(self.evse_id, rated_current_a)
        self.lock = ConnectorLock(self.evse_id)
        self.display = StationDisplay(self.evse_id)

        self.active_transaction = nil
        self.current_allocated_amps = 0.0
        self.is_operational = true

        self._setup_fsm()
    end

    def _setup_fsm()
        self.fsm = FSM("EVSE_" + str(self.evse_id), Types.STATE_AVAILABLE, {"evse_id": self.evse_id})

        # Transitions
        self.fsm.add_transition(Types.STATE_AVAILABLE, "PLUGIN", Types.STATE_PREPARING, nil,
            def(ctx, d) self.display.set_preparing() end)

        self.fsm.add_transition(Types.STATE_PREPARING, "AUTH_OK", Types.STATE_CHARGING,
            def(ctx) return self.lock.is_connector_locked() end,
            def(ctx, d)
                self.contactor.close(0)
                self.pilot.set_charging_current_limit(self.current_allocated_amps)
                self.display.set_charging(self.meter.get_total_active_power_kw(), nil)
            end)

        self.fsm.add_transition(Types.STATE_CHARGING, "SUSPEND_EV", Types.STATE_SUSPENDED_EV, nil,
            def(ctx, d)
                self.contactor.open(0)
                self.display.set_suspended_ev()
            end)

        self.fsm.add_transition(Types.STATE_SUSPENDED_EV, "RESUME_EV", Types.STATE_CHARGING, nil,
            def(ctx, d)
                self.contactor.close(0)
                self.display.set_charging(self.meter.get_total_active_power_kw(), nil)
            end)

        self.fsm.add_transition(Types.STATE_CHARGING, "STOP", Types.STATE_FINISHING, nil,
            def(ctx, d)
                self.contactor.open(0)
                self.pilot.set_charging_current_limit(0.0)
                self.lock.unlock()
            end)

        self.fsm.add_transition(Types.STATE_SUSPENDED_EV, "STOP", Types.STATE_FINISHING, nil,
            def(ctx, d)
                self.lock.unlock()
            end)

        self.fsm.add_transition(Types.STATE_FINISHING, "UNPLUG", Types.STATE_AVAILABLE, nil,
            def(ctx, d)
                self.display.set_available()
            end)

        self.fsm.add_transition(Types.STATE_FAULTED, "RESET", Types.STATE_AVAILABLE, nil,
            def(ctx, d)
                self.display.set_available()
            end)

        self.fsm.add_transition(Types.STATE_FAULTED, "UNPLUG", Types.STATE_AVAILABLE, nil,
            def(ctx, d)
                self.display.set_available()
            end)

        self.fsm.add_transition("*", "FAULT", Types.STATE_FAULTED, nil,
            def(ctx, d)
                self.contactor.open(0)
                self.pilot.set_charging_current_limit(0.0)
                self.display.set_faulted(d)
            end)
    end

    # Set dynamic allocated current from DLM
    def set_allocated_amps(amps)
        self.current_allocated_amps = real(amps)
        if self.fsm.is_in_state(Types.STATE_CHARGING)
            self.pilot.set_charging_current_limit(self.current_allocated_amps)
        end
    end

    # Periodic control loop step (e.g. called every 100ms or 1s)
    def step(timestamp_sec)
        timestamp_sec = int(timestamp_sec)

        # 1. Evaluate safety telemetry
        var max_phase_i = self.meter.get_total_current_a() / 3.0
        var safe = self.safety.evaluate_safety(0.0, 0.0, max_phase_i, self.meter.phase_l1.voltage_ln_v, 30.0, 30.0, 1.0)
        if !safe
            self.fsm.trigger("FAULT", "SafetyTrip")
            return
        end

        # 2. Sync pilot state to FSM
        if self.pilot.current_state == Types.PILOT_STATE_A && !self.fsm.is_in_state(Types.STATE_AVAILABLE)
            if self.fsm.is_in_state(Types.STATE_FINISHING)
                self.fsm.trigger("UNPLUG", nil)
            end
        elif self.pilot.current_state == Types.PILOT_STATE_B && self.fsm.is_in_state(Types.STATE_AVAILABLE)
            self.fsm.trigger("PLUGIN", nil)
        elif self.pilot.current_state == Types.PILOT_STATE_B && self.fsm.is_in_state(Types.STATE_CHARGING)
            # Vehicle paused charging (State B: 9V)
            self.fsm.trigger("SUSPEND_EV", nil)
        elif self.pilot.current_state == Types.PILOT_STATE_C && self.fsm.is_in_state(Types.STATE_SUSPENDED_EV)
            # Vehicle resumed charging (State C: 6V)
            self.fsm.trigger("RESUME_EV", nil)
        end

        # 3. Update active transaction energy if charging
        if self.active_transaction != nil && self.active_transaction.is_active
            self.active_transaction.update_energy(self.meter.energy_import_total_kwh)
        end
    end

    def plug_in_vehicle()
        self.pilot.update_pilot_measurement(9.0, 0) # 9V = Connected
        self.connector.set_state(Types.STATE_PREPARING)
        self.fsm.trigger("PLUGIN", nil)
    end

    def authorize_and_start(token_str, timestamp_sec)
        if !self.fsm.is_in_state(Types.STATE_PREPARING)
            return false
        end
        # Lock connector
        self.lock.lock()
        # Initialize transaction
        self.active_transaction = Transaction(self.evse_id, 1, token_str, self.meter.energy_import_total_kwh, timestamp_sec)
        # Advance pilot to 6V (Vehicle ready)
        self.pilot.update_pilot_measurement(6.0, 0)
        self.fsm.trigger("AUTH_OK", nil)
        self.connector.set_state(Types.STATE_CHARGING)
        return true
    end

    def stop_transaction(stopped_reason, timestamp_sec)
        if self.active_transaction != nil && self.active_transaction.is_active
            self.active_transaction.stop(timestamp_sec, self.meter.energy_import_total_kwh, stopped_reason)
        end
        self.fsm.trigger("STOP", nil)
        self.connector.set_state(Types.STATE_FINISHING)
    end

    def unplug_vehicle()
        self.pilot.update_pilot_measurement(12.0, 0) # 12V = Disconnected
        self.fsm.trigger("UNPLUG", nil)
        self.connector.set_state(Types.STATE_AVAILABLE)
    end

    def get_state()
        return self.fsm.get_state()
    end
end

return EVSEChannel
