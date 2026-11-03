package com.fouteox.biathlon

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await

/**
 * Play Integrity standard requests (https://developer.android.com/google/play/integrity/standard),
 * the Android counterpart of App Attest: a token bound to each request to the server by its hash.
 * The token provider is prepared once and kept, as Google recommends.
 */
class PlayIntegrity(context: Context) {
    private val manager = IntegrityManagerFactory.createStandard(context)
    private val lock = Mutex()
    private var provider: StandardIntegrityTokenProvider? = null

    suspend fun token(requestHash: String): String = try {
        request(requestHash)
    } catch (error: StandardIntegrityException) {
        // Google: prepare a new provider when the current one is no longer valid.
        if (error.errorCode != StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID) throw error
        lock.withLock { provider = null }
        request(requestHash)
    }

    private suspend fun request(requestHash: String): String {
        val request = StandardIntegrityTokenRequest.builder().setRequestHash(requestHash).build()
        return provider().request(request).await().token()
    }

    private suspend fun provider(): StandardIntegrityTokenProvider = lock.withLock {
        provider ?: manager.prepareIntegrityToken(
            PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(BuildConfig.CLOUD_PROJECT_NUMBER).build(),
        ).await().also { provider = it }
    }
}
