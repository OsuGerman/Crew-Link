package com.crewlink.crew_link

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

/**
 * Platform-channel handler for microphone capture on Android.
 *
 * Channels:
 *   crewlink/ptt         (MethodChannel)  — startRecording / stopRecording
 *   crewlink/ptt/frames  (EventChannel)   — Opus packets (API 29+) or int16 PCM fallback
 *
 * Audio path:
 *   AudioRecord (48 kHz, mono, int16)
 *     → MediaCodec Opus encoder (API 29+, 16 kbps VOIP)
 *       or raw int16 PCM frames (960 samples) on API < 29 / no Opus codec
 *     → FlutterEventSink → Dart frames stream
 */
class PttAudioChannel(messenger: BinaryMessenger) : EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "crewlink/ptt"
        const val EVENT_CHANNEL  = "crewlink/ptt/frames"

        private const val SAMPLE_RATE   = 48_000
        private const val FRAME_SAMPLES = 960        // 20 ms @ 48 kHz
        private const val FRAME_BYTES   = FRAME_SAMPLES * 2
        private const val OPUS_BITRATE  = 16_000
    }

    private var eventSink:   EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    @Volatile private var recording = false
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> startRecording(result)
                "stopRecording"  -> { stopRecording(); result.success(null) }
                else             -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    private fun startRecording(result: MethodChannel.Result) {
        if (recording) { result.success(null); return }

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
        recorder.startRecording()
        result.success(null)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            captureWithOpus(recorder)
        } else {
            captureRawPcm(recorder)
        }
    }

    private fun stopRecording() {
        recording = false
        audioRecord?.apply { stop(); release() }
        audioRecord = null
    }

    // ── Opus path (API 29+) ──────────────────────────────────────────────────

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
            // Device has no Opus encoder; degrade to raw PCM.
            captureRawPcm(recorder)
            return
        }

        thread(name = "ptt-opus") {
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
                // AudioRecord stopped externally; exit cleanly.
            } finally {
                codec.stop()
                codec.release()
            }
        }
    }

    private fun drainOutput(codec: MediaCodec, bufInfo: MediaCodec.BufferInfo) {
        var outIdx = codec.dequeueOutputBuffer(bufInfo, 0L)
        while (outIdx >= 0) {
            val isConfig = (bufInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
            if (!isConfig && bufInfo.size > 0) {
                val outBuf = codec.getOutputBuffer(outIdx)
                if (outBuf != null) {
                    val frame = ByteArray(bufInfo.size)
                    outBuf.position(bufInfo.offset)
                    outBuf.get(frame)
                    val sink = eventSink
                    if (sink != null) mainHandler.post { sink.success(frame) }
                }
            }
            codec.releaseOutputBuffer(outIdx, false)
            outIdx = codec.dequeueOutputBuffer(bufInfo, 0L)
        }
    }

    // ── Raw PCM fallback (API < 29 or no Opus codec) ─────────────────────────

    private fun captureRawPcm(recorder: AudioRecord) {
        thread(name = "ptt-pcm") {
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
                            val frame = pcmToBytes(accumulator, FRAME_SAMPLES)
                            val sink  = eventSink
                            if (sink != null) mainHandler.post { sink.success(frame) }
                            accumulated = 0
                        }
                    }
                }
            } catch (e: IllegalStateException) {
                // AudioRecord stopped externally; exit cleanly.
            }
        }
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
