@tool
class_name ProtocolStamp
extends Resource
## The fingerprint of one build of the game, as a resource so it survives export.
##
## A dedicated server and a client are two builds of THIS repository. They agree
## about the pit only because they were built from the same tree: the world is a
## pure function of the seed, avatars are `CharacterDef`s resolved by id, and a
## blast names the pieces it broke. Every one of those agreements breaks
## silently when a server is left running across a game update — the client
## rebuilds a different pit from the same seed, or asks for a character the
## server has never heard of, and what the player sees is "the game is desynced",
## with nothing anywhere saying why.
##
## So the two sides state their build to each other before the first packet of
## gameplay, and a mismatch is refused with a sentence naming which side is
## stale. `content_hash` is what they compare.
##
## Written by `tools/build_protocol_stamp.gd`, which is a one-shot generator like
## the others in that folder — it digests every file the simulation is a function
## of. Do not hand-edit it; regenerate it. `tools/run_tests.sh` regenerates it on
## every run and says out loud when it moved, because a commit that moves this
## number is a commit that obliges you to redeploy the server.

## Hex SHA-256 over the declared source set. The only field anyone compares.
@export var content_hash: String = ""
## How many files went into it, and when. Both are for the human reading a log
## line that says two builds disagree — neither is compared.
@export var file_count: int = 0
@export var generated_at: String = ""
## The globs the generator walked, recorded so a reader of this file can tell
## what "the game changed" is defined to mean without opening the generator.
@export var sources: PackedStringArray = PackedStringArray()
