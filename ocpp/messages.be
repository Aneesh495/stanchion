# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# OCPP 2.0.1 Message Catalog, Payload Builders & Schema Validators
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import time_util as TimeUtil
import uuid as UUID

class OCPPAction
    static var BOOT_NOTIFICATION            = "BootNotification"
    static var HEARTBEAT                    = "Heartbeat"
    static var STATUS_NOTIFICATION          = "StatusNotification"
    static var AUTHORIZE                    = "Authorize"
    static var TRANSACTION_EVENT            = "TransactionEvent"
    static var METER_VALUES                 = "MeterValues"
    static var DATA_TRANSFER                = "DataTransfer"
    static var SECURITY_EVENT_NOTIFICATION  = "SecurityEventNotification"
    static var SET_CHARGING_PROFILE         = "SetChargingProfile"
    static var CLEAR_CHARGING_PROFILE       = "ClearChargingProfile"
    static var REQUEST_START_TRANSACTION    = "RequestStartTransaction"
    static var REQUEST_STOP_TRANSACTION     = "RequestStopTransaction"
    static var UNLOCK_CONNECTOR             = "UnlockConnector"
    static var RESET                        = "Reset"
    static var CHANGE_AVAILABILITY          = "ChangeAvailability"
    static var TRIGGER_MESSAGE              = "TriggerMessage"
    static var GET_VARIABLES               = "GetVariables"
    static var SET_VARIABLES               = "SetVariables"
end

class OCPPMessages
    # Build BootNotificationRequest payload
    static def boot_notification_req(vendor, model, serial_number, firmware_ver, reason)
        return {
            "reason": (reason != nil) ? str(reason) : "PowerUp",
            "chargingStation": {
                "vendorName": str(vendor),
                "model": str(model),
                "serialNumber": (serial_number != nil) ? str(serial_number) : "SN-STANCHION-001",
                "firmwareVersion": (firmware_ver != nil) ? str(firmware_ver) : "1.0.0"
            }
        }
    end

    # Build HeartbeatRequest payload
    static def heartbeat_req()
        return {}
    end

    # Build StatusNotificationRequest payload
    static def status_notification_req(timestamp_iso, connector_status, evse_id, connector_id)
        return {
            "timestamp": str(timestamp_iso),
            "connectorStatus": str(connector_status),
            "evseId": int(evse_id),
            "connectorId": int(connector_id)
        }
    end

    # Build AuthorizeRequest payload
    static def authorize_req(id_token_str, token_type)
        return {
            "idToken": {
                "idToken": str(id_token_str),
                "type": (token_type != nil) ? str(token_type) : "ISO14443" # RFID default
            }
        }
    end

    # Build TransactionEventRequest payload (Started, Updated, Ended)
    static def transaction_event_req(event_type, timestamp_iso, trigger_reason, seq_no, tx_id, evse_id, connector_id, id_token, meter_value_map)
        var payload = {
            "eventType": str(event_type), # "Started", "Updated", "Ended"
            "timestamp": str(timestamp_iso),
            "triggerReason": str(trigger_reason),
            "seqNo": int(seq_no),
            "transactionInfo": {
                "transactionId": str(tx_id)
            }
        }

        if evse_id != nil
            payload["evse"] = {
                "id": int(evse_id),
                "connectorId": (connector_id != nil) ? int(connector_id) : 1
            }
        end

        if id_token != nil
            payload["idToken"] = {
                "idToken": str(id_token),
                "type": "ISO14443"
            }
        end

        if meter_value_map != nil
            payload["meterValue"] = [meter_value_map]
        end

        return payload
    end

    # Build MeterValuesRequest payload
    static def meter_values_req(evse_id, meter_readings_list)
        return {
            "evseId": int(evse_id),
            "meterValue": (meter_readings_list != nil) ? meter_readings_list : []
        }
    end

    # Build SecurityEventNotificationRequest payload
    static def security_event_req(event_type, timestamp_iso, tech_info)
        return {
            "type": str(event_type),
            "timestamp": str(timestamp_iso),
            "techInfo": (tech_info != nil) ? str(tech_info) : "Security event triggered"
        }
    end

    # Build DataTransferRequest payload for custom vendor extensions
    static def data_transfer_req(vendor_id, message_id, data_str)
        return {
            "vendorId": str(vendor_id),
            "messageId": (message_id != nil) ? str(message_id) : "CustomTelemetry",
            "data": (data_str != nil) ? str(data_str) : ""
        }
    end
end

return OCPPMessages
