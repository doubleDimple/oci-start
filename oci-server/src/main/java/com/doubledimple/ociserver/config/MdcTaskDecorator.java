package com.doubledimple.ociserver.config;

import org.slf4j.MDC;

import java.util.Map;
import java.util.concurrent.Callable;

/**
 * @version 1.0.0
 * @ClassName MdcTaskDecorator
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-09 07:10
 */
public class MdcTaskDecorator {

    public static <T> Callable<T> withMdc(Callable<T> callable) {
        Map<String, String> contextMap = MDC.getCopyOfContextMap();
        return () -> {
            Map<String, String> previousContext = MDC.getCopyOfContextMap();
            if (contextMap != null) {
                MDC.setContextMap(contextMap);
            }
            try {
                return callable.call();
            } finally {
                if (previousContext != null) {
                    MDC.setContextMap(previousContext);
                } else {
                    MDC.clear();
                }
            }
        };
    }

    public static Runnable withMdc(Runnable runnable) {
        Map<String, String> contextMap = MDC.getCopyOfContextMap();
        return () -> {
            Map<String, String> previousContext = MDC.getCopyOfContextMap();
            if (contextMap != null) {
                MDC.setContextMap(contextMap);
            }
            try {
                runnable.run();
            } finally {
                if (previousContext != null) {
                    MDC.setContextMap(previousContext);
                } else {
                    MDC.clear();
                }
            }
        };
    }
}
