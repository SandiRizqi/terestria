package io.github.sandirizqi.terestria

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.graphhopper.GHRequest
import com.graphhopper.GraphHopper
import com.graphhopper.config.Profile
import com.graphhopper.routing.DefaultWeightingFactory
import com.graphhopper.routing.WeightingFactory
import com.graphhopper.routing.ev.EnumEncodedValue
import com.graphhopper.routing.ev.RoadClass
import com.graphhopper.routing.weighting.AbstractAdjustedWeighting
import com.graphhopper.routing.weighting.Weighting
import com.graphhopper.util.EdgeIteratorState
import com.graphhopper.util.PMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Handles GraphHopper offline routing via MethodChannel.
 *
 * Channel: com.terestria/routing
 * Methods:
 *   initialize(osmPath: String) → Boolean
 *   calculateRoute(fromLat, fromLon, toLat, toLon, profile) → Map
 *   isInitialized() → Boolean
 */
class RoutingPlugin(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL = "com.terestria/routing"
        private const val TAG = "RoutingPlugin"
    }

    private var graphHopper: GraphHopper? = null
    private val executor   = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize"    -> {
                val osmPath = call.argument<String>("osmPath")
                if (osmPath == null) {
                    result.error("INVALID_ARGS", "osmPath required", null)
                } else {
                    val forceRebuild = call.argument<Boolean>("forceRebuild") ?: false
                    initGraphHopper(osmPath, result, forceRebuild)
                }
            }
            "isInitialized" -> result.success(graphHopper != null)
            "calculateRoute" -> {
                val fromLat = call.argument<Double>("fromLat") ?: run {
                    result.error("INVALID_ARGS", "fromLat required", null); return
                }
                val fromLon = call.argument<Double>("fromLon") ?: run {
                    result.error("INVALID_ARGS", "fromLon required", null); return
                }
                val toLat   = call.argument<Double>("toLat") ?: run {
                    result.error("INVALID_ARGS", "toLat required", null); return
                }
                val toLon   = call.argument<Double>("toLon") ?: run {
                    result.error("INVALID_ARGS", "toLon required", null); return
                }
                val profile = call.argument<String>("profile") ?: "car"
                calculateRoute(fromLat, fromLon, toLat, toLon, profile, result)
            }
            else -> result.notImplemented()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INITIALIZE
    // ─────────────────────────────────────────────────────────────────────────

    private fun initGraphHopper(osmPath: String, result: Result, forceRebuild: Boolean = false) {
        executor.submit {
            try {
                Log.i(TAG, "initGraphHopper: start — $osmPath (forceRebuild=$forceRebuild)")

                val osmFile = File(osmPath)
                if (!osmFile.exists()) {
                    Log.e(TAG, "initGraphHopper: file not found — $osmPath")
                    mainHandler.post {
                        result.error("FILE_NOT_FOUND", "OSM file not found: $osmPath", null)
                    }
                    return@submit
                }

                Log.i(TAG, "initGraphHopper: file size = ${osmFile.length() / 1024} KB")

                // Delete stale graph cache when a new PBF file has been imported,
                // so GraphHopper is forced to rebuild from the new source data.
                // NOTE: the "-v2" suffix bumps the cache version — adding the
                // road_class encoded value + the car_recommended profile changes
                // the graph layout, so every existing install must rebuild once.
                val graphCacheDir = File(context.filesDir, "gh-graph-cache-v2")
                // Clean up the legacy v1 cache (built without road_class) to
                // reclaim space and avoid load mismatches.
                val legacyCacheDir = File(context.filesDir, "gh-graph-cache")
                if (legacyCacheDir.exists()) {
                    legacyCacheDir.deleteRecursively()
                    Log.i(TAG, "initGraphHopper: legacy graph cache removed")
                }
                if (forceRebuild && graphCacheDir.exists()) {
                    graphCacheDir.deleteRecursively()
                    Log.i(TAG, "initGraphHopper: graph cache deleted for rebuild")
                }
                val graphDir = graphCacheDir.absolutePath
                Log.i(TAG, "initGraphHopper: graph dir = $graphDir")

                // GraphHopper's CustomModel cannot run on Android — it compiles
                // the model expressions at runtime with Janino, which needs JVM
                // .class files (Android only has DEX) → "Cannot compile expression".
                // So the "recommended" mode is implemented as a plain Kotlin
                // Weighting (RecommendedWeighting) injected via a custom
                // WeightingFactory below — no Janino involved.
                val gh = object : GraphHopper() {
                    override fun createWeightingFactory(): WeightingFactory {
                        val em = encodingManager
                        return object : DefaultWeightingFactory(baseGraph, em) {
                            override fun createWeighting(
                                profile: Profile,
                                requestHints: PMap,
                                disableTurnCosts: Boolean
                            ): Weighting {
                                if (profile.weighting.equals("recommended", ignoreCase = true)) {
                                    // Base = the normal fastest weighting for this vehicle…
                                    val base = super.createWeighting(
                                        Profile(profile.name)
                                            .setVehicle(profile.vehicle)
                                            .setWeighting("fastest")
                                            .setTurnCosts(profile.isTurnCosts),
                                        requestHints, disableTurnCosts
                                    )
                                    // …then bias it by road_class priority.
                                    val rcEnc = em.getEnumEncodedValue(
                                        RoadClass.KEY, RoadClass::class.java
                                    )
                                    return RecommendedWeighting(base, rcEnc)
                                }
                                return super.createWeighting(profile, requestHints, disableTurnCosts)
                            }
                        }
                    }
                }
                gh.setOSMFile(osmPath)
                gh.setGraphHopperLocation(graphDir)
                // road_class is required by RecommendedWeighting.
                gh.setEncodedValuesString("road_class")
                // "car_recommended" uses our custom "recommended" weighting;
                // base speeds still come from the "car" vehicle.
                gh.setProfiles(
                    Profile("car").setWeighting("fastest"),
                    Profile("car_recommended").setVehicle("car").setWeighting("recommended"),
                    Profile("foot").setWeighting("fastest")
                )
                // CH intentionally NOT configured: without setCHProfiles() the handler
                // stays disabled (isEnabled == false), so importOrLoad() skips CH
                // preprocessing entirely.  A* without CH is fast enough for local areas
                // and init takes seconds instead of minutes.

                Log.i(TAG, "initGraphHopper: calling importOrLoad()…")
                gh.importOrLoad()
                Log.i(TAG, "initGraphHopper: importOrLoad() done ✓")

                graphHopper = gh
                mainHandler.post { result.success(true) }

            } catch (e: Throwable) {
                // Catch Throwable (not just Exception) so Java Errors (OOM, etc.)
                // are forwarded to Dart instead of silently killing the thread.
                Log.e(TAG, "initGraphHopper: FAILED — ${e.javaClass.simpleName}: ${e.message}", e)
                mainHandler.post {
                    result.error(
                        "INIT_ERROR",
                        "${e.javaClass.simpleName}: ${e.message ?: "Unknown error"}",
                        null
                    )
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CALCULATE ROUTE
    // ─────────────────────────────────────────────────────────────────────────

    private fun calculateRoute(
        fromLat: Double, fromLon: Double,
        toLat: Double, toLon: Double,
        profile: String,
        result: Result
    ) {
        val gh = graphHopper
        if (gh == null) {
            result.error("NOT_INIT", "GraphHopper belum diinisialisasi. Load OSM data terlebih dahulu.", null)
            return
        }

        // Map to a registered profile; fall back to fastest car if unknown.
        val safeProfile = when (profile) {
            "foot"            -> "foot"
            "car_recommended" -> "car_recommended"
            else              -> "car"
        }

        executor.submit {
            try {
                val req = GHRequest(fromLat, fromLon, toLat, toLon)
                    .setProfile(safeProfile)
                    .setLocale(Locale.getDefault())

                val rsp = gh.route(req)

                if (rsp.hasErrors()) {
                    mainHandler.post {
                        result.error("ROUTE_ERROR", rsp.errors.first().message, null)
                    }
                    return@submit
                }

                val path   = rsp.best
                val pts    = path.points

                // Serialize route points
                val points = ArrayList<Map<String, Double>>()
                for (i in 0 until pts.size()) {
                    points.add(mapOf("lat" to pts.getLat(i), "lon" to pts.getLon(i)))
                }

                // Serialize instructions
                val instructions = ArrayList<Map<String, Any>>()
                var cumPointIdx  = 0
                for (instr in path.instructions) {
                    instructions.add(
                        mapOf(
                            "text"     to (instr.name ?: ""),
                            "distance" to instr.distance,
                            "time"     to instr.time,
                            "sign"     to instr.sign,
                            "interval" to cumPointIdx
                        )
                    )
                    cumPointIdx += instr.length
                }

                val payload = mapOf(
                    "points"       to points,
                    "instructions" to instructions,
                    "distance"     to path.distance,
                    "time"         to path.time,
                    "ascend"       to path.ascend,
                    "descend"      to path.descend
                )

                mainHandler.post { result.success(payload) }

            } catch (e: Throwable) {
                Log.e(TAG, "calculateRoute: FAILED — ${e.javaClass.simpleName}: ${e.message}", e)
                mainHandler.post {
                    result.error(
                        "ROUTE_ERROR",
                        "${e.javaClass.simpleName}: ${e.message ?: "Unknown error"}",
                        null
                    )
                }
            }
        }
    }
}

/**
 * "Recommendation" weighting: wraps the fastest [Weighting] and biases routing
 * toward higher road classes by dividing each edge weight by a road_class
 * priority (<= 1.0). Pure Kotlin — no Janino / CustomModel — so it runs on
 * Android, unlike GraphHopper's CustomModel-based custom weighting.
 *
 * Because every priority is <= 1.0 the adjusted weight is always >= the base
 * (fastest) weight, so delegating getMinWeight() to the base stays an
 * admissible A* heuristic.
 */
private class RecommendedWeighting(
    superWeighting: Weighting,
    private val roadClassEnc: EnumEncodedValue<RoadClass>
) : AbstractAdjustedWeighting(superWeighting) {

    private fun priorityOf(rc: RoadClass): Double = when (rc) {
        RoadClass.MOTORWAY, RoadClass.TRUNK, RoadClass.PRIMARY -> 1.0
        RoadClass.SECONDARY    -> 0.85
        RoadClass.TERTIARY     -> 0.70
        RoadClass.UNCLASSIFIED -> 0.60
        RoadClass.RESIDENTIAL  -> 0.50
        RoadClass.SERVICE      -> 0.30
        RoadClass.TRACK        -> 0.15
        else                   -> 0.40
    }

    override fun calcEdgeWeight(edgeState: EdgeIteratorState, reverse: Boolean): Double {
        val w = superWeighting.calcEdgeWeight(edgeState, reverse)
        if (w.isInfinite()) return w
        return w / priorityOf(edgeState.get(roadClassEnc))
    }

    override fun getName(): String = "recommended"
}
