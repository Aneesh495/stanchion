# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Asynchronous Publish-Subscribe Event Bus & Priority Event Dispatcher
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import collection as Col
import time_util as TimeUtil

var RingBuffer = Col["RingBuffer"]

class Event
    var topic
    var payload
    var timestamp
    var source

    def init(topic, payload, source)
        self.topic = str(topic)
        self.payload = (payload != nil) ? payload : {}
        self.source = (source != nil) ? str(source) : "system"
        self.timestamp = TimeUtil.to_iso8601(TimeUtil.to_epoch_seconds(2026, 1, 1, 0, 0, 0))
    end

    def to_map()
        return {
            "topic": self.topic,
            "payload": self.payload,
            "source": self.source,
            "timestamp": self.timestamp
        }
    end
end

class Subscription
    var sub_id
    var topic_pattern
    var callback
    var priority
    var is_active

    def init(sub_id, topic_pattern, callback, priority)
        self.sub_id = int(sub_id)
        self.topic_pattern = str(topic_pattern)
        self.callback = callback
        self.priority = (priority != nil) ? int(priority) : 100
        self.is_active = true
    end

    def matches(topic)
        if self.topic_pattern == "*" || self.topic_pattern == topic
            return true
        end
        # Prefix wildcard match (e.g. "meter.*")
        if string.endswith(self.topic_pattern, ".*")
            var prefix = string.split(self.topic_pattern, ".*")[0]
            return string.startswith(topic, prefix)
        end
        return false
    end
end

class EventBus
    var subscriptions
    var next_sub_id
    var history
    var is_paused

    def init(history_capacity)
        var cap = (history_capacity != nil) ? int(history_capacity) : 128
        self.subscriptions = []
        self.next_sub_id = 1
        self.history = RingBuffer(cap)
        self.is_paused = false
    end

    # Subscribe a callback function to a topic pattern with an execution priority
    # Higher priority numbers execute first
    def subscribe(topic_pattern, callback, priority)
        var sub = Subscription(self.next_sub_id, topic_pattern, callback, priority)
        self.next_sub_id = self.next_sub_id + 1
        self.subscriptions.push(sub)

        # Sort subscriptions by priority descending
        self._sort_subscriptions()
        return sub.sub_id
    end

    # Unsubscribe by subscription identifier
    def unsubscribe(sub_id)
        sub_id = int(sub_id)
        for i : 0 .. (self.subscriptions.size() - 1)
            if self.subscriptions[i].sub_id == sub_id
                self.subscriptions[i].is_active = false
                self.subscriptions.remove(i)
                return true
            end
        end
        return false
    end

    # Publish an event to all matching active subscribers
    def publish(topic, payload, source)
        var ev = Event(topic, payload, source)
        self.history.push(ev)

        if self.is_paused
            return 0
        end

        var dispatched_count = 0
        var subs = self.subscriptions
        var n = subs.size()

        for i : 0 .. (n - 1)
            var sub = subs[i]
            if sub.is_active && sub.matches(topic)
                try
                    sub.callback(ev)
                    dispatched_count = dispatched_count + 1
                except .. as err
                    # Log error without aborting other event listeners
                    print("[EventBus Error] Exception in listener " + str(sub.sub_id) + ": " + str(err))
                end
            end
        end
        return dispatched_count
    end

    # Pause event dispatching
    def pause()
        self.is_paused = true
    end

    # Resume event dispatching
    def resume()
        self.is_paused = false
    end

    # Return total active subscriber count
    def subscriber_count()
        return self.subscriptions.size()
    end

    # Return recent event history
    def get_history()
        return self.history.to_list()
    end

    def clear()
        self.subscriptions = []
        self.history.clear()
    end

    def _sort_subscriptions()
        var n = self.subscriptions.size()
        for i : 0 .. (n - 2)
            for j : 0 .. (n - 2 - i)
                if self.subscriptions[j].priority < self.subscriptions[j + 1].priority
                    var temp = self.subscriptions[j]
                    self.subscriptions[j] = self.subscriptions[j + 1]
                    self.subscriptions[j + 1] = temp
                end
            end
        end
    end
end

return EventBus
