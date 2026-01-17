extends Node
## VoiceManager - High-quality proximity VOIP system
## Uses TwoVoIP for Opus encoding/decoding with proper stream handling
## Host forwards compressed packets only (no decode/mix)
##
## Wire Protocol: 12-byte header [stream_id:u32][epoch:u32][seq:u32] + opus_data
## Byte order: Big-endian (explicit via StreamPeerBuffer)

# ===== Configuration Constants =====

const VOICE_RANGE := 50.0
const VOICE_RANGE_LEAVE := 55.0         # Hysteresis: leave > enter
const MAX_VOICES_PER_LISTENER := 4      # Per-listener cap
const MAX_LISTENERS_PER_TALKER := 8     # Per-talker cap (protects host upload)
const STICKINESS_BONUS := 2.0           # Meters of "virtual closeness" for existing subscriptions
const PROXIMITY_UPDATE_INTERVAL := 0.1  # 10 Hz

# VAD Configuration (two-threshold hysteresis)
const VAD_START_THRESHOLD := 0.02       # Higher threshold to start speaking
const VAD_STOP_THRESHOLD := 0.015       # Lower threshold to stop (hysteresis)
const VAD_HANGOVER_SEC := 0.3           # Continue speaking for 300ms after energy drops

const OPUS_SAMPLE_RATE := 48000         # Opus internal rate (always 48k, TwoVoIP handles resampling)
const OPUS_FRAME_DURATION_MS := 20      # Frame duration in milliseconds
const OPUS_FRAME_SAMPLES := int(OPUS_SAMPLE_RATE * OPUS_FRAME_DURATION_MS / 1000)  # 960 samples for 20ms @ 48kHz

# Configurable voice settings (can be changed at runtime)
var opus_bitrate: int = 24000           # 24 kbps default (good voice quality)
var decoder_buffer_chunks: int = 10     # 200ms buffer (10 * 20ms frames)

# Wire protocol constants
const PREFIX_BYTES := 12                # stream_id(4) + epoch(4) + seq(4)
const HEADER_BIG_ENDIAN := true         # Explicit byte order for cross-platform compatibility

# Reorder buffer constants
const REORDER_WINDOW := 12              # ~240ms at 20ms frames
const STALL_TIMEOUT_MSEC := 100         # 100ms stall timeout (tune for your network)
const MAX_SEQ_JUMP := 1000              # Max allowed sequence jump before soft resync
const MAX_PACKET_AGE_MSEC := 300        # Drop packets older than 300ms

# ===== Signals =====

signal voice_started(peer_id: int)
signal voice_stopped(peer_id: int)

# ===== Private State =====

var _opus_effect: AudioEffectOpusChunked
var _mic_player: AudioStreamPlayer
var _voice_enabled: bool = false

# Encoder state
var _rng: RandomNumberGenerator = null  # For truly random stream_id
var _stream_id: int = 0                 # Unique per voice session (prevents restart soft-brick)
var _stream_epoch: int = 0              # Increments on each speech start (stream boundary)
var _sequence_number: int = 0           # Per-packet sequence within epoch
var _is_speaking: bool = false
var _last_speech_time: float = 0.0      # For VAD hangover (seconds)

# Playback state
var _voice_streams: Dictionary = {}     # peer_id -> AudioStreamOpusChunked
var _voice_players: Dictionary = {}     # peer_id -> AudioStreamPlayer3D

# Reorder buffer state (per sender)
var _last_stream_id: Dictionary = {}    # sender_id -> int
var _last_epoch: Dictionary = {}        # sender_id -> int
var _expected_seq: Dictionary = {}      # sender_id -> int
var _reorder_buffer: Dictionary = {}    # sender_id -> Dictionary(seq -> PackedByteArray)
var _packet_timestamps: Dictionary = {} # sender_id -> Dictionary(seq -> int msec)
var _stall_since_msec: Dictionary = {}  # sender_id -> int
var _missing_prev: Dictionary = {}      # sender_id -> bool (for FEC flag)

# Proximity state (host only)
var _listener_to_talkers: Dictionary = {}
var _talker_to_listeners: Dictionary = {}
var _proximity_timer: float = 0.0

# Loopback test
var _loopback_enabled: bool = false
var _loopback_stream: AudioStreamOpusChunked
var _loopback_player: AudioStreamPlayer
var _loopback_packets_sent: int = 0
var _loopback_queue: Array[PackedByteArray] = []

# Debug
var _debug_chunk_count: int = 0
var _debug_last_log: float = 0.0


# ===== Helper Functions =====

## Configure Opus stream with consistent frame/sample settings (encoder or decoder)
## Safely checks for property existence since TwoVoIP versions may differ
## For decoders, audiosamplerate MUST match Godot's output mix rate for correct playback speed
func _configure_opus_stream(stream: Object, is_decoder: bool = true) -> void:
	if stream == null:
		return
	
	# Opus internal rate (what the codec operates at)
	if stream.get("opussamplerate") != null:
		stream.opussamplerate = OPUS_SAMPLE_RATE
	
	if stream.get("opusframesize") != null:
		stream.opusframesize = OPUS_FRAME_SAMPLES  # 960 samples, NOT milliseconds!
	
	# For decoders: audiosamplerate MUST match Godot's output mix rate
	# This ensures playback consumes audio at the correct real-time rate
	var godot_mix_rate := int(AudioServer.get_mix_rate())
	if stream.get("audiosamplerate") != null:
		stream.audiosamplerate = godot_mix_rate
	
	# Calculate samples per frame at Godot's mix rate
	var samples_at_mix_rate := int(godot_mix_rate * OPUS_FRAME_DURATION_MS / 1000)
	if stream.get("audiosamplesize") != null:
		stream.audiosamplesize = samples_at_mix_rate
	
	# Set buffer size for decoders (more chunks = more latency tolerance but also more delay)
	# Default 50 chunks = 1 second buffer; we use less for lower latency
	if is_decoder and stream.get("audiosamplechunks") != null:
		stream.audiosamplechunks = decoder_buffer_chunks
	
	# Log configuration for debugging
	print("[VoiceManager] Configured stream: opussamplerate=%d, opusframesize=%d, audiosamplerate=%d, audiosamplesize=%d%s" % [
		OPUS_SAMPLE_RATE, OPUS_FRAME_SAMPLES, godot_mix_rate, samples_at_mix_rate,
		", audiosamplechunks=%d" % decoder_buffer_chunks if is_decoder else ""])


## Safe method call for GDExtension objects (Callable.is_valid() is the correct pattern)
static func _call_if_exists(obj: Object, method: StringName, args: Array = []) -> bool:
	var c := Callable(obj, method)
	if c.is_valid():
		c.callv(args)
		# DIAGNOSTIC: Uncomment to log all successful calls
		# print("[VoiceManager] ✓ Called %s successfully" % method)
		return true
	# DIAGNOSTIC: Log failed calls (method not available)
	print("[VoiceManager] ✗ Method %s not available on %s" % [method, obj.get_class()])
	return false


## Create 12-byte header with explicit big-endian encoding
static func _make_header(stream_id: int, epoch: int, seq: int) -> PackedByteArray:
	var spb := StreamPeerBuffer.new()
	spb.big_endian = HEADER_BIG_ENDIAN
	spb.put_u32(stream_id & 0xffffffff)
	spb.put_u32(epoch & 0xffffffff)
	spb.put_u32(seq & 0xffffffff)
	return spb.data_array


## Read u32 from packet at offset with explicit big-endian decoding
static func _read_u32(data: PackedByteArray, offset: int) -> int:
	var spb := StreamPeerBuffer.new()
	spb.big_endian = HEADER_BIG_ENDIAN
	spb.data_array = data
	spb.seek(offset)
	return spb.get_u32()


# ===== Initialization =====

func _ready() -> void:
	print("[VoiceManager] ===== SCRIPT VERSION: V8 (Full reorder buffer + stream_id) =====")
	
	# Initialize RNG once for stream_id generation
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	
	# Log audio configuration for debugging
	var output_rate = AudioServer.get_mix_rate()
	var input_rate = AudioServer.get_input_mix_rate()
	print("[VoiceManager] Output mix rate: %d Hz" % int(output_rate))
	print("[VoiceManager] Input mix rate: %d Hz" % int(input_rate))
	print("[VoiceManager] Output device: %s" % AudioServer.output_device)
	print("[VoiceManager] Input device: %s" % AudioServer.input_device)
	
	# Setup mic driver and opus encoder
	_setup_audio()


func _setup_audio() -> void:
	# Check if Mic bus exists
	var mic_bus_idx = AudioServer.get_bus_index("Mic")
	if mic_bus_idx == -1:
		push_error("[VoiceManager] Mic bus not found! Create a 'Mic' bus in Audio settings.")
		return
	
	# Setup mic driver node (required by TwoVoIP)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Mic"
	add_child(_mic_player)
	# Don't autoplay - we'll start it when voice is enabled
	
	# Get Godot's mix rate FIRST
	var godot_mix_rate = int(AudioServer.get_mix_rate())
	print("[VoiceManager] Configuring for mix_rate: %d Hz" % godot_mix_rate)
	print("[VoiceManager] Opus frame: %d samples (%dms @ %dHz)" % [OPUS_FRAME_SAMPLES, OPUS_FRAME_DURATION_MS, OPUS_SAMPLE_RATE])
	
	# Check if there's already an effect on the bus
	if AudioServer.get_bus_effect_count(mic_bus_idx) > 0:
		AudioServer.remove_bus_effect(mic_bus_idx, 0)
		print("[VoiceManager] Removed existing effect from Mic bus")
	
	# Create and configure BEFORE adding to bus
	var effect = AudioEffectOpusChunked.new()
	
	# Configure opus parameters - CRITICAL: opusframesize is SAMPLES, not milliseconds!
	effect.opussamplerate = OPUS_SAMPLE_RATE
	effect.opusbitrate = opus_bitrate
	effect.opusframesize = OPUS_FRAME_SAMPLES  # 960 samples for 20ms @ 48kHz (NOT "20"!)
	
	# Set audio sample rate/size to match
	# Note: audiosamplerate should match Godot's mix_rate for proper resampling
	if effect.get("audiosamplerate") != null:
		effect.audiosamplerate = godot_mix_rate
		print("[VoiceManager] Pre-configured audiosamplerate = %d" % godot_mix_rate)
	
	if effect.get("audiosamplesize") != null:
		effect.audiosamplesize = OPUS_FRAME_SAMPLES
		print("[VoiceManager] Pre-configured audiosamplesize = %d" % OPUS_FRAME_SAMPLES)
	
	# NOW add to bus
	AudioServer.add_bus_effect(mic_bus_idx, effect)
	print("[VoiceManager] Added pre-configured AudioEffectOpusChunked to Mic bus")
	
	_opus_effect = effect
	
	if _opus_effect == null:
		push_error("[VoiceManager] Failed to create AudioEffectOpusChunked!")
		return
	
	# Log available properties for debugging
	print("[VoiceManager] Opus effect properties:")
	for prop in _opus_effect.get_property_list():
		if prop.name.begins_with("opus") or prop.name.begins_with("audio"):
			print("  - %s = %s" % [prop.name, _opus_effect.get(prop.name)])
	
	# DIAGNOSTIC: Verify TwoVoIP methods are available
	print("[VoiceManager] === Checking TwoVoIP method availability ===")
	var flush_ok := Callable(_opus_effect, "flush_opus_encoder").is_valid()
	var undrop_ok := Callable(_opus_effect, "undrop_chunk").is_valid()
	var clear_ok := Callable(_opus_effect, "clear_opus_buffer").is_valid()
	print("  flush_opus_encoder: %s" % ("AVAILABLE" if flush_ok else "NOT FOUND"))
	print("  undrop_chunk: %s" % ("AVAILABLE" if undrop_ok else "NOT FOUND"))
	print("  clear_opus_buffer: %s" % ("AVAILABLE" if clear_ok else "NOT FOUND"))
	
	print("[VoiceManager] Audio setup complete")


func _process(delta: float) -> void:
	if _voice_enabled and _opus_effect != null:
		if _loopback_enabled:
			_process_minimal_loopback()
		else:
			_process_mic_input()
	
	# Host: update proximity subscriptions
	if NetworkManager.is_host:
		_proximity_timer += delta
		if _proximity_timer >= PROXIMITY_UPDATE_INTERVAL:
			_proximity_timer = 0.0
			_update_proximity_subscriptions()


# ===== Mic Input Processing (with VAD hysteresis) =====

func _process_mic_input() -> void:
	# SAFETY: This function should NEVER run when loopback is enabled
	# (loopback uses _process_minimal_loopback instead)
	if _loopback_enabled:
		push_error("[VoiceManager] BUG: _process_mic_input() called with loopback enabled!")
		return
	
	var had_speech := false
	var now_sec := Time.get_ticks_msec() / 1000.0
	
	# DIAGNOSTIC: Count chunks processed per frame (not lifetime counter)
	var chunks_this_frame := 0
	
	while _opus_effect.chunk_available():
		_debug_chunk_count += 1  # Lifetime counter
		chunks_this_frame += 1     # Per-frame counter
		
		# Real VAD: check energy level (args: denoise, postdenoise)
		var energy := _opus_effect.chunk_max(false, false)
		
		# Debug: log energy every second with both counters
		if now_sec - _debug_last_log > 1.0:
			_debug_last_log = now_sec
			print("[VoiceManager] Mic: chunks=%d (frame=%d), energy=%.4f (start=%.4f, stop=%.4f)" % [
				_debug_chunk_count, chunks_this_frame, energy, VAD_START_THRESHOLD, VAD_STOP_THRESHOLD])
		
		# Two-threshold VAD with hangover (affects actual dropping, not just events)
		var should_encode := false
		if not _is_speaking:
			# Not speaking: need to exceed START threshold
			should_encode = energy >= VAD_START_THRESHOLD
		else:
			# Currently speaking: stay speaking unless below STOP threshold AND outside hangover
			var in_hangover := (now_sec - _last_speech_time) < VAD_HANGOVER_SEC
			should_encode = energy >= VAD_STOP_THRESHOLD or in_hangover
		
		if not should_encode:
			_opus_effect.drop_chunk()
			continue
		
		# We have speech (or are in hangover)
		had_speech = true
		if energy >= VAD_STOP_THRESHOLD:
			_last_speech_time = now_sec  # Update only on real speech, not hangover
		
		if not _is_speaking:
			# Speech START boundary (gap just happened)
			_stream_epoch += 1
			_sequence_number = 0
			
			# Flush encoder state after gap (TwoVoIP recommends this)
			var flush_result := _call_if_exists(_opus_effect, "flush_opus_encoder")
			
			# TEMPORARILY DISABLED FOR TESTING: undrop_chunk may cause sequence warnings
			# Undrop to avoid clipping first syllable (TwoVoIP feature)
			# var undrop_result := _call_if_exists(_opus_effect, "undrop_chunk")
			var undrop_result := false  # Disabled for testing
			
			_is_speaking = true
			print("[VoiceManager] Speech started! Energy: %.4f, epoch: %d, flush: %s, undrop: %s (DISABLED)" % [
				energy, _stream_epoch, flush_result, undrop_result])
			voice_started.emit(multiplayer.get_unique_id())
		
		# Build header using stable encoding with stream_id
		var header := _make_header(_stream_id, _stream_epoch, _sequence_number)
		var opus_packet: PackedByteArray = _opus_effect.read_opus_packet(header)
		
		# CRITICAL: Must call drop_chunk() AFTER read_opus_packet() to advance the buffer!
		_opus_effect.drop_chunk()
		
		# Skip if no valid opus data (header only)
		if opus_packet.size() <= PREFIX_BYTES:
			continue
		
		# Send to network (loopback uses separate path via _process_minimal_loopback)
		NetworkManager.send_voice_packet(opus_packet)
		_sequence_number += 1
	
	# DIAGNOSTIC: Warn if chunks are accumulating (indicates backlog)
	if chunks_this_frame > 10:
		push_warning("[VoiceManager] Processing %d chunks in single frame - possible backlog!" % chunks_this_frame)
	
	# Mark silence when hangover expires
	if _is_speaking and not had_speech:
		var in_hangover := (now_sec - _last_speech_time) < VAD_HANGOVER_SEC
		if not in_hangover:
			_is_speaking = false
			
			# Flush encoder NOW (when stopping) to prepare for next speech
			# This is when the gap BEGINS, so flush according to TwoVoIP guidance
			var flush_result := _call_if_exists(_opus_effect, "flush_opus_encoder")
			print("[VoiceManager] Speech ended, flushed encoder: %s" % flush_result)
			
			voice_stopped.emit(multiplayer.get_unique_id())


# ===== MINIMAL LOOPBACK TEST (exact TwoVoIP README pattern) =====

var _empty_prepend := PackedByteArray()
var _loopback_last_queue_warning: int = 0
var _loopback_max_queue: int = 15  # Max ~300ms of buffered packets before dropping

func _process_minimal_loopback() -> void:
	# ENCODER: Always drain ALL available chunks (no VAD, no gating)
	while _opus_effect.chunk_available():
		var opus_data: PackedByteArray = _opus_effect.read_opus_packet(_empty_prepend)
		_opus_effect.drop_chunk()
		
		if opus_data.size() > 0:
			_loopback_queue.append(opus_data)
	
	# DECODER: Push only while space available
	if _loopback_stream != null:
		var pushed_this_frame := 0
		while _loopback_stream.chunk_space_available() and _loopback_queue.size() > 0:
			var packet = _loopback_queue.pop_front()
			
			# DIAGNOSTIC: Verify minimal loopback uses prefix=0 (log first few packets)
			if _loopback_packets_sent < 3:
				print("[VoiceManager] Minimal decode: prefix=0, size=%d" % packet.size())
			
			_loopback_stream.push_opus_packet(packet, 0, 0)  # NO prefix, NO fec
			_loopback_packets_sent += 1
			pushed_this_frame += 1
		
		# Drop old packets if queue grows too large (prevents unbounded latency)
		# This trades audio gaps for keeping latency bounded
		if _loopback_queue.size() > _loopback_max_queue:
			var drop_count := _loopback_queue.size() - _loopback_max_queue
			for i in drop_count:
				_loopback_queue.pop_front()
			print("[VoiceManager] Dropped %d packets to maintain latency bound" % drop_count)
		
		# Log periodically with queue health
		if _loopback_packets_sent > 0 and _loopback_packets_sent % 100 == 1:
			var queue_latency_ms := _loopback_queue.size() * OPUS_FRAME_DURATION_MS
			print("[VoiceManager] Loopback: %d packets, queue: %d (%dms latency)" % [
				_loopback_packets_sent, _loopback_queue.size(), queue_latency_ms])
		
		# Warn if queue is persistently high (indicates decoder not keeping up)
		var now_msec := Time.get_ticks_msec()
		if _loopback_queue.size() > 10 and (now_msec - _loopback_last_queue_warning) > 5000:
			_loopback_last_queue_warning = now_msec
			var latency_ms := _loopback_queue.size() * OPUS_FRAME_DURATION_MS
			push_warning("[VoiceManager] Persistent queue buildup: %d packets = %dms. Decoder may not be consuming fast enough." % [
				_loopback_queue.size(), latency_ms])


# ===== Voice Enable/Disable =====

func enable_voice() -> void:
	if _voice_enabled:
		return
	
	# Generate truly random stream ID for this session (prevents restart soft-brick)
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	_stream_id = int(_rng.randi())
	_stream_epoch = 0
	_sequence_number = 0
	_is_speaking = false
	_last_speech_time = 0.0
	
	_voice_enabled = true
	_debug_chunk_count = 0
	
	if _mic_player:
		_mic_player.play()
		# Check if it actually started
		await get_tree().create_timer(0.1).timeout
		if _mic_player.playing:
			print("[VoiceManager] Voice enabled - mic player is PLAYING, stream_id: %d" % _stream_id)
		else:
			push_error("[VoiceManager] Voice enabled but mic player FAILED to start!")
			print("[VoiceManager] Try selecting a different microphone in Settings > Audio")
	else:
		push_error("[VoiceManager] Voice enabled but _mic_player is null!")
	
	print("[VoiceManager] Current input device: %s" % AudioServer.input_device)


func disable_voice() -> void:
	if not _voice_enabled:
		return
	
	_voice_enabled = false
	if _mic_player:
		_mic_player.stop()
	
	# Reset speaking state
	_is_speaking = false
	
	# Disable loopback if active
	enable_loopback(false)
	
	print("[VoiceManager] Voice disabled")


func is_voice_enabled() -> bool:
	return _voice_enabled


# ===== Loopback Test Mode =====

func enable_loopback(enabled: bool) -> void:
	if enabled and not _loopback_enabled:
		# CRITICAL: Drain any accumulated chunks to start fresh
		print("[VoiceManager] Draining encoder buffer before loopback...")
		var drained_count := 0
		while _opus_effect.chunk_available():
			_opus_effect.drop_chunk()
			drained_count += 1
		print("[VoiceManager] Drained %d old chunks" % drained_count)
		
		# Flush encoder state if available
		var flush_result := _call_if_exists(_opus_effect, "flush_opus_encoder")
		print("[VoiceManager] Flush encoder: %s" % flush_result)
		
		# Create loopback player - using 2D AudioStreamPlayer (NOT 3D) to avoid attenuation issues
		_loopback_stream = AudioStreamOpusChunked.new()
		
		# Configure decoder with consistent frame/sample settings
		_configure_opus_stream(_loopback_stream)
		print("[VoiceManager] Decoder configured: %d samples (%dms @ %dHz)" % [OPUS_FRAME_SAMPLES, OPUS_FRAME_DURATION_MS, OPUS_SAMPLE_RATE])
		
		# Use 2D AudioStreamPlayer for loopback (no 3D attenuation/listener issues)
		_loopback_player = AudioStreamPlayer.new()
		_loopback_player.stream = _loopback_stream
		_loopback_player.bus = "Master"
		_loopback_player.volume_db = 0.0
		add_child(_loopback_player)
		_loopback_player.play()
		
		_loopback_enabled = true
		_loopback_packets_sent = 0
		_loopback_queue.clear()
		_loopback_last_queue_warning = 0
		
		# Diagnostics
		var master_bus_idx = AudioServer.get_bus_index("Master")
		var master_muted = AudioServer.is_bus_mute(master_bus_idx)
		var mix_rate = int(AudioServer.get_mix_rate())
		
		print("[VoiceManager] ========== LOOPBACK ENABLED ==========")
		print("[VoiceManager] Audio Configuration:")
		print("  - Godot mix_rate: %d Hz" % mix_rate)
		print("  - Opus: %d Hz, %d samples/frame (%dms)" % [OPUS_SAMPLE_RATE, OPUS_FRAME_SAMPLES, OPUS_FRAME_DURATION_MS])
		print("  - Bitrate: %d bps" % opus_bitrate)
		print("  - Decoder buffer: %d chunks (%dms)" % [decoder_buffer_chunks, decoder_buffer_chunks * OPUS_FRAME_DURATION_MS])
		print("[VoiceManager] Player: bus=%s, volume=%.1f dB" % [_loopback_player.bus, _loopback_player.volume_db])
		print("[VoiceManager] Master bus muted: %s" % master_muted)
		
		if master_muted:
			push_warning("[VoiceManager] Master bus is MUTED - you won't hear anything!")
		
		print("[VoiceManager] ==========================================")
		print("[VoiceManager] Speak into your mic - you should hear yourself...")
	
	elif not enabled and _loopback_enabled:
		if _loopback_player:
			_loopback_player.stop()
			_loopback_player.queue_free()
			_loopback_player = null
		_loopback_stream = null
		_loopback_enabled = false
		print("[VoiceManager] Loopback disabled")


func _play_loopback(opus_packet: PackedByteArray) -> void:
	if not _loopback_enabled or not _loopback_stream:
		return
	
	if opus_packet.size() <= PREFIX_BYTES:
		return
	
	if _loopback_stream.chunk_space_available():
		# Tell TwoVoIP to skip PREFIX_BYTES (our 12-byte header)
		_loopback_stream.push_opus_packet(opus_packet, PREFIX_BYTES, 0)
		_loopback_packets_sent += 1
		if _loopback_packets_sent == 1 or _loopback_packets_sent % 50 == 0:
			print("[VoiceManager] Loopback: sent %d packets" % _loopback_packets_sent)
	else:
		print("[VoiceManager] Loopback: buffer full, dropping")


func is_loopback_enabled() -> bool:
	return _loopback_enabled


## Get current loopback statistics for UI display
func get_loopback_stats() -> Dictionary:
	return {
		"enabled": _loopback_enabled,
		"packets_sent": _loopback_packets_sent,
		"queue_size": _loopback_queue.size(),
		"latency_ms": _loopback_queue.size() * OPUS_FRAME_DURATION_MS,
		"bitrate": opus_bitrate,
		"buffer_chunks": decoder_buffer_chunks,
	}


## Set opus bitrate (takes effect on next encoder setup)
func set_bitrate(bitrate: int) -> void:
	opus_bitrate = clampi(bitrate, 6000, 128000)
	# Apply immediately to encoder if active
	if _opus_effect != null and _opus_effect.get("opusbitrate") != null:
		_opus_effect.opusbitrate = opus_bitrate
		print("[VoiceManager] Bitrate changed to: %d bps" % opus_bitrate)


## Set decoder buffer size in chunks (20ms each)
func set_buffer_chunks(chunks: int) -> void:
	decoder_buffer_chunks = clampi(chunks, 3, 50)
	print("[VoiceManager] Buffer size changed to: %d chunks (%dms)" % [decoder_buffer_chunks, decoder_buffer_chunks * OPUS_FRAME_DURATION_MS])


## Get available bitrate presets
func get_bitrate_presets() -> Array[Dictionary]:
	return [
		{"name": "Low (12 kbps)", "value": 12000},
		{"name": "Medium (24 kbps)", "value": 24000},
		{"name": "High (48 kbps)", "value": 48000},
		{"name": "Very High (96 kbps)", "value": 96000},
	]


## Diagnostic: Check if basic audio playback works
func test_audio_playback() -> void:
	print("[VoiceManager] === AUDIO DIAGNOSTIC TEST ===")
	
	var master_idx = AudioServer.get_bus_index("Master")
	var mic_idx = AudioServer.get_bus_index("Mic")
	print("  Output device: %s" % AudioServer.output_device)
	print("  Mix rate: %d Hz" % int(AudioServer.get_mix_rate()))
	print("  Master bus: muted=%s, volume=%.1f dB" % [AudioServer.is_bus_mute(master_idx), AudioServer.get_bus_volume_db(master_idx)])
	print("  Mic bus: muted=%s, volume=%.1f dB" % [AudioServer.is_bus_mute(mic_idx), AudioServer.get_bus_volume_db(mic_idx)])
	
	if _loopback_enabled and _loopback_player:
		print("  Loopback player: playing=%s, bus=%s, volume=%.1f dB" % [
			_loopback_player.playing,
			_loopback_player.bus,
			_loopback_player.volume_db
		])
	else:
		print("  Loopback: NOT enabled")
	
	print("[VoiceManager] === END DIAGNOSTIC ===")


# ===== Proximity System (Host Only) =====

func _update_proximity_subscriptions() -> void:
	var player_nodes = NetworkManager._player_nodes
	if player_nodes.is_empty():
		return
	
	# Reset talker->listeners (will rebuild)
	_talker_to_listeners.clear()
	for player_id in player_nodes:
		_talker_to_listeners[player_id] = []
	
	# Build listener->talkers with per-listener cap
	for listener_id in player_nodes:
		var listener_node = player_nodes[listener_id]
		if listener_node == null or not is_instance_valid(listener_node):
			continue
		
		var listener_pos = listener_node.global_position
		var candidates: Array = []
		var current_subs = _listener_to_talkers.get(listener_id, [])
		
		for talker_id in player_nodes:
			if talker_id == listener_id:
				continue
			
			var talker_node = player_nodes[talker_id]
			if talker_node == null or not is_instance_valid(talker_node):
				continue
			
			var talker_pos = talker_node.global_position
			var dist = listener_pos.distance_to(talker_pos)
			
			# Hysteresis: wider threshold for existing subscriptions
			var was_subscribed = current_subs.has(talker_id)
			var threshold = VOICE_RANGE_LEAVE if was_subscribed else VOICE_RANGE
			
			if dist < threshold:
				var effective_dist = dist
				if was_subscribed:
					effective_dist = max(0.0, dist - STICKINESS_BONUS)
				
				candidates.append({
					"id": talker_id,
					"dist": dist,
					"effective_dist": effective_dist
				})
		
		# Sort by effective distance, then peer_id for determinism
		candidates.sort_custom(func(a, b):
			if abs(a["effective_dist"] - b["effective_dist"]) < 0.5:
				return a["id"] < b["id"]
			return a["effective_dist"] < b["effective_dist"]
		)
		
		var subscribed: Array = []
		for i in min(candidates.size(), MAX_VOICES_PER_LISTENER):
			var talker_id = candidates[i]["id"]
			
			if _talker_to_listeners[talker_id].size() < MAX_LISTENERS_PER_TALKER:
				subscribed.append(talker_id)
				_talker_to_listeners[talker_id].append(listener_id)
		
		_listener_to_talkers[listener_id] = subscribed


func get_listeners_for(talker_id: int) -> Array:
	return _talker_to_listeners.get(talker_id, [])


# ===== Voice Playback =====

func setup_voice_playback_for(peer_id: int, player_node: Node3D) -> void:
	if _voice_streams.has(peer_id):
		return  # Already setup
	
	var stream = AudioStreamOpusChunked.new()
	
	# Configure decoder with consistent frame/sample settings
	_configure_opus_stream(stream)
	
	var player3d = AudioStreamPlayer3D.new()
	player3d.stream = stream
	player3d.bus = "Master"
	player3d.max_distance = VOICE_RANGE
	player3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player3d.volume_db = 0.0
	player3d.name = "VoicePlayer_%d" % peer_id
	player_node.add_child(player3d)
	player3d.play()
	
	_voice_streams[peer_id] = stream
	_voice_players[peer_id] = player3d
	
	# Initialize reorder buffer state for this sender
	# Note: We don't initialize _expected_seq here - it will be set on first packet
	_reorder_buffer[peer_id] = {}
	_packet_timestamps[peer_id] = {}
	_stall_since_msec[peer_id] = 0
	_missing_prev[peer_id] = false
	
	print("[VoiceManager] Setup voice playback for peer %d (%d samples @ %dHz)" % [peer_id, OPUS_FRAME_SAMPLES, OPUS_SAMPLE_RATE])


func receive_voice_packet(sender_id: int, data: PackedByteArray) -> void:
	if not _voice_streams.has(sender_id):
		return
	if data.size() < PREFIX_BYTES:
		return
	
	# Parse 12-byte header with explicit big-endian decoding
	var stream_id := _read_u32(data, 0)
	var epoch := _read_u32(data, 4)
	var seq := _read_u32(data, 8)
	
	# Check for new stream session (client restart/reconnect)
	var last_stream_id: int = _last_stream_id.get(sender_id, -1)
	if stream_id != last_stream_id:
		# New stream session - hard reset everything
		_last_stream_id[sender_id] = stream_id
		_last_epoch[sender_id] = epoch
		_reset_decoder_for(sender_id)
		print("[VoiceManager] New stream session for peer %d (stream_id: %d)" % [sender_id, stream_id])
	else:
		# Same stream session - check epoch
		var last_epoch: int = _last_epoch.get(sender_id, -1)
		if epoch < last_epoch:
			# Late packet from old epoch within same session - drop it
			return
		elif epoch > last_epoch:
			# New epoch within same session - soft reset decoder state
			_last_epoch[sender_id] = epoch
			_reset_decoder_for(sender_id)
	
	# Add to reorder buffer and drain in order
	_store_and_drain_ordered(sender_id, seq, data)


func _reset_decoder_for(sender_id: int) -> void:
	var stream: Object = _voice_streams.get(sender_id, null)
	var player: AudioStreamPlayer3D = _voice_players.get(sender_id, null)
	if stream == null:
		return
	
	# Try TwoVoIP's reset method first (if available)
	var cleared := _call_if_exists(stream, "clear_opus_buffer")
	
	# WORKAROUND: If clear_opus_buffer() not available, hard-reset by recreating stream
	# This is crude but effective when the API method doesn't exist
	if not cleared and player != null:
		var was_playing := player.playing
		player.stop()
		
		var new_stream := AudioStreamOpusChunked.new()
		_configure_opus_stream(new_stream)
		player.stream = new_stream
		_voice_streams[sender_id] = new_stream
		
		if was_playing:
			player.play()
	
	# Reset sequence tracking (don't set to 0 - let first packet initialize)
	_expected_seq.erase(sender_id)
	_reorder_buffer[sender_id] = {}
	_packet_timestamps[sender_id] = {}
	_stall_since_msec[sender_id] = 0
	_missing_prev[sender_id] = false


func _store_and_drain_ordered(sender_id: int, seq: int, packet: PackedByteArray) -> void:
	var stream: Object = _voice_streams[sender_id]
	var now_msec := Time.get_ticks_msec()
	
	# Initialize buffer if needed
	if not _reorder_buffer.has(sender_id):
		_reorder_buffer[sender_id] = {}
	if not _packet_timestamps.has(sender_id):
		_packet_timestamps[sender_id] = {}
	if not _expected_seq.has(sender_id):
		# First packet for this stream - initialize expected to this seq
		_expected_seq[sender_id] = seq
		_stall_since_msec[sender_id] = 0
		_missing_prev[sender_id] = false
	
	var buffer: Dictionary = _reorder_buffer[sender_id]
	var timestamps: Dictionary = _packet_timestamps[sender_id]
	var expected: int = _expected_seq[sender_id]
	
	# Drop late packets (already passed expected) to preserve monotonic decode
	if seq < expected:
		return
	
	# Guard against malicious/corrupted packets with huge sequence jumps
	if seq > expected + MAX_SEQ_JUMP:
		# Huge jump - treat as soft resync (recovers from legitimate desync)
		buffer.clear()
		timestamps.clear()
		_missing_prev[sender_id] = true  # Mark loss for FEC
		expected = seq
		_stall_since_msec[sender_id] = 0
		# Fall through to store this packet
	
	# Check for duplicate packets (cheap protection)
	if buffer.has(seq):
		return  # Ignore duplicate
	
	# Store packet with timestamp for age tracking
	buffer[seq] = packet
	timestamps[seq] = now_msec
	
	# If we're missing 'expected' but have newer packets, check stall timeout
	if not buffer.has(expected) and buffer.size() > 0:
		if _stall_since_msec[sender_id] == 0:
			_stall_since_msec[sender_id] = now_msec
		
		var keys := buffer.keys()
		keys.sort()
		var min_seq: int = int(keys[0])
		
		var stall_time: int = _stall_since_msec[sender_id]
		var stalled: bool = (now_msec - stall_time) >= STALL_TIMEOUT_MSEC
		var overflow: bool = buffer.size() > REORDER_WINDOW
		
		# Give up waiting: declare loss and skip to next available
		if (min_seq > expected) and (stalled or overflow):
			_missing_prev[sender_id] = true
			expected = min_seq
			_stall_since_msec[sender_id] = 0
	
	# Too-late policy: drop packets older than max age (pairs well with UnreliableNoDelay)
	var keys_to_drop: Array = []
	for pkt_seq in buffer.keys():
		var pkt_time: int = timestamps.get(pkt_seq, now_msec)
		var age_msec: int = now_msec - pkt_time
		if age_msec > MAX_PACKET_AGE_MSEC:
			keys_to_drop.append(pkt_seq)
	for pkt_seq in keys_to_drop:
		buffer.erase(pkt_seq)
		timestamps.erase(pkt_seq)
		if pkt_seq == expected:
			# Too-late packet was the one we were waiting for - mark as loss
			_missing_prev[sender_id] = true
			expected += 1
	
	# Drain in-order
	while buffer.has(expected) and stream.chunk_space_available():
		var pkt: PackedByteArray = buffer[expected]
		buffer.erase(expected)
		timestamps.erase(expected)
		
		# TwoVoIP: fec can be set to 1 if previous packet is missing
		var fec := 1 if _missing_prev.get(sender_id, false) else 0
		_missing_prev[sender_id] = false
		
		# DIAGNOSTIC: Log decode parameters (only log first few packets per sender to avoid spam)
		if expected < 3:
			var has_header := pkt.size() >= PREFIX_BYTES
			print("[VoiceManager] Decode peer %d: prefix=%d, size=%d, has_header=%s, fec=%d" % [
				sender_id, PREFIX_BYTES, pkt.size(), has_header, fec])
		
		stream.push_opus_packet(pkt, PREFIX_BYTES, fec)
		expected += 1
	
	# Stall timer maintenance
	if not buffer.has(expected):
		_stall_since_msec[sender_id] = 0
	
	_expected_seq[sender_id] = expected


func cleanup_voice_playback_for(peer_id: int) -> void:
	if _voice_players.has(peer_id):
		_voice_players[peer_id].queue_free()
		_voice_players.erase(peer_id)
	_voice_streams.erase(peer_id)
	
	# Clean up ALL reorder buffer tracking to prevent leaks
	_last_stream_id.erase(peer_id)
	_last_epoch.erase(peer_id)
	_expected_seq.erase(peer_id)
	_reorder_buffer.erase(peer_id)
	_packet_timestamps.erase(peer_id)
	_stall_since_msec.erase(peer_id)
	_missing_prev.erase(peer_id)
	
	# Clean up proximity data
	_listener_to_talkers.erase(peer_id)
	_talker_to_listeners.erase(peer_id)
	
	print("[VoiceManager] Cleaned up voice playback for peer %d" % peer_id)


# ===== Cleanup =====

func cleanup_all() -> void:
	disable_voice()
	
	for peer_id in _voice_players.keys():
		cleanup_voice_playback_for(peer_id)
	
	_listener_to_talkers.clear()
	_talker_to_listeners.clear()
