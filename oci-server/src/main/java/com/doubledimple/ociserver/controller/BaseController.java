package com.doubledimple.ociserver.controller;

import com.doubledimple.ociserver.config.annotations.CheckIpBan;
import com.doubledimple.ociserver.config.annotations.CheckLoginUser;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import org.springframework.context.MessageSource;
import org.springframework.context.annotation.Lazy;
import org.springframework.context.i18n.LocaleContextHolder;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.ModelAttribute;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

@Controller
@CheckIpBan
@CheckLoginUser
public abstract class BaseController {

    @Resource
    protected MessageSource messageSource;

    @Resource
    @Lazy
    protected SystemConfigService systemConfigService;

    @ModelAttribute
    public void addCommonAttributes(Model model, HttpServletRequest request) {
        Locale locale = LocaleContextHolder.getLocale();
        String siteLogoName = systemConfigService.getSiteLogoName();
        model.addAttribute("msg", new MessageResolver(messageSource, locale));
        model.addAttribute("currentLocale", locale.toString());
        model.addAttribute("siteLogoName", siteLogoName);
    }

    public static class MessageResolver {
        private final MessageSource messageSource;
        private final Locale locale;

        public MessageResolver(MessageSource messageSource, Locale locale) {
            this.messageSource = messageSource;
            this.locale = locale;
        }

        public String get(String code) {
            try {
                return messageSource.getMessage(code, null, locale);
            } catch (Exception e) {
                return "???" + code + "???";
            }
        }

        public String getWithArgs(String code, Object... args) {
            return messageSource.getMessage(code, args, locale);
        }
    }
}
