package com.doubledimple.ociserver.config.exception;

import cn.dev33.satoken.exception.NotLoginException;
import org.springframework.http.ResponseEntity;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;

import javax.servlet.http.HttpServletRequest;

import static com.doubledimple.ocicommon.utils.IpUtils.getClientIpAddress;

@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(IpBannedException.class)
    public String handleIpBannedException(IpBannedException e, HttpServletRequest request, Model model) {
        model.addAttribute("message", e.getMessage());
        model.addAttribute("code", 403);
        model.addAttribute("ip", getClientIpAddress(request));
        return "error/403";
    }

    @ExceptionHandler(NotLoginException.class)
    public void handleNotLoginException(NotLoginException e, HttpServletRequest request,
                                        javax.servlet.http.HttpServletResponse response) throws Exception {
        String xRequestedWith = request.getHeader("X-Requested-With");
        String accept = request.getHeader("Accept");
        boolean isAjax = "XMLHttpRequest".equals(xRequestedWith)
                || (accept != null && accept.contains("application/json"));
        if (isAjax) {
            response.setStatus(401);
            response.setContentType("application/json;charset=utf-8");
            response.getWriter().write("{\"code\":401,\"message\":\"未登录或登录已过期\"}");
        } else {
            response.sendRedirect("/login");
        }
    }
}
