package com.crewlink.crew_link

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.concurrent.thread

/**
 * Platform-channel handler for microphone capture AND playback on Android.
 *
 * Channels:
 *   crewlink/ptt         (MethodChannel)  — startRecording / stopRecording /
 *                                           playFrame / stopPlayback
 *   crewlink/ptt/frames  (EventChannel)   — captured frames as byte arrays
 *   crewlink/ptt/session (EventChannel)   — audio-focus lifecycle events
 *
 * Wire format: every frame is prefixed with a 1-byte codec tag so the receiver
 * knows how to decode it. iOS (PttAudioChannel.swift) uses the SAME tags.
 *   0x01 = Opus packet, 0x00 = raw int16 PCM (little-endian, 960 samples).
 *
 * Record path:  AudioRecord (48 kHz mono int16) → MediaCodec Opus (API 29+)
 *               or raw int16 PCM → tag → EventSink → Dart frames stream.
 * Playback path: Dart playFrame(bytes) → tag → Opus decode (API 29+) or PCM
 *                → AudioTrack → speaker. Runs on a dedicated playback thread.
 */
class PttAudioChannel(messenger: BinaryMessenger, private val context: Context) :
    EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL  = "crewlink/ptt"
        const val EVENT_CHANNEL   = "crewlink/ptt/frames"
        const val SESSION_CHANNEL = "crewlink/ptt/session"

        private const val SAMPLE_RATE   = 48_000
        private const val FRAME_SAMPLES = 960        // 20 ms @ 48 kHz
        private const val FRAME_BYTES   = FRAME_SAMPLES * 2
        private const val OPUS_BITRATE  = 16_000

        // 1-byte codec tag — MUST match ios/Runner/PttAudioChannel.swift.
        private const val CODEC_OPUS: Byte = 1
        private const val CODEC_PCM:  Byte = 0
    }

    private var eventSink:   EventChannel.EventSink? = null
    private var sessionSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    @Volatile private var recording = false
    private var recordingThread: Thread? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Playback runs on a single dedicated thread so AudioTrack.write never
    // blocks the platform/main thread (ANR risk).
    private val playbackLock = Any()
    private var playbackExecutor: ExecutorService? = null
    private var audioTrack:  AudioTrack? = null
    private var opusDecoder: MediaCodec? = null

    private val audioManager by lazy {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                if (recording) stopRecording()
                emitSession("interruptionBegan")
            }
            AudioManager.AUDIOFOCUS_GAIN -> emitSession("interruptionEnded", shouldResume = true)
        }
    }

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> startRecording(result)
                "stopRecording"  -> { stopRecording(); result.success(null) }
                "playFrame"      -> playFrame(call.arguments, result)
                "stopPlayback"   -> { stopPlayback(); result.success(null) }
                else             -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
        EventChannel(messenger, SESSION_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sessionSink = events
                }
                override fun onCancel(arguments: Any?) {
                    sessionSink = null
                }
            },
        )
    }

    // ── Recording ─────────────────────────────────────────────────────────────

    private fun startRecording(result: MethodChannel.Result) {
        if (recording) { result.success(null); return }

        // Runtime permission check so Dart can distinguish "denied" from other
        // init failures and prompt the user. Context.checkSelfPermission is M+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.error("PERMISSION_DENIED", "RECORD_AUDIO permission not granted", null)
            return
        }

        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minBuf, FRAME_BYTES * 4),
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            result.error("INIT_ERROR", "AudioRecord failed to initialize", null)
            return
        }
        audioRecord = recorder
        recording = true
        requestAudioFocus()
        recorder.startRecording()
        result.success(null)

        // Capture loop on its own thread; joined in stopRecording before the
        // recorder is released to avoid a use-after-free / SIGSEGV race.
        recordingThread = thread(name = "ptt-capture") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                captureWithOpus(recorder)
            } else {
                captureRawPcm(recorder)
            }
        }
    }

    private fun stopRecording() {
        if (!recording && audioRecord == null) return
        recording = false
        // Wait for the capture loop to leave recorder.read() before releasing.
        recordingThread?.let { t -> try { t.join(2_000) } catch (_: InterruptedException) {} }
        recordingThread = null
        audioRecord?.apply {
            try { stop() } catch (_: Exception) {}
            release()
        }
        audioRecord = null
        abandonAudioFocus()
    }

    private fun captureWithOpus(recorder: AudioRecord) {
        val codec = try {
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_OPUS).also { c ->
                val fmt = MediaFormat.createAudioFormat(
                    MediaFormat.MIMETYPE_AUDIO_OPUS, SAMPLE_RATE, 1)
                fmt.setInteger(MediaFormat.KEY_BIT_RATE, OPUS_BITRATE)
                fmt.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, FRAME_BYTES)
                c.configure(fmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                c.start()
            }
        } catch (e: Exception) {
            // Device has no Opus encoder; degrade to raw PCM (same thread).
            captureRawPcm(recorder)
            return
        }

        val bufInfo   = MediaCodec.BufferInfo()
        val pcm       = ShortArray(FRAME_SAMPLES)
        var presentUs = 0L
        try {
            while (recording) {
                val idx = codec.dequeueInputBuffer(10_000L)
                if (idx >= 0) {
                    val buf = codec.getInputBuffer(idx)
                    if (buf != null) {
                        buf.clear()
                        val read = recorder.read(pcm, 0, FRAME_SAMPLES)
                        if (read > 0) {
                            val bytes = pcmToBytes(pcm, read)
                            buf.put(bytes)
                            codec.queueInputBuffer(idx, 0, bytes.size, presentUs, 0)
                            presentUs += (read * 1_000_000L) / SAMPLE_RATE
                        } else {
                            codec.queueInputBuffer(idx, 0, 0, presentUs, 0)
                        }
                    }
                }
                drainOutput(codec, bufInfo)
            }
        } catch (e: IllegalStateException) {
            // AudioRecord/codec stopped externally; exit cleanly.
        } finally {
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
        }
    }

    private fun drainOutput(codec: MediaCodec, bufInfo: MediaCodec.BufferInfo) {
        var outIdx = codec.dequeueOutputBuffer(bufInfo, 0L)
        while (outIdx >= 0) {
            val isConfig = (bufInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
            if (!isConfig && bufInfo.size > 0) {
                val outBuf = codec.getOutputBuffer(outIdx)
                if (outBuf != null) {
                    val frame = ByteArray(1 + bufInfo.size)
                    frame[0] = CODEC_OPUS
                    outBuf.position(bufInfo.offset)
                    outBuf.get(frame, 1, bufInfo.size)
                    emitFrame(frame)
                }
            }
            codec.releaseOutputBuffer(outIdx, false)
            outIdx = codec.dequeueOutputBuffer(bufInfo, 0L)
        }
    }

    private fun captureRawPcm(recorder: AudioRecord) {
        val accumulator = ShortArray(FRAME_SAMPLES)
        var accumulated = 0
        val chunk       = ShortArray(FRAME_SAMPLES)
        try {
            while (recording) {
                val read = recorder.read(chunk, 0, chunk.size)
                if (read <= 0) continue
                var offset = 0
                while (offset < read) {
                    val toCopy = minOf(read - offset, FRAME_SAMPLES - accumulated)
                    System.arraycopy(chunk, offset, accumulator, accumulated, toCopy)
                    accumulated += toCopy
                    offset      += toCopy
                    if (accumulated == FRAME_SAMPLES) {
                        val pcmBytes = pcmToBytes(accumulator, FRAME_SAMPLES)
                        val frame = ByteArray(1 + pcmBytes.size)
                        frame[0] = CODEC_PCM
                        System.arraycopy(pcmBytes, 0, frame, 1, pcmBytes.size)
                        emitFrame(frame)
                        accumulated = 0
                    }
                }
            }
        } catch (e: IllegalStateException) {
            // AudioRecord stopped externally; exit cleanly.
        }
    }

    /// Posts a frame to the Dart frames stream. Captures the sink and re-checks
    /// identity on the main thread so a frame is never delivered to a sink that
    /// was swapped/cancelled between capture and delivery.
    private fun emitFrame(frame: ByteArray) {
        val sink = eventSink ?: return
        mainHandler.post { if (eventSink === sink) sink.success(frame) }
    }

    // ── Playback ───────────────────────────────────────────────────────────────

    private fun playFrame(arguments: Any?, result: MethodChannel.Result) {
        val data = arguments as? ByteArray
        if (data == null || data.isEmpty()) {
            result.success(null)
            return
        }
        ensurePlaybackExecutor().execute { handleFrame(data) }
        result.success(null)
    }

    private fun ensurePlaybackExecutor(): ExecutorService {
        synchronized(playbackLock) {
            val existing = playbackExecutor
            if (existing != null && !existing.isShutdown) return existing
            val created = Executors.newSingleThreadExecutor()
            playbackExecutor = created
            return created
        }
    }

    /// Runs on the single playback thread.
    private fun handleFrame(data: ByteArray) {
        val track = ensureAudioTrack() ?: return
        val codec = data[0]
        if (data.size <= 1) return
        val payload = data.copyOfRange(1, data.size)
        if (codec == CODEC_OPUS) {
            decodeOpusAndWrite(payload, track)
        } else {
            track.write(payload, 0, payload.size)
        }
    }

    private fun ensureAudioTrack(): AudioTrack? {
        audioTrack?.let { return it }
        val minBuf = AudioTrack.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val track = try {
            AudioTrack(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
                maxOf(minBuf, FRAME_BYTES * 4),
                AudioTrack.MODE_STREAM,
                AudioManager.AUDIO_SESSION_ID_GENERATE,
            )
        } catch (e: Exception) {
            return null
        }
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            return null
        }
        track.play()
        audioTrack = track
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            opusDecoder = configureOpusDecoder()
        }
        return track
    }

    private fun configureOpusDecoder(): MediaCodec? {
        return try {
            val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_OPUS)
            val fmt = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_OPUS, SAMPLE_RATE, 1)
            // MediaCodec's Opus decoder needs the identification header (csd-0)
            // plus codec-delay (csd-1) and seek-preroll (csd-2) in nanoseconds.
            fmt.setByteBuffer("csd-0", ByteBuffer.wrap(opusIdHeader()))
            fmt.setByteBuffer("csd-1", ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).apply { putLong(0L); flip() })
            fmt.setByteBuffer("csd-2", ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).apply { putLong(0L); flip() })
            codec.configure(fmt, null, null, 0)
            codec.start()
            codec
        } catch (e: Exception) {
            null
        }
    }

    private fun opusIdHeader(): ByteArray {
        val b = ByteBuffer.allocate(19).order(ByteOrder.LITTLE_ENDIAN)
        b.put("OpusHead".toByteArray(Charsets.US_ASCII)) // 8 bytes magic
        b.put(1.toByte())              // version
        b.put(1.toByte())              // channel count (mono)
        b.putShort(0.toShort())        // pre-skip
        b.putInt(SAMPLE_RATE)          // input sample rate
        b.putShort(0.toShort())        // output gain
        b.put(0.toByte())              // channel mapping family
        return b.array()
    }

    private fun decodeOpusAndWrite(payload: ByteArray, track: AudioTrack) {
        // No decoder (creation failed / pre-Q) → drop the Opus frame. We must
        // NOT reinterpret Opus bytes as PCM, which would be a loud noise burst.
        val codec = opusDecoder ?: return
        try {
            val inIdx = codec.dequeueInputBuffer(10_000L)
            if (inIdx >= 0) {
                val inBuf = codec.getInputBuffer(inIdx)
                inBuf?.clear()
                inBuf?.put(payload)
                codec.queueInputBuffer(inIdx, 0, payload.size, 0L, 0)
            }
            val info = MediaCodec.BufferInfo()
            var outIdx = codec.dequeueOutputBuffer(info, 10_000L)
            while (outIdx >= 0) {
                val outBuf = codec.getOutputBuffer(outIdx)
                if (outBuf != null && info.size > 0) {
                    val pcm = ByteArray(info.size)
                    outBuf.position(info.offset)
                    outBuf.get(pcm)
                    track.write(pcm, 0, pcm.size)
                }
                codec.releaseOutputBuffer(outIdx, false)
                outIdx = codec.dequeueOutputBuffer(info, 0L)
            }
        } catch (e: IllegalStateException) {
            // Decoder in a bad state — drop this frame.
        }
    }

    private fun stopPlayback() {
        val exec = synchronized(playbackLock) {
            val e = playbackExecutor
            playbackExecutor = null
            e
        }
        // Tear down on the playback thread (same thread that created them), then
        // let the executor terminate.
        exec?.execute { teardownPlayback() }
        exec?.shutdown()
    }

    private fun teardownPlayback() {
        try { audioTrack?.stop() } catch (_: Exception) {}
        audioTrack?.release()
        audioTrack = null
        try { opusDecoder?.stop() } catch (_: Exception) {}
        opusDecoder?.release()
        opusDecoder = null
    }

    // ── Audio focus / session events ────────────────────────────────────────────

    private fun requestAudioFocus() {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = req
            audioManager.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    private fun emitSession(type: String, shouldResume: Boolean = false) {
        val sink = sessionSink ?: return
        val map = mapOf<String, Any?>("type" to type, "shouldResume" to shouldResume)
        mainHandler.post { if (sessionSink === sink) sink.success(map) }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun pcmToBytes(shorts: ShortArray, length: Int): ByteArray {
        val buf = ByteBuffer.allocate(length * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until length) buf.putShort(shorts[i])
        return buf.array()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
