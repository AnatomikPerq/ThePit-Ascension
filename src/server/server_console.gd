class_name ServerConsole
extends RefCounted
## The keyboard on the box the server is running on.
##
## Godot has no non-blocking read of standard input — `OS.read_string_from_stdin`
## waits for a line — so the read lives on its own thread and hands finished
## lines to the main thread through a mutex. Doing it in `_process` instead would
## freeze every room on the server between keystrokes, which is not a trade
## anybody would take for the convenience of one fewer thread.
##
## **On shutdown the reader is not joined**, and that is deliberate rather than
## an oversight. The thread is parked inside a blocking read; `wait_to_finish()`
## would not return until stdin produced another line, so a server told to stop
## would sit there until somebody pressed Enter — and a server stopped by a
## service manager, with nobody at the keyboard, would never exit at all. The
## thread owns nothing but a queue, the process is on its way out, and the
## operating system reclaims both.
##
## Three front-ends run the same commands: this, the remote console, and the
## admin panel inside the game. They differ only in who is asking and how the
## answer is delivered — see CommandRegistry.

## Emitted on the MAIN thread, once per line, in the order they were typed.
signal line_received(text: String)

## Standard input is read a line at a time; this is only the ceiling on how long
## one line may be before it is cut. Nothing legitimate is close to it.
const READ_BUFFER: int = 4096

var available: bool = false

var _thread: Thread
var _mutex: Mutex = Mutex.new()
var _pending: PackedStringArray = PackedStringArray()
## Read by the reader thread, written by the main thread. A plain bool is enough:
## the worst race is one extra loop before the thread notices it should stop, and
## it is about to be abandoned anyway.
var _running: bool = false


## Returns false when there is nothing to read — a server started by a launcher
## that gave it no console, which is normal and not an error. The remote console
## and the in-game panel still work in that case, so the server is not mute.
func start() -> bool:
	var kind := OS.get_stdin_type()
	if kind == OS.STD_HANDLE_INVALID or kind == OS.STD_HANDLE_UNKNOWN:
		available = false
		return false
	_running = true
	_thread = Thread.new()
	var err := _thread.start(_read_loop, Thread.PRIORITY_LOW)
	available = err == OK
	if not available:
		_thread = null
		_running = false
	return available


func stop() -> void:
	_running = false
	_reap()


## Join the reader IF it has already finished — which it has whenever stdin
## reached end of input, the common case for a server started by a service
## manager or with its input redirected. Godot complains about a Thread object
## destroyed without `wait_to_finish()`, and this quietly satisfies it in every
## case where satisfying it does not mean blocking forever. The case it cannot
## help with — a reader parked in a blocking read on a live terminal — is the one
## the class comment explains.
func _reap() -> void:
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		available = false


## Called every frame from the server's main loop. Everything crossing the
## thread boundary crosses here, and nothing else touches `_pending`.
func poll() -> void:
	if not available:
		return
	var lines := PackedStringArray()
	_mutex.lock()
	if not _pending.is_empty():
		lines = _pending.duplicate()
		_pending.clear()
	_mutex.unlock()
	for line in lines:
		line_received.emit(line)
	_reap()


## `OS.read_string_from_stdin(n)` reads up to n BYTES, not one line, and that
## distinction is not academic: from a terminal it usually returns exactly the
## line you typed, but from a pipe or a file it returns as much as it can and the
## naive version treats a whole script of commands as one command. So the lines
## are cut here, and a partial one is carried to the next read.
func _read_loop() -> void:
	var buffer := ""
	while _running:
		# Blocks here for as long as nobody types. That is the whole reason this
		# is a thread.
		var chunk := OS.read_string_from_stdin(READ_BUFFER)
		if chunk == "":
			# End of input: the terminal was closed, or stdin was a file that ran
			# out. Anything typed without a closing newline still counts.
			_push(buffer)
			break
		buffer += chunk
		var split := buffer.find("\n")
		while split >= 0:
			_push(buffer.substr(0, split))
			buffer = buffer.substr(split + 1)
			split = buffer.find("\n")
		if buffer.length() > READ_BUFFER:
			# A sender with no newline in it. Not a console operator.
			buffer = ""


func _push(line: String) -> void:
	var clean := line.strip_edges()
	if clean == "":
		return
	_mutex.lock()
	_pending.append(clean)
	_mutex.unlock()


## Split a command line into words, honouring double quotes so that a reason, a
## message of the day or a room name can contain spaces.
##
## Deliberately not a full shell: no escapes, no single quotes, no variables. An
## operator typing `ban somebody "being unpleasant in room 2"` is the whole
## requirement, and every feature past that is a way to be surprised.
static func split(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var quoted := false
	var has_current := false
	for i in line.length():
		var ch := line[i]
		if ch == '"':
			quoted = not quoted
			has_current = true
			continue
		if ch == " " and not quoted:
			if has_current:
				out.append(current)
				current = ""
				has_current = false
			continue
		current += ch
		has_current = true
	if has_current:
		out.append(current)
	return out
