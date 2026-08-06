class_name NetCrypto
extends Object
## The small amount of cryptography a dedicated server needs, in one place.
##
## Nothing here is invented. PBKDF2-HMAC-SHA256 is RFC 8018, and every primitive
## under it is an engine call (`Crypto.hmac_digest`, `Crypto.generate_random_bytes`,
## `Crypto.constant_time_compare`) — this file is the standard construction
## around them and nothing more. It exists so that "how is a password stored"
## has exactly one answer that can be read in a minute.
##
## What it buys, and what it does not:
##
## - A stolen `accounts.json` does not hand over anybody's password. Each account
##   has its own 16-byte salt, so one rainbow table cannot serve two accounts,
##   and the iteration count makes a guess expensive.
## - A password is never sent over the wire, not even once. The server sends the
##   salt and a per-connection nonce; the client answers with
##   `HMAC(PBKDF2(password, salt), nonce)`. A captured answer is worthless on the
##   next connection.
## - The **one** exception is registration, which has to send the derived key so
##   the server has something to verify against later. That is a real weakness
##   on an open network and it is why `security/encryption` exists and why
##   `account register` on the console is offered as the out-of-band route. It is
##   spelled out in docs/SERVER.md rather than hidden here.

## SHA-256 output size, which is also the derived-key and proof size.
const DIGEST_BYTES: int = 32
## Per-account salt. 16 bytes is the usual floor and there is no reason to skimp.
const SALT_BYTES: int = 16
## The nonce the server challenges each connection with. Only has to be unique
## per connection, never reused, and unguessable.
const NONCE_BYTES: int = 24

## Chosen against the measurement in test/server_crypto_test.gd rather than by
## copying a number out of a blog post: the whole point of an iteration count is
## that it costs the attacker, so it has to be the largest one the server can
## absorb. See ServerSettings for the tunable and docs/SERVER.md for how to
## raise it as machines get faster.
const DEFAULT_ITERATIONS: int = 24000
## A floor, so that a badly-set config cannot quietly turn hashing off.
const MIN_ITERATIONS: int = 1000


static func random_bytes(count: int) -> PackedByteArray:
	return Crypto.new().generate_random_bytes(count)


static func hmac_sha256(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, message)


## Constant-time equality. Never compare a proof or a token with `==`: a byte
## array comparison that returns early leaks, over enough attempts, how much of a
## guess was right.
static func equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	return Crypto.new().constant_time_compare(a, b)


## PBKDF2-HMAC-SHA256, one output block (32 bytes), which is all we ever want.
##
## Deliberately not generalised to longer outputs: a second block would double
## the cost for a key nothing needs, and the loop below is the part that has to
## be obviously correct.
static func derive_key(password: String, salt: PackedByteArray,
		iterations: int) -> PackedByteArray:
	var iters := maxi(iterations, MIN_ITERATIONS)
	var secret := password.to_utf8_buffer()
	# U1 = HMAC(P, S || INT32_BE(1)). One block, so the counter is always 1.
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := hmac_sha256(secret, block)
	var out := u.duplicate()
	for _i in iters - 1:
		u = hmac_sha256(secret, u)
		# out ^= u
		for b in DIGEST_BYTES:
			out[b] = out[b] ^ u[b]
	return out


## What the client answers a challenge with. The server holds `key` (as the
## account's verifier) and can compute the same thing without ever seeing the
## password.
static func proof(key: PackedByteArray, nonce: PackedByteArray) -> PackedByteArray:
	return hmac_sha256(key, nonce)


static func new_salt() -> PackedByteArray:
	return random_bytes(SALT_BYTES)


static func new_nonce() -> PackedByteArray:
	return random_bytes(NONCE_BYTES)


## A token for reconnects and for RCON. Hex, so it survives a config file, a
## terminal and a copy-paste without an encoding argument.
static func new_token(bytes: int = 24) -> String:
	return random_bytes(bytes).hex_encode()


## The salt to answer a login for an account that does not exist.
##
## Without this, "unknown account" and "wrong password" are distinguishable by
## whether a salt comes back at all, and a stranger can enumerate who plays here
## by trying names. Deriving a stable fake salt from the server's own secret
## makes an unknown name look exactly like a known one — same shape, same
## timing, same failure one step later.
static func decoy_salt(server_secret: PackedByteArray, account_name: String) -> PackedByteArray:
	return hmac_sha256(server_secret, account_name.to_utf8_buffer()).slice(0, SALT_BYTES)


## SHA-256 of arbitrary bytes, hex encoded. Used for fingerprints, not secrets.
static func sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()
