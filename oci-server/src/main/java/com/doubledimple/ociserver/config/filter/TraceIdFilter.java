package com.doubledimple.ociserver.config.filter;

import cn.hutool.core.lang.UUID;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * @version 1.0.0
 * @ClassName TraceIdFilter
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-09 07:05
 */
@Component
public class TraceIdFilter extends OncePerRequestFilter {

    private static final String TRACE_ID = "traceId";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        try {
            // 从请求头中获取 traceId，如果没有则生成一个新的
            String traceId = request.getHeader("X-Trace-Id");
            if (traceId == null || traceId.isEmpty()) {
                traceId = generateTraceId();
            }

            // 将 traceId 放入 MDC
            MDC.put(TRACE_ID, traceId);

            // 向响应头添加 traceId
            response.addHeader("X-Trace-Id", traceId);

            filterChain.doFilter(request, response);
        } finally {
            // 请求处理完成后清除 MDC
            MDC.remove(TRACE_ID);
        }
    }

    private String generateTraceId() {
        return UUID.randomUUID().toString().replace("-", "");
    }
}
