# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# End-to-End Session Lifecycle Coordinator & Multi-Step Handshake Engine
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import time_util as TimeUtil

class SessionCoordinator
    var evse_channel
    var auth_manager
    var current_step
    var session_log

    def init(evse_channel, auth_manager)
        self.evse_channel = evse_channel
        self.auth_manager = auth_manager
        self.current_step = "Idle"
        self.session_log = []
    end

    def _log(msg)
        self.session_log.push(msg)
        print("[SessionCoord EVSE " + str(self.evse_channel.evse_id) + "] " + msg)
    end

    # Complete automated sequence: Plug In -> Authorize -> Lock -> Energize -> Charge
    def execute_session_start(id_token, timestamp_sec)
        self._log("Step 1: Vehicle physical cable plugged in")
        self.evse_channel.plug_in_vehicle()
        self.current_step = "Preparing"

        self._log("Step 2: Authorizing RFID IdToken: " + str(id_token))
        var auth_res = self.auth_manager.verify_token_locally(id_token, timestamp_sec)
        if auth_res["status"] != Types.AUTH_ACCEPTED
            self._log("Authorization Failed: " + auth_res["status"])
            self.current_step = "AuthFailed"
            return false
        end

        self._log("Step 3: IdToken Accepted (" + auth_res["source"] + ") - Engaging motorized cable lock")
        var started = self.evse_channel.authorize_and_start(id_token, timestamp_sec)
        if !started
            self._log("Failed to start session on EVSE channel")
            self.current_step = "StartFailed"
            return false
        end

        self._log("Step 4: Contactors closed - Power delivery active")
        self.current_step = "Charging"
        return true
    end

    # Complete automated termination sequence: Stop command -> Open Contactors -> Retract Lock -> Unplug
    def execute_session_stop(stopped_reason, timestamp_sec)
        self._log("Step 1: Stopping charging session: " + str(stopped_reason))
        self.evse_channel.stop_transaction(stopped_reason, timestamp_sec)
        self.current_step = "Finishing"

        self._log("Step 2: Contactors opened - Retracting motorized cable lock")
        self.evse_channel.unplug_vehicle()
        self.current_step = "Idle"
        self._log("Step 3: Cable removed - EVSE returned to Available state")
        return true
    end
end

return SessionCoordinator
