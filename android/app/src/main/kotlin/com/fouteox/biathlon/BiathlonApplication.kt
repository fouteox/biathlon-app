package com.fouteox.biathlon

import android.app.Application
import com.fouteox.biathlon.kit.IbuClient
import io.ktor.http.Url

class BiathlonApplication : Application() {
    /** One client for the whole app, through the server's cache when there is a server, to spare the IBU API. */
    val ibu: IbuClient by lazy {
        IbuClient(BuildConfig.SERVER_URL.takeIf { it.isNotEmpty() }?.let { Url("${it.trimEnd('/')}/ibu/") } ?: IbuClient.IBU_BASE_URL)
    }
}
