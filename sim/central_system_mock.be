# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Mock OCPP 2.0.1 Central System Management Server (CSMS)
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import json
import time_util as TimeUtil
import frame as OcppFrame

# Simulates an enterprise OCPP 2.0.1 Charging Station Management System (CSMS).
# Receives JSON-RPC frames over WebSocket transport, responds to station requests,
# and issues server-initiated commands (SetChargingProfile, Reset, Unlock).
class CentralSystemMock
    var authorized_tokens
    var received_messages
    var sent_messages
    var pending_commands
    var station_registration_status
    var heartbeat_interval_sec
    var current_station_time_epoch

    def init()
        self.authorized_tokens = {
            "RFID-OPERATOR-999": {"status": "Accepted", "groupIdToken": "SUPERVISOR"},
            "FLEET-VAN-01": {"status": "Accepted", "groupIdToken": "DEPOT-FLEET"},
            "FLEET-VAN-02": {"status": "Accepted", "groupIdToken": "DEPOT-FLEET"},
            "FLEET-VAN-03": {"status": "Accepted", "groupIdToken": "DEPOT-FLEET"},
            "RFID-VIP-DRIVER": {"status": "Accepted", "groupIdToken": "EXECUTIVE"},
            "REVOKED-TAG-404": {"status": "Blocked", "groupIdToken": "BLOCKED"}
        }
        self.received_messages = []
        self.sent_messages = []
        self.pending_commands = []
        self.station_registration_status = "Accepted"
        self.heartbeat_interval_sec = 60
        self.current_station_time_epoch = 1770000000
    end

    def add_authorized_token(token_id, status, group_id)
        self.authorized_tokens[str(token_id)] = {
            "status": (status != nil) ? str(status) : "Accepted",
            "groupIdToken": (group_id != nil) ? str(group_id) : "STANDARD"
        }
    end

    # Handle an inbound JSON-RPC frame string from the station
    def handle_station_frame(raw_json_str)
        var frame = OcppFrame.parse(raw_json_str)
        if frame == nil
            return nil
        end

        var msg_type = frame.message_type_id
        var msg_id = frame.message_id

        if msg_type == 2 # CALL
            var action = frame.action
            var payload = frame.payload

            self.received_messages.push({
                "type": "CALL",
                "action": action,
                "message_id": msg_id,
                "payload": payload
            })

            return self._dispatch_call_response(msg_id, action, payload)
        elif msg_type == 3 # CALLRESULT
            self.received_messages.push({
                "type": "CALLRESULT",
                "message_id": msg_id,
                "payload": frame.payload
            })
            return nil
        elif msg_type == 4 # CALLERROR
            self.received_messages.push({
                "type": "CALLERROR",
                "message_id": msg_id,
                "error_code": frame.error_code,
                "error_desc": frame.error_description
            })
            return nil
        end
        return nil
    end

    # Dispatch CALL response payload according to OCPP 2.0.1 specification
    def _dispatch_call_response(msg_id, action, payload)
        var response_payload = {}
        var now_iso = TimeUtil.to_iso8601(self.current_station_time_epoch)

        if action == "BootNotification"
            response_payload = {
                "currentTime": now_iso,
                "interval": self.heartbeat_interval_sec,
                "status": self.station_registration_status
            }
        elif action == "Heartbeat"
            response_payload = {
                "currentTime": now_iso
            }
        elif action == "StatusNotification"
            response_payload = {}
        elif action == "Authorize"
            var token_info = self._lookup_token(payload)
            response_payload = {
                "idTokenInfo": token_info
            }
        elif action == "TransactionEvent"
            var event_type = payload.find("eventType")
            var token_info = self._lookup_token(payload)
            response_payload = {
                "totalCost": 0.0,
                "idTokenInfo": token_info
            }
        elif action == "MeterValues"
            response_payload = {}
        elif action == "SecurityEventNotification"
            response_payload = {}
        elif action == "LogStatusNotification"
            response_payload = {}
        else
            # Default generic acceptance for unmodeled RPCs
            response_payload = {"status": "Accepted"}
        end

        var reply_frame = OcppFrame.create_call_result(msg_id, response_payload)
        var reply_json = reply_frame.serialize()
        self.sent_messages.push({
            "type": "CALLRESULT",
            "message_id": msg_id,
            "action": action,
            "payload": response_payload
        })
        return reply_json
    end

    def _lookup_token(payload)
        var id_token_obj = payload.find("idToken")
        var token_str = ""
        if isinstance(id_token_obj, map)
            token_str = str(id_token_obj.find("idToken"))
        elif id_token_obj != nil
            token_str = str(id_token_obj)
        end

        var entry = self.authorized_tokens.find(token_str)
        if entry != nil
            return {
                "status": entry["status"],
                "groupIdToken": entry["groupIdToken"]
            }
        end
        return {
            "status": "Unknown",
            "groupIdToken": "GUEST"
        }
    end

    # Create server-initiated SetChargingProfile command frame
    def make_set_charging_profile_call(msg_id, evse_id, limit_amps)
        var payload = {
            "evseId": int(evse_id),
            "chargingProfile": {
                "id": 101,
                "stackLevel": 1,
                "chargingProfilePurpose": "TxDefaultProfile",
                "chargingProfileKind": "Absolute",
                "chargingSchedule": [{
                    "id": 1,
                    "startSchedule": TimeUtil.to_iso8601(self.current_station_time_epoch),
                    "duration": 7200,
                    "chargingRateUnit": "A",
                    "chargingSchedulePeriod": [{
                        "startPeriod": 0,
                        "limit": real(limit_amps),
                        "numberPhases": 3
                    }]
                }]
            }
        }
        var frame = OcppFrame.create_call("SetChargingProfile", payload)
        frame.message_id = str(msg_id)
        self.sent_messages.push({"type": "CALL", "action": "SetChargingProfile", "message_id": str(msg_id)})
        return frame.serialize()
    end

    # Create server-initiated Reset command frame
    def make_reset_call(msg_id, reset_type)
        var payload = {
            "type": (reset_type != nil) ? str(reset_type) : "OnIdle"
        }
        var frame = OcppFrame.create_call("Reset", payload)
        frame.message_id = str(msg_id)
        self.sent_messages.push({"type": "CALL", "action": "Reset", "message_id": str(msg_id)})
        return frame.serialize()
    end

    # Find total count of received messages matching action
    def count_received_action(action_name)
        var cnt = 0
        var i = 0
        while i < size(self.received_messages)
            var m = self.received_messages[i]
            if m.find("action") == action_name
                cnt = cnt + 1
            end
            i = i + 1
        end
        return cnt
    end
end

return CentralSystemMock
