extends Node

# Pro Voice Chat mit Opus + RNNoise via TwoVoip

# Voice settings
var voice_range := 20.0  # Proximity range in meters
var voice_volume := 1.0
var noise_gate_db := -60.0  # For UI compatibility (not used with Opus+RNNoise)
var mic_gain := 1.0  # For UI compatibility

# Audio settings
const SAMPLE_RATE = 48000  # VoIP standard
var frame_size_ms := 20  # Frame size in ms (adjustable for quality)
var opus_bitrate := 20000  # 20 kbps default
var opus_complexity := 6  # 5-7 recommended
var rnnoise_enabled := true

var recording := false
var voice_players := {}  # peer_id -> AudioStreamPlayer3D

# TwoVoip check
var twovoip_available := false
var opus_encoder = null
var opus_decoder = null

# Jitter buffer per peer
var jitter_buffers := {}  # peer_id -> JitterBuffer

# Performance
var _frame_counter := 0
var _distance_check_counter := 0
var _distance_check_interval := 10
var _cached_nearby_peers := []

# Audio capture
var audio_effect: AudioEffectCapture
var audio_bus_idx := -1

# Signals (for compatibility)
# signal voice_packet_received(peer_id: int, audio_data: PackedByteArray)  # Unused but kept for compatibility

class JitterBuffer:
	var packets := []
	var sequence_number := 0
	var target_delay_ms := 80  # 60-80ms recommended
	
	func add_packet(seq: int, data: PackedByteArray):
		packets.append({"seq": seq, "data": data, "time": Time.get_ticks_msec()})
		packets.sort_custom(func(a, b): return a.seq < b.seq)
		
		# Remove old packets
		var current_time = Time.get_ticks_msec()
		packets = packets.filter(func(p): return current_time - p.time < 500)
	
	func get_next_packet() -> PackedByteArray:
		if packets.is_empty():
			return PackedByteArray()
		
		# Wait for target delay before playing
		var oldest = packets[0]
		if Time.get_ticks_msec() - oldest.time >= target_delay_ms:
			var packet = packets.pop_front()
			return packet.data
		
		return PackedByteArray()

func _ready():
	# Check TwoVoip availability
	twovoip_available = _check_twovoip()
	
	if not twovoip_available:
		push_warning("TwoVoip not found! Please install from Asset Library for best quality.")
		push_warning("Falling back to basic voice chat.")
	else:
		print("TwoVoip detected - Opus + RNNoise enabled!")
		_init_opus()
	
	# Setup audio bus
	_setup_audio_bus()
	
	print("VoiceChatOpus initialized (48kHz, %s)" % ("Opus" if twovoip_available else "PCM"))

func _check_twovoip() -> bool:
	# Check if TwoVoip is loaded
	return ClassDB.class_exists("OpusEncoder") and ClassDB.class_exists("OpusDecoder")

func _init_opus():
	if not twovoip_available:
		return
	
	# Create Opus encoder/decoder
	opus_encoder = ClassDB.instantiate("OpusEncoder")
	opus_encoder.set_sample_rate(SAMPLE_RATE)
	opus_encoder.set_frame_size(frame_size_ms)
	opus_encoder.set_bitrate(opus_bitrate)
	opus_encoder.set_complexity(opus_complexity)
	
	if rnnoise_enabled:
		opus_encoder.set_rnnoise(true)
	
	print("Opus encoder initialized: %d kbps, complexity %d, RNNoise: %s" % 
		[opus_bitrate / 1000, opus_complexity, rnnoise_enabled])

func _setup_audio_bus():
	# Get or create Mic bus
	var mic_bus = AudioServer.get_bus_index("Mic")
	if mic_bus == -1:
		mic_bus = AudioServer.bus_count
		AudioServer.add_bus(mic_bus)
		AudioServer.set_bus_name(mic_bus, "Mic")
		AudioServer.set_bus_mute(mic_bus, true)  # Prevent feedback
	
	audio_bus_idx = mic_bus
	
	# Add AudioEffectCapture at the end (after High-Pass & Limiter)
	var capture_idx = -1
	for i in range(AudioServer.get_bus_effect_count(mic_bus)):
		var effect = AudioServer.get_bus_effect(mic_bus, i)
		if effect is AudioEffectCapture:
			capture_idx = i
			break
	
	if capture_idx == -1:
		audio_effect = AudioEffectCapture.new()
		audio_effect.buffer_length = 0.1
		AudioServer.add_bus_effect(mic_bus, audio_effect)
	else:
		audio_effect = AudioServer.get_bus_effect(mic_bus, capture_idx)

func start_recording():
	if recording:
		return
	
	recording = true
	
	# Create microphone player
	var mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Mic"
	add_child(mic_player)
	mic_player.play()
	
	# Immediately update nearby peers list
	_update_nearby_peers()
	
	print("Voice recording started (48kHz)")

func stop_recording():
	recording = false
	
	for child in get_children():
		if child is AudioStreamPlayer:
			child.queue_free()
	
	if audio_effect:
		audio_effect.clear_buffer()
	
	print("Voice recording stopped")

func _process(_delta):
	if not recording or not audio_effect:
		return
	
	# Process every frame for low latency
	_frame_counter += 1
	
	# Update nearby peers periodically
	_distance_check_counter += 1
	if _distance_check_counter >= _distance_check_interval:
		_distance_check_counter = 0
		_update_nearby_peers()
	
	if _cached_nearby_peers.is_empty():
		return
	
	# Get available audio frames
	var frames_available = audio_effect.get_frames_available()
	if frames_available == 0:
		return
	
	# Calculate frame size based on current setting
	var target_frames = int(SAMPLE_RATE * (frame_size_ms / 1000.0))
	
	if frames_available < target_frames:
		return  # Wait for full frame
	
	# Debug: First time capturing audio
	if _frame_counter == 1:
		print("Voice: Capturing audio (%d frames available, target: %d, frame_size: %dms)" % [frames_available, target_frames, frame_size_ms])
	
	# Capture audio
	var audio_data = audio_effect.get_buffer(target_frames)
	if audio_data.size() == 0:
		return
	
	# Convert to mono
	var mono_samples = PackedFloat32Array()
	mono_samples.resize(audio_data.size())
	for i in range(audio_data.size()):
		mono_samples[i] = (audio_data[i].x + audio_data[i].y) * 0.5
	
	# Encode with Opus (if available) or compress to Int16
	var compressed: PackedByteArray
	if twovoip_available and opus_encoder:
		compressed = opus_encoder.encode(mono_samples)
	else:
		# Fallback: Compress Float32 to Int16 (halves size)
		compressed = _compress_to_int16(mono_samples)
	
	# Send to nearby peers
	_send_voice_packet(compressed)

func _update_nearby_peers():
	_cached_nearby_peers.clear()
	
	var local_player = NetworkManager.get_local_player()
	if not local_player:
		return
	
	var local_pos = local_player.global_position
	var my_id = multiplayer.get_unique_id()
	
	# Add ALL other players (distance check can be added later)
	for peer_id in NetworkManager.players.keys():
		if peer_id == my_id:
			continue
		
		var player = NetworkManager.get_player(peer_id)
		if not player or not is_instance_valid(player):
			continue
		
		_cached_nearby_peers.append(peer_id)
	
	# Debug only on change
	if _cached_nearby_peers.size() > 0 and _distance_check_counter == 0:
		print("Voice: %d nearby peers to send to" % _cached_nearby_peers.size())

func _compress_to_int16(float_samples: PackedFloat32Array) -> PackedByteArray:
	# Convert Float32 (-1.0 to 1.0) to Int16 (-32768 to 32767)
	var result = PackedByteArray()
	result.resize(float_samples.size() * 2)
	
	for i in range(float_samples.size()):
		var sample = clamp(float_samples[i], -1.0, 1.0)
		var int_sample = int(sample * 32767.0)
		result[i * 2] = int_sample & 0xFF
		result[i * 2 + 1] = (int_sample >> 8) & 0xFF
	
	return result

func _decompress_from_int16(byte_data: PackedByteArray) -> PackedFloat32Array:
	# Convert Int16 back to Float32
	var result = PackedFloat32Array()
	var sample_count = byte_data.size() / 2
	result.resize(sample_count)
	
	for i in range(sample_count):
		var low = byte_data[i * 2]
		var high = byte_data[i * 2 + 1]
		var int_sample = low | (high << 8)
		
		# Handle sign (Int16 is signed)
		if int_sample >= 32768:
			int_sample -= 65536
		
		result[i] = float(int_sample) / 32767.0
	
	return result

func _send_voice_packet(data: PackedByteArray):
	# Debug first packet
	if _frame_counter == 1:
		print("Voice: First packet size: %d bytes (Int16 compressed)" % data.size())
	
	if data.size() > 2048:
		print("Warning: Voice packet too large: %d bytes" % data.size())
		return
	
	if _cached_nearby_peers.is_empty():
		return
	
	for peer_id in _cached_nearby_peers:
		if NetworkManager.players.has(peer_id):
			_receive_voice_packet.rpc_id(peer_id, data)

@rpc("any_peer", "unreliable_ordered")
func _receive_voice_packet(compressed: PackedByteArray):
	var sender_id = multiplayer.get_remote_sender_id()
	
	if not NetworkManager.players.has(sender_id):
		print("Voice: Received packet from unknown peer %d" % sender_id)
		return
	
	# Debug: First packet from this peer
	if not voice_players.has(sender_id):
		print("Voice: First packet from peer %d, size: %d bytes" % [sender_id, compressed.size()])
	
	# Get or create jitter buffer
	if not jitter_buffers.has(sender_id):
		jitter_buffers[sender_id] = JitterBuffer.new()
	
	var jitter_buffer: JitterBuffer = jitter_buffers[sender_id]
	jitter_buffer.add_packet(jitter_buffer.sequence_number, compressed)
	jitter_buffer.sequence_number += 1
	
	# Try to get packet from buffer
	var packet_data = jitter_buffer.get_next_packet()
	if packet_data.is_empty():
		return  # Waiting for more packets
	
	# Decode audio
	var samples: PackedVector2Array
	if twovoip_available and ClassDB.class_exists("OpusDecoder"):
		# Decode with Opus
		if not opus_decoder:
			opus_decoder = ClassDB.instantiate("OpusDecoder")
			opus_decoder.set_sample_rate(SAMPLE_RATE)
			opus_decoder.set_frame_size(frame_size_ms)
		
		var mono_decoded = opus_decoder.decode(packet_data)
		
		# Convert mono to stereo
		samples = PackedVector2Array()
		samples.resize(mono_decoded.size())
		for i in range(mono_decoded.size()):
			var val = mono_decoded[i] * voice_volume
			samples[i] = Vector2(val, val)
	else:
		# Fallback: Decompress Int16 to Float32
		var mono_samples = _decompress_from_int16(packet_data)
		samples = PackedVector2Array()
		samples.resize(mono_samples.size())
		for i in range(mono_samples.size()):
			var val = mono_samples[i] * voice_volume
			samples[i] = Vector2(val, val)
	
	# Play audio
	_play_voice_audio(sender_id, samples)

func _play_voice_audio(peer_id: int, samples: PackedVector2Array):
	# Get or create voice player
	if not voice_players.has(peer_id):
		_setup_voice_player(peer_id)
	
	if not voice_players.has(peer_id):
		return
	
	var player_3d: AudioStreamPlayer3D = voice_players[peer_id]
	if not is_instance_valid(player_3d):
		return
	
	var playback: AudioStreamGeneratorPlayback = player_3d.get_stream_playback()
	if not playback:
		return
	
	# Push to playback
	playback.push_buffer(samples)

func _setup_voice_player(peer_id: int):
	var player = NetworkManager.get_player(peer_id)
	if not player or not is_instance_valid(player):
		return
	
	# Create 3D audio player
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = 0.2  # 200ms playback buffer
	
	var player_3d = AudioStreamPlayer3D.new()
	player_3d.name = "VoicePlayerOpus"
	player_3d.stream = stream
	player_3d.autoplay = true
	
	# 3D audio settings for proximity
	player_3d.max_distance = voice_range * 1.5
	player_3d.unit_size = 1.0
	player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player_3d.attenuation_filter_cutoff_hz = 20000  # No filtering for clarity
	player_3d.volume_db = 15.0  # Higher volume
	
	player.add_child(player_3d)
	voice_players[peer_id] = player_3d
	
	print("Voice player created for peer %d (Opus 48kHz)" % peer_id)

func cleanup_voice_player(peer_id: int):
	if voice_players.has(peer_id):
		var player_3d = voice_players[peer_id]
		if is_instance_valid(player_3d):
			player_3d.queue_free()
		voice_players.erase(peer_id)
	
	if jitter_buffers.has(peer_id):
		jitter_buffers.erase(peer_id)

func setup_voice_player(peer_id: int):
	_setup_voice_player(peer_id)

# Quality settings
func set_quality(level: int):
	match level:
		0:  # Quality 1 - Fast, lowest latency
			frame_size_ms = 10
			voice_volume = 1.5
		1:  # Quality 2
			frame_size_ms = 12
			voice_volume = 1.8
		2:  # Quality 3
			frame_size_ms = 15
			voice_volume = 2.0
		3:  # Quality 4 (Default) - Balanced
			frame_size_ms = 18
			voice_volume = 2.5
		4:  # Quality 5 - High quality
			frame_size_ms = 20
			voice_volume = 3.0
		5:  # Quality MAX - Best quality, loudest
			frame_size_ms = 20
			voice_volume = 4.0
	
	if opus_encoder:
		opus_encoder.set_bitrate(opus_bitrate)
	
	var level_text = "MAX" if level == 5 else str(level + 1)
	print("Voice quality: %s (vol: %.1fx, %dms)" % [level_text, voice_volume, frame_size_ms])
