package com.fouteox.biathlon

import android.app.Application
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.WikidataClient
import io.ktor.http.Url

class BiathlonApplication : Application() {
    /** One client for the whole app, through the server's cache when there is a server, to spare the IBU API. */
    val ibu: IbuClient by lazy {
        IbuClient(BuildConfig.SERVER_URL.takeIf { it.isNotEmpty() }?.let { Url("${it.trimEnd('/')}/ibu/") } ?: IbuClient.IBU_BASE_URL)
    }

    /** Named as the iOS app names itself to Wikimedia, which asks for a way to reach its developer. */
    val wikidata: WikidataClient by lazy {
        WikidataClient("Biathlon/${BuildConfig.VERSION_NAME} (https://github.com/fouteox/biathlon-app)")
    }
}
