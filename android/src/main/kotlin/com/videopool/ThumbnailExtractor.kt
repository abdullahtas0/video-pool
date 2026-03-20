package com.videopool

import android.media.MediaMetadataRetriever
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class ThumbnailExtractor {
    companion object {
        fun register(channel: MethodChannel) {
            channel.setMethodCallHandler { call, result ->
                if (call.method == "extractThumbnail") {
                    val videoPath = call.argument<String>("videoPath")
                    val outputPath = call.argument<String>("outputPath")

                    if (videoPath == null || outputPath == null) {
                        result.error("INVALID_ARGS", "Missing videoPath or outputPath", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val retriever = MediaMetadataRetriever()
                            retriever.setDataSource(videoPath)
                            val bitmap = retriever.getFrameAtTime(
                                0,
                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                            )
                            retriever.release()

                            if (bitmap != null) {
                                val file = File(outputPath)
                                FileOutputStream(file).use { out ->
                                    bitmap.compress(
                                        android.graphics.Bitmap.CompressFormat.JPEG,
                                        70,
                                        out
                                    )
                                }
                                bitmap.recycle()
                                result.success(outputPath)
                            } else {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }.start()
                }
            }
        }
    }
}
