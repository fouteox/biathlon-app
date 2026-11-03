package com.fouteox.biathlon

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.time.Duration

/**
 * The work that keeps notifications current, run by WorkManager: it waits for the network, goes
 * on once the app is gone, and retries with a backoff.
 */
object NotificationWork {
    /** Attempts of a failing request before it waits for the next change or launch, as iOS. */
    private const val MAX_ATTEMPTS = 5

    private val online = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    /** Sends the preferences to the server; a newer request replaces one waiting or running. */
    fun syncPush(context: Context) {
        val request = OneTimeWorkRequestBuilder<PushSyncWorker>().setConstraints(online).build()
        WorkManager.getInstance(context).enqueueUniqueWork("push-sync", ExistingWorkPolicy.REPLACE, request)
    }

    fun refreshReminders(context: Context) {
        val request = OneTimeWorkRequestBuilder<ReminderWorker>().setConstraints(online).build()
        WorkManager.getInstance(context).enqueueUniqueWork("reminders", ExistingWorkPolicy.REPLACE, request)
    }

    /**
     * Once a day, so that the coming week's races get their reminders and a race moved meanwhile
     * moves its reminder, even when the app isn't opened.
     */
    fun refreshRemindersDaily(context: Context) {
        val request = PeriodicWorkRequestBuilder<ReminderWorker>(Duration.ofDays(1)).setConstraints(online).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork("reminders-daily", ExistingPeriodicWorkPolicy.KEEP, request)
    }

    class PushSyncWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
        override suspend fun doWork(): Result {
            // A build without a server has no push alerts.
            val registration = (applicationContext as BiathlonApplication).pushRegistration ?: return Result.success()
            return when (registration.sync()) {
                PushRegistration.Outcome.DONE -> Result.success()
                PushRegistration.Outcome.RETRY -> if (runAttemptCount + 1 < MAX_ATTEMPTS) Result.retry() else Result.failure()
                PushRegistration.Outcome.FAILED -> Result.failure()
            }
        }
    }

    class ReminderWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
        override suspend fun doWork(): Result = when {
            (applicationContext as BiathlonApplication).reminders.refresh() -> Result.success()
            runAttemptCount + 1 < MAX_ATTEMPTS -> Result.retry()
            else -> Result.failure()
        }
    }
}
