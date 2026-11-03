package com.fouteox.biathlon

import android.app.Application
import com.fouteox.biathlon.kit.IbuClient
import com.fouteox.biathlon.kit.ServerClient
import com.fouteox.biathlon.kit.WikidataClient
import io.ktor.http.Url

class BiathlonApplication : Application() {
    /** The server, when the build has one: the app then goes without what it adds. */
    val server: ServerClient? by lazy {
        BuildConfig.SERVER_URL.takeIf { it.isNotEmpty() }?.let { ServerClient(Url("${it.trimEnd('/')}/")) }
    }

    /** One client for the whole app, through the server's cache when there is a server, to spare the IBU API. */
    val ibu: IbuClient by lazy { IbuClient(server?.let { Url("${it.baseUrl}ibu/") } ?: IbuClient.IBU_BASE_URL) }

    /** Named as the iOS app names itself to Wikimedia, which asks for a way to reach its developer. */
    val wikidata: WikidataClient by lazy {
        WikidataClient("Biathlon/${BuildConfig.VERSION_NAME} (https://github.com/fouteox/biathlon-app)")
    }
}
