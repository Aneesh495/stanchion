# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# OCPP-J (JSON over WebSocket) Protocol Framing & RPC Message Dispatcher
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import json
import string
import uuid as UUID

class MessageType
    static var CALL        = 2
    static var CALLRESULT  = 3
    static var CALLERROR   = 4
end

class OCPPErrorCode
    static var NOT_IMPLEMENTED         = "NotImplemented"
    static var SECURITY_ERROR           = "SecurityError"
    static var FORMATION_VIOLATION     = "FormationViolation"
    static var PROPERTY_CONSTRAINT     = "PropertyConstraintViolation"
    static var OCCURRENCE_CONSTRAINT   = "OccurrenceConstraintViolation"
    static var TYPE_CONSTRAINT         = "TypeConstraintViolation"
    static var PROTOCOL_ERROR          = "ProtocolError"
    static var INTERNAL_ERROR          = "InternalError"
end

class OCPPFrame
    var message_type_id
    var message_id
    var action
    var payload
    var error_code
    var error_description
    var error_details

    def init(msg_type, msg_id, action_or_payload)
        self.message_type_id = int(msg_type)
        self.message_id = (msg_id != nil) ? str(msg_id) : UUID.v4()
        self.action = nil
        self.payload = {}
        self.error_code = nil
        self.error_description = nil
        self.error_details = {}

        if self.message_type_id == MessageType.CALL
            self.action = str(action_or_payload)
        elif self.message_type_id == MessageType.CALLRESULT
            self.payload = (action_or_payload != nil) ? action_or_payload : {}
        end
    end

    static def create_call(action, payload)
        var f = OCPPFrame(MessageType.CALL, UUID.v4(), action)
        f.payload = (payload != nil) ? payload : {}
        return f
    end

    static def create_call_result(message_id, payload)
        var f = OCPPFrame(MessageType.CALLRESULT, message_id, payload)
        return f
    end

    static def create_call_error(message_id, error_code, error_desc, details)
        var f = OCPPFrame(MessageType.CALLERROR, message_id, nil)
        f.error_code = str(error_code)
        f.error_description = (error_desc != nil) ? str(error_desc) : ""
        f.error_details = (details != nil) ? details : {}
        return f
    end

    # Serialize frame into canonical OCPP-J JSON array string
    def serialize()
        var arr = []
        if self.message_type_id == MessageType.CALL
            # [2, "<uniqueId>", "<action>", {<payload>}]
            arr = [MessageType.CALL, self.message_id, self.action, self.payload]
        elif self.message_type_id == MessageType.CALLRESULT
            # [3, "<uniqueId>", {<payload>}]
            arr = [MessageType.CALLRESULT, self.message_id, self.payload]
        elif self.message_type_id == MessageType.CALLERROR
            # [4, "<uniqueId>", "<errorCode>", "<errorDescription>", {<errorDetails>}]
            arr = [MessageType.CALLERROR, self.message_id, self.error_code, self.error_description, self.error_details]
        end
        return json.dump(arr)
    end

    # Parse an incoming OCPP-J JSON string into an OCPPFrame instance
    static def parse(json_str)
        if json_str == nil
            return nil
        end
        var parsed = nil
        try
            parsed = json.load(json_str)
        except .. as err
            return nil
        end

        if type(parsed) != "instance" || classname(parsed) != "list" || parsed.size() < 3
            return nil
        end

        var msg_type = parsed[0]
        var msg_id = parsed[1]

        if msg_type == MessageType.CALL
            if parsed.size() < 4
                return nil
            end
            var f = OCPPFrame(MessageType.CALL, msg_id, parsed[2])
            f.payload = parsed[3]
            return f
        elif msg_type == MessageType.CALLRESULT
            var f = OCPPFrame(MessageType.CALLRESULT, msg_id, parsed[2])
            return f
        elif msg_type == MessageType.CALLERROR
            if parsed.size() < 5
                return nil
            end
            var f = OCPPFrame.create_call_error(msg_id, parsed[2], parsed[3], parsed[4])
            return f
        end
        return nil
    end
end

return OCPPFrame
