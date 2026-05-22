package com.doubledimple.ocicommon.utils;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;

public class CompletableFutureUtils {
    public static <T> CompletableFuture<T> completeOnTimeout(
            CompletableFuture<T> future,
            T value,
            long timeout,
            TimeUnit unit,
            ScheduledExecutorService scheduler) {

        final CompletableFuture<T> timeoutFuture = new CompletableFuture<>();
        scheduler.schedule(() -> timeoutFuture.complete(value), timeout, unit);

        return future.applyToEither(timeoutFuture, Function.identity());
    }
}
