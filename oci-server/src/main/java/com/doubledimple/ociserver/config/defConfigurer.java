package com.doubledimple.ociserver.config;

import com.doubledimple.ociserver.config.interceptor.RequestContextInterceptor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.CacheControl;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import org.springframework.web.servlet.i18n.CookieLocaleResolver;
import org.springframework.web.servlet.i18n.LocaleChangeInterceptor;

import javax.annotation.Resource;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

/**
 * @version 1.0.0
 * @ClassName I18nConfig
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-08-09 20:41
 */
@Configuration
public class defConfigurer implements WebMvcConfigurer {

    @Resource
    private RequestContextInterceptor interceptor;

    @Bean
    public CookieLocaleResolver localeResolver() {
        CookieLocaleResolver resolver = new CookieLocaleResolver();
        resolver.setDefaultLocale(Locale.SIMPLIFIED_CHINESE);
        resolver.setCookieName("language");
        resolver.setCookieMaxAge(3600 * 24 * 30);
        resolver.setCookieSecure(false);
        resolver.setCookieHttpOnly(true);
        resolver.setCookiePath("/");
        resolver.setCookieDomain(null);
        return resolver;
    }

    @Bean
    public LocaleChangeInterceptor localeChangeInterceptor() {
        LocaleChangeInterceptor interceptor = new LocaleChangeInterceptor();
        interceptor.setParamName("lang");
        return interceptor;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(interceptor).addPathPatterns("/**");
        registry.addInterceptor(localeChangeInterceptor());
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/images/**")
                .addResourceLocations("classpath:/static/images/")
                .setCacheControl(CacheControl.maxAge(365, TimeUnit.DAYS).cachePublic());
        // webfonts: long cache so FA icons don't re-fetch on every page load
        registry.addResourceHandler("/webfonts/**")
                .addResourceLocations("classpath:/static/webfonts/")
                .setCacheControl(CacheControl.maxAge(365, TimeUnit.DAYS).cachePublic());
        // css/js static assets: 7-day cache
        registry.addResourceHandler("/css/**")
                .addResourceLocations("classpath:/static/css/")
                .setCacheControl(CacheControl.maxAge(7, TimeUnit.DAYS).cachePublic());
        registry.addResourceHandler("/js/**")
                .addResourceLocations("classpath:/static/js/")
                .setCacheControl(CacheControl.maxAge(7, TimeUnit.DAYS).cachePublic());
        // 暴露 script 目录,让前端 install 指南能直接 wget/curl 下载脚本
        registry.addResourceHandler("/script/**")
                .addResourceLocations("classpath:/script/")
                .setCacheControl(CacheControl.maxAge(0, TimeUnit.SECONDS));
    }
}
