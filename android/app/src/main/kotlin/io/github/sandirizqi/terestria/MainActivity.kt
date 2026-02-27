package io.github.sandirizqi.terestria

import android.os.Bundle
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "io.github.sandirizqi.terestria/python"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializePython" -> {
                    // Python is no longer used, return false or error
                    result.error("NOT_SUPPORTED", "Python is no longer supported in this app", null)
                }
                
                "runPythonCode" -> {
                    // Python is no longer used, return error
                    result.error("NOT_SUPPORTED", "Python is no longer supported in this app", null)
                }
                
                "callPythonFunction" -> {
                    // Python is no longer used, return error
                    result.error("NOT_SUPPORTED", "Python is no longer supported in this app", null)
                }
                
                "pdfToImage" -> {
                    try {
                        val pdfPath = call.argument<String>("pdfPath")
                        val outputPath = call.argument<String>("outputPath")
                        val pageNumber = call.argument<Int>("page") ?: 0
                        val dpi = call.argument<Int>("dpi") ?: 150
                        
                        if (pdfPath == null || outputPath == null) {
                            result.error("INVALID_ARGS", "PDF path and output path are required", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            val pdfFile = File(pdfPath)
                            if (!pdfFile.exists()) {
                                result.error("FILE_NOT_FOUND", "PDF file not found: $pdfPath", null)
                                return@setMethodCallHandler
                            }
                            
                            // Open PDF
                            val fileDescriptor = ParcelFileDescriptor.open(
                                pdfFile,
                                ParcelFileDescriptor.MODE_READ_ONLY
                            )
                            val pdfRenderer = PdfRenderer(fileDescriptor)
                            
                            // Check page number
                            if (pageNumber >= pdfRenderer.pageCount) {
                                pdfRenderer.close()
                                fileDescriptor.close()
                                result.error("INVALID_PAGE", "Page $pageNumber does not exist", null)
                                return@setMethodCallHandler
                            }
                            
                            // Open page
                            val page = pdfRenderer.openPage(pageNumber)
                            
                            // Calculate dimensions based on DPI
                            val scale = dpi / 72f // 72 DPI is default
                            val width = (page.width * scale).toInt()
                            val height = (page.height * scale).toInt()
                            
                            // Create bitmap
                            val bitmap = Bitmap.createBitmap(
                                width,
                                height,
                                Bitmap.Config.ARGB_8888
                            )
                            
                            // Render page to bitmap
                            page.render(
                                bitmap,
                                null,
                                null,
                                PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY
                            )
                            
                            // Save bitmap to file
                            val outputFile = File(outputPath)
                            outputFile.parentFile?.mkdirs()
                            
                            FileOutputStream(outputFile).use { out ->
                                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                            }
                            
                            // Close resources
                            page.close()
                            pdfRenderer.close()
                            fileDescriptor.close()
                            bitmap.recycle()
                            
                            result.success(mapOf(
                                "success" to true,
                                "outputPath" to outputPath,
                                "width" to width,
                                "height" to height,
                                "dpi" to dpi,
                                "message" to "PDF page $pageNumber converted to image"
                            ))
                        } catch (e: Exception) {
                            result.error("CONVERSION_ERROR", "Failed to convert PDF: ${e.message}", null)
                        }
                    } catch (e: Exception) {
                        result.error("PDF_TO_IMAGE_ERROR", "Error: ${e.message}", null)
                    }
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
