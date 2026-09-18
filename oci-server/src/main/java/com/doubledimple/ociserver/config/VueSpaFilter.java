package com.doubledimple.ociserver.config;

import cn.dev33.satoken.exception.NotLoginException;
import cn.dev33.satoken.stp.StpUtil;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestAttributes;
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
 * HTML 页面交给 Vue：仅接管白名单 GET / HEAD，API、SSE 和下载保持原入口。
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 30)
public class VueSpaFilter extends OncePerRequestFilter {

    private static final Set<String> PUBLIC_PAGES = new HashSet<String>(Arrays.asList(
            "/login", "/m/login", "/forbidden"
    ));

    private static final Set<String> PAGES = new HashSet<String>(Arrays.asList(
            "/main",
            "/index",
            "/about/author",
            "/boot/dashboard",
            "/resource/list",
            "/tenants/list",
            "/tenants/regionList",
            "/tenants/auditPage",
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
            "/ai/chat",
            "/m", "/m/", "/m/tenants", "/m/regions", "/m/boot", "/m/add-boot",
            "/m/instances", "/m/oci-instances", "/m/tenant-instances", "/m/import",
            "/m/speedtest", "/m/monitor", "/m/settings", "/m/arm-regions",
            "/m/cloudflare", "/m/ai", "/m/notify-settings", "/m/traffic", "/m/cost",
            "/m/region-sub", "/m/user-mgr", "/m/audit-log", "/m/disk-info",
            "/m/security-rules", "/m/storage-instances", "/m/memo", "/m/mfa",
            "/m/vnic/manage", "/m/logs", "/m/open-logs", "/m/sysHelp"
    ));

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        if (!"GET".equalsIgnoreCase(request.getMethod()) && !"HEAD".equalsIgnoreCase(request.getMethod())) {
            filterChain.doFilter(request, response);
            return;
        }
        String path = request.getServletPath();
        if (path == null || path.isEmpty()) {
            path = "/";
        }
        // Spring MVC also accepts a trailing slash on legacy page mappings.
        while (path.length() > 1 && path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }
        if (isVuePage(path)) {
            if (!new ClassPathResource("static/index.html").exists()) {
                response.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
                response.setHeader("Cache-Control", "no-store");
                response.setContentType("text/plain;charset=UTF-8");
                if (!"HEAD".equalsIgnoreCase(request.getMethod())) {
                    response.getWriter().write("Web interface is unavailable.");
                }
                return;
            }
            if (!PUBLIC_PAGES.contains(path)) {
                RequestAttributes previousAttributes = RequestContextHolder.getRequestAttributes();
                RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request, response));
                try {
                    StpUtil.checkLogin();
                } catch (NotLoginException e) {
                    String loginPath = path.equals("/m") || path.startsWith("/m/") ? "/m/login" : "/login";
                    response.sendRedirect(request.getContextPath() + loginPath);
                    return;
                } finally {
                    if (previousAttributes == null) {
                        RequestContextHolder.resetRequestAttributes();
                    } else {
                        RequestContextHolder.setRequestAttributes(previousAttributes);
                    }
                }
            }
            request.getRequestDispatcher("/index.html").forward(request, response);
            return;
        }
        filterChain.doFilter(request, response);
    }

    private static boolean isVuePage(String path) {
        if (PUBLIC_PAGES.contains(path) || PAGES.contains(path)) {
            return true;
        }
        return path.startsWith("/oci/console/terminal/");
    }
}
