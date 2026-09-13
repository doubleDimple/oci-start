package com.doubledimple.ociserver.config;

import cn.dev33.satoken.exception.NotLoginException;
import cn.dev33.satoken.stp.StpUtil;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * HTML 业务页交给 Vue：仅拦截白名单 GET，JSON / SSE / 下载 / 登录 HTML 一律放行。
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 30)
public class VueSpaFilter extends OncePerRequestFilter {

    private static final Set<String> PAGES = new HashSet<String>(Arrays.asList(
            "/main",
            "/index",
            "/boot/dashboard",
            "/resource/list",
            "/tenants/list",
            "/tenants/regionList",
            "/tenants/regionSubList",
            "/tenants/addSpeed",
            "/tenants/bootPage",
            "/tenants/gcpBootPage",
            "/tenants/bootList",
            "/oci/list",
            "/email/management",
            "/oci/storage/page",
            "/boot/fullBootList",
            "/system/ai/models",
            "/delayTest",
            "/system/openLogs",
            "/other/instances/list",
            "/azure/vms",
            "/azure/resources",
            "/azure/storage",
            "/azure/networks",
            "/aws/ec2",
            "/aws/s3",
            "/aws/lambda",
            "/aws/rds",
            "/system/domainSettings",
            "/dns/cloudflare",
            "/dns/edgeone",
            "/ssl/nginx/management",
            "/vps/instances/list",
            "/system/ipSettings",
            "/system/logs",
            "/system/settings",
            "/vpnProxy/page",
            "/system/notifySettings",
            "/system/memPage",
            "/migration/migPage",
            "/mfa/page",
            "/system/apiTokens",
            "/oci/terminal",
            "/ssh/terminal",
            "/oci/sysHelp",
            "/oci/metricsPage",
            "/instanceDetail/bootList",
            "/cost/costPage",
            "/monitor/homePage",
            "/oci/vnic/manage",
            "/oci/console/terminal",
            "/ai/chat"
    ));

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        if (!"GET".equalsIgnoreCase(request.getMethod())) {
            filterChain.doFilter(request, response);
            return;
        }
        if (!new ClassPathResource("static/index.html").exists()) {
            filterChain.doFilter(request, response);
            return;
        }
        String path = request.getServletPath();
        if (path == null || path.isEmpty()) {
            path = "/";
        }
        if (isVuePage(path)) {
            RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request, response));
            try {
                StpUtil.checkLogin();
            } catch (NotLoginException e) {
                response.sendRedirect("/login");
                return;
            } finally {
                RequestContextHolder.resetRequestAttributes();
            }
            request.getRequestDispatcher("/index.html").forward(request, response);
            return;
        }
        filterChain.doFilter(request, response);
    }

    private static boolean isVuePage(String path) {
        if (PAGES.contains(path)) {
            return true;
        }
        return path.startsWith("/oci/console/terminal/");
    }
}
