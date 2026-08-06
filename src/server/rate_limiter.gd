class_name RateLimiter
extends RefCounted
## Token buckets, keyed by whatever the caller is limiting — a peer id, an
## address, an account name.
##
## A bucket refills at `rate` per second up to `burst`, and every request costs
## one token. That shape rather than "N per window" because a window resets, and
## a resetting window lets somebody send their whole allowance in the last
## millisecond of one window and again in the first of the next. A bucket has no
## such edge.
##
## Used for four different things, which is the reason it is its own file: the
## number of messages a peer may send, how often an address may attempt to
## connect, how often a login may be tried, and how fast anyone may talk in chat.

## key -> [tokens, last_refill_seconds]
var _buckets: Dictionary[String, Array] = {}

var rate: float = 1.0
var burst: float = 1.0


static func make(per_second: float, burst_size: float) -> RateLimiter:
	var limiter := RateLimiter.new()
	limiter.rate = maxf(per_second, 0.0001)
	limiter.burst = maxf(burst_size, 1.0)
	return limiter


func configure(per_second: float, burst_size: float) -> void:
	rate = maxf(per_second, 0.0001)
	burst = maxf(burst_size, 1.0)


## Take one token if there is one. False means "refuse this", not "wait" — the
## callers are all packet handlers, and a packet held is a packet that arrives
## out of order later.
func allow(key: String, cost: float = 1.0) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var bucket: Array = _buckets.get(key, [burst, now])
	var refilled: float = minf(burst, float(bucket[0]) + (now - float(bucket[1])) * rate)
	if refilled < cost:
		_buckets[key] = [refilled, now]
		return false
	_buckets[key] = [refilled - cost, now]
	return true


## How much allowance is left, for a status line or a log message about somebody
## who is being throttled.
func remaining(key: String) -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var bucket: Array = _buckets.get(key, [burst, now])
	return minf(burst, float(bucket[0]) + (now - float(bucket[1])) * rate)


## Called when a peer disconnects. Without it the table grows for the lifetime
## of the process, one entry per address that ever touched the port — which is
## exactly the thing an attacker would be feeding.
func forget(key: String) -> void:
	_buckets.erase(key)


## Drop buckets that have been full for a while: nothing is being limited about
## them, so remembering them is pure cost. Called on the server's slow tick.
func prune() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var stale: Array[String] = []
	for key in _buckets:
		var bucket: Array = _buckets[key]
		if minf(burst, float(bucket[0]) + (now - float(bucket[1])) * rate) >= burst:
			stale.append(key)
	for key in stale:
		_buckets.erase(key)


func tracked() -> int:
	return _buckets.size()
