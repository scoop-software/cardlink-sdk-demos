package de.scoopsoftware.cardlink.demo

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.decode.SvgDecoder
import okhttp3.OkHttpClient

/**
 * Application class that configures Coil with SVG support.
 * This enables loading SVG profile pictures from OAuth providers.
 */
class CardlinkApplication : Application(), ImageLoaderFactory {

    override fun newImageLoader(): ImageLoader {
        // Create OkHttpClient with browser User-Agent to avoid 403 from some servers
        val okHttpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
                    .build()
                chain.proceed(request)
            }
            .build()

        return ImageLoader.Builder(this)
            .okHttpClient(okHttpClient)
            .components {
                add(SvgDecoder.Factory())
            }
            .crossfade(true)
            .build()
    }
}
