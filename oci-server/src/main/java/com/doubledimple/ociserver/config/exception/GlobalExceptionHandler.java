package com.doubledimple.ociserver.config.exception;

import org.springframework.http.ResponseEntity;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import javax.servlet.http.HttpServletRequest;

import static com.doubledimple.ocicommon.utils.IpUtils.getClientIpAddress;

@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(IpBannedException.class)
    public String handleIpBannedException(IpBannedException e, HttpServletRequest request, Model model) {
        model.addAttribute("message", e.getMessage());
        model.addAttribute("code", 403);
        model.addAttribute("ip", getClientIpAddress( request));
        return "error/403";
    }
}
