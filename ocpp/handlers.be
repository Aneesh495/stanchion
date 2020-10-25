# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Inbound CSMS RPC Action Handlers, Request Validation & CallResult Encoders
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import frame as OCPPFrame
import messages as OCPPMessages
import types as Types

class OCPPHandlers
    var station_controller
    var energy_manager
    var action_handlers

    def init(station_controller, energy_manager)
        self.station_controller = station_controller
        self.energy_manager = energy_manager
        self.action_handlers = {}
        self._register_default_handlers()
    end

    def _register_default_handlers()
        self.action_handlers["Reset"] = def(f) return self.handle_reset(f) end
        self.action_handlers["UnlockConnector"] = def(f) return self.handle_unlock_connector(f) end
        self.action_handlers["ChangeAvailability"] = def(f) return self.handle_change_availability(f) end
        self.action_handlers["SetChargingProfile"] = def(f) return self.handle_set_charging_profile(f) end
        self.action_handlers["ClearChargingProfile"] = def(f) return self.handle_clear_charging_profile(f) end
        self.action_handlers["RequestStartTransaction"] = def(f) return self.handle_request_start_transaction(f) end
        self.action_handlers["RequestStopTransaction"] = def(f) return self.handle_request_stop_transaction(f) end
        self.action_handlers["TriggerMessage"] = def(f) return self.handle_trigger_message(f) end
    end

    # Dispatch incoming CALL frame to the appropriate action handler
    def dispatch(call_frame)
        if call_frame == nil || call_frame.action == nil
            return OCPPFrame.create_call_error(call_frame.message_id, "FormationViolation", "Null frame or action", {})
        end

        var action = call_frame.action
        if self.action_handlers.contains(action)
            try
                return self.action_handlers[action](call_frame)
            except .. as err
                return OCPPFrame.create_call_error(call_frame.message_id, "InternalError", str(err), {})
            end
        else
            return OCPPFrame.create_call_error(call_frame.message_id, "NotImplemented",
                "Action not supported: " + action, {})
        end
    end

    def handle_reset(frame)
        var reset_type = "Soft"
        if frame.payload.contains("type")
            reset_type = frame.payload["type"]
        end
        print("[OCPP Handlers] Received Reset request: " + reset_type)

        var status = "Accepted"
        if self.station_controller != nil
            if reset_type == "Hard"
                self.station_controller.trigger_hard_reset()
            else
                self.station_controller.trigger_soft_reset()
            end
        end
        return OCPPFrame.create_call_result(frame.message_id, {"status": status})
    end

    def handle_unlock_connector(frame)
        var evse_id = frame.payload.contains("evseId") ? int(frame.payload["evseId"]) : 1
        print("[OCPP Handlers] Received UnlockConnector for EVSE " + str(evse_id))

        var status = "UnlockFailed"
        if self.station_controller != nil
            if self.station_controller.unlock_connector(evse_id)
                status = "Unlocked"
            end
        else
            status = "Unlocked"
        end
        return OCPPFrame.create_call_result(frame.message_id, {"status": status})
    end

    def handle_change_availability(frame)
        var evse_id = frame.payload.contains("evseId") ? int(frame.payload["evseId"]) : 0
        var oper_status = frame.payload.contains("operationalStatus") ? frame.payload["operationalStatus"] : "Operative"
        print("[OCPP Handlers] ChangeAvailability EVSE " + str(evse_id) + " -> " + oper_status)

        var status = "Accepted"
        if self.station_controller != nil
            self.station_controller.set_availability(evse_id, oper_status == "Operative")
        end
        return OCPPFrame.create_call_result(frame.message_id, {"status": status})
    end

    def handle_set_charging_profile(frame)
        var evse_id = frame.payload.contains("evseId") ? int(frame.payload["evseId"]) : 0
        var profile_data = frame.payload.contains("chargingProfile") ? frame.payload["chargingProfile"] : nil

        var status = "Rejected"
        if profile_data != nil && self.energy_manager != nil
            if self.energy_manager.apply_smart_charging_profile(evse_id, profile_data)
                status = "Accepted"
            end
        elif profile_data != nil
            status = "Accepted"
        end
        return OCPPFrame.create_call_result(frame.message_id, {"status": status})
    end

    def handle_clear_charging_profile(frame)
        var profile_id = frame.payload.contains("chargingProfileId") ? int(frame.payload["chargingProfileId"]) : nil
        var status = "Unknown"
        if self.energy_manager != nil
            if self.energy_manager.clear_profile(profile_id)
                status = "Accepted"
            end
        else
            status = "Accepted"
        end
        return OCPPFrame.create_call_result(frame.message_id, {"status": status})
    end

    def handle_request_start_transaction(frame)
        var evse_id = frame.payload.contains("evseId") ? int(frame.payload["evseId"]) : 1
        var id_token_obj = frame.payload.contains("idToken") ? frame.payload["idToken"] : nil
        var token_str = (id_token_obj != nil && id_token_obj.contains("idToken")) ? id_token_obj["idToken"] : "REMOTE"

        var status = "Accepted"
        if self.station_controller != nil
            if !self.station_controller.start_remote_transaction(evse_id, token_str)
                status = "Rejected"
            end
        end
        return OCPPFrame.create_call_result(frame.message_id, {"status": status})
    end

    def handle_request_stop_transaction(frame)
        var tx_id = frame.payload.contains("transactionId") ? str(frame.payload["transactionId"]) : ""
        var status = "Accepted"
        if self.station_controller != nil
            if !self.station_controller.stop_remote_transaction(tx_id)
                status = "Rejected"
            end
        end
        return OCPPFrame.create_call_result(frame.message_id, {"status": status})
    end

    def handle_trigger_message(frame)
        var requested_msg = frame.payload.contains("requestedMessage") ? frame.payload["requestedMessage"] : ""
        print("[OCPP Handlers] TriggerMessage: " + requested_msg)
        return OCPPFrame.create_call_result(frame.message_id, {"status": "Accepted"})
    end
end

return OCPPHandlers
