package com.doubledimple.ociserver.config;

import com.doubledimple.ociserver.config.filter.RsaDecryptionFilter;
import com.doubledimple.ociserver.service.login.CustomerRememberMeService;
import com.doubledimple.ociserver.pojo.request.GithubConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Lazy;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.security.oauth2.client.registration.InMemoryClientRegistrationRepository;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestTemplate;

/**
 * @author doubleDimple
 * @date 2024:10:05日 23:27
 */
@Configuration
@EnableWebSecurity
@Slf4j
public class SecurityConfig {


    private final SystemConfigService systemConfigService;
    private final LoginUserService loginUserService;
    private final CustomerRememberMeService customerRememberMeService;
    private final RestTemplate restTemplate;


    public SecurityConfig(@Lazy SystemConfigService systemConfigService,
                          @Lazy LoginUserService loginUserService,
                          @Lazy CustomerRememberMeService customerRememberMeService,
                          @Lazy RestTemplate restTemplate) {
        this.systemConfigService = systemConfigService;
        this.loginUserService = loginUserService;
        this.customerRememberMeService = customerRememberMeService;
        this.restTemplate = restTemplate;
    }

    @Bean
    @Order(1)
    public SecurityFilterChain openApiFilterChain(HttpSecurity http) throws Exception {
        return http
                .requestMatchers(matchers -> matchers.antMatchers("/oci-start/open-api/**"))
                .authorizeHttpRequests(auth -> auth.anyRequest().permitAll())
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .build();
    }

    @Bean
    @Order(2)
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .authorizeRequests()
                .antMatchers(
                        "/login",
                        "/api/send-reset-code",
                        "/api/verify-reset-code",
                        "/api/reset-password",

                        "/api/config/mfa-enabled",
                        "/api/config/turnstile",
                        "/api/memos/**",


                        "/css/**",
                        "/js/**",
                        "/script/**",
                        "/api/metrics/reportMetrics",
                        "/api/config/message-enabled",
                        "/api/send-verification-code",
                        "/perform_login",
                        "/test/query",
                        //"/api/verify-code-login"

                        // 更新为 springdoc-openapi 路径
                        "/swagger-ui.html",
                        "/swagger-ui/**",
                        "/v3/api-docs/**",
                        "/swagger-resources/**",
                        "/webjars/**",

                        // Open API 健康检查接口（无需认证）
                        "/oci-start/open-api/v1/**"
                ).permitAll()
                // 允许直接的端点
                .antMatchers(
                        "/",                          // 添加根路径
                        "/api/register-first-user",
                        "/api/disTurnstile",
                        "/api/github/login/url",
                        "/api/github/callback",
                        "/api/github/status",
                        //探针相关
                        "/api/monitor/download",
                        "/api/monitor/report",
                        //google相关
                        "/api/google/login/url",
                        "/api/google/callback"
                ).permitAll()
                .anyRequest().authenticated()
                .and()
                .addFilterBefore(new RsaDecryptionFilter(systemConfigService, restTemplate), UsernamePasswordAuthenticationFilter.class)
                .formLogin()
                .loginPage("/login")
                .loginProcessingUrl("/perform_login")
                .successHandler(new MobileAwareAuthenticationSuccessHandler())
                .failureUrl("/login?error=true")  // 添加失败处理
                .permitAll()
                .and()
                .logout()
                .logoutUrl("/perform_logout")
                .logoutSuccessUrl("/login?logout")
                .invalidateHttpSession(true)
                .clearAuthentication(true)
                .deleteCookies("JSESSIONID", "remember-me-cookie")
                .permitAll()
                .and()
                // 添加 rememberMe 配置
                .rememberMe()
                .rememberMeServices(customerRememberMeService)
                .key(systemConfigService.getOrCreateRememberMeKey())  // 安全的密钥
                //.tokenValiditySeconds(7 * 24 * 60 * 60)  // 7天有效期
                //.userDetailsService(loginUserService)
                //.rememberMeParameter("remember-me")  // 前端复选框的 name 属性
                //.rememberMeCookieName("remember-me-cookie")  // cookie 名称
                .and()
                // 会话管理配置 - 调整顺序
                .sessionManagement()
                .sessionFixation().migrateSession()  // 添加 session fixation 保护
                .invalidSessionUrl("/login")
                .maximumSessions(1)
                .maxSessionsPreventsLogin(false)     // 允许新的登录踢掉旧的登录
                .expiredUrl("/login");

        http.headers().frameOptions().sameOrigin();

        // CSRF配置
        http.csrf()
                .ignoringAntMatchers("/api/metrics/reportMetrics")
                .ignoringAntMatchers("/api/register-first-user")
                .ignoringAntMatchers("/api/disTurnstile")
                .ignoringAntMatchers("/api/config/message-enabled")
                .ignoringAntMatchers("/api/send-verification-code")
                .ignoringAntMatchers("/api/verify-code-login")
                .ignoringAntMatchers("/perform_login")
                .ignoringAntMatchers("/test/query")
                .ignoringAntMatchers("/api/github/callback")

                .ignoringAntMatchers("/api/send-reset-code")
                .ignoringAntMatchers("/api/verify-reset-code")
                .ignoringAntMatchers("/api/reset-password")

                .ignoringAntMatchers("/api/config/mfa-enabled")
                .ignoringAntMatchers("/api/config/verify-mfa-code")
                .ignoringAntMatchers("/api/memos/**")

                // 更新为 springdoc-openapi 路径
                .ignoringAntMatchers("/swagger-ui.html")
                .ignoringAntMatchers("/swagger-ui/**")
                .ignoringAntMatchers("/v3/api-docs/**")      // 更新：v2 -> v3
                .ignoringAntMatchers("/swagger-resources/**") // 可选
                .ignoringAntMatchers("/webjars/**")

                // 开放健康检查接口和其他需要的 Open API 接口
                .ignoringAntMatchers("/oci-start/open-api/v1/**")
                // 如果其他 Open API 接口也需要免 CSRF，可以添加：
                // .ignoringAntMatchers("/open-api/**")
                .ignoringAntMatchers("/api/monitor/download")
                .ignoringAntMatchers("/api/monitor/report")

        ;

        return http.build();
    }

    @Bean
    public ClientRegistrationRepository clientRegistrationRepository() {
        return new LazyClientRegistrationRepository(systemConfigService);
    }

    private static class LazyClientRegistrationRepository implements ClientRegistrationRepository {

        private final SystemConfigService systemConfigService;
        private volatile ClientRegistrationRepository delegate;

        public LazyClientRegistrationRepository(SystemConfigService systemConfigService) {
            this.systemConfigService = systemConfigService;
        }

        @Override
        public ClientRegistration findByRegistrationId(String registrationId) {
            log.info("Searching for ClientRegistration with id: {}", registrationId);

            if (!"github".equals(registrationId)) {
                log.info("Registration id is not github, returning null");
                return null;
            }

            // 只有当真正需要时才初始化
            if (delegate == null) {
                synchronized (this) {
                    if (delegate == null) {
                        log.info("Initializing GitHub client registration");
                        GithubConfig config = systemConfigService.getGithubConfig();
                        log.info("Loaded GitHub config: enabled={}, hasClientId={}, hasClientSecret={}",
                                config.isEnabled(),
                                StringUtils.hasText(config.getClientId()),
                                StringUtils.hasText(config.getClientSecret()));

                        // 只有当配置有效时才创建
                        if (config != null && config.isEnabled() &&
                                StringUtils.hasText(config.getClientId()) &&
                                StringUtils.hasText(config.getClientSecret())) {

                            try {
                                ClientRegistration registration = ClientRegistration.withRegistrationId("github")
                                        .clientId(config.getClientId())
                                        .clientSecret(config.getClientSecret())
                                        .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                                        .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                                        .redirectUri("{baseUrl}/login/oauth2/code/{registrationId}")
                                        .scope("read:user", "user:email")
                                        .authorizationUri("https://github.com/login/oauth/authorize")
                                        .tokenUri("https://github.com/login/oauth/access_token")
                                        .userInfoUri("https://api.github.com/user")
                                        .userNameAttributeName("id")  // 改为"id"而不是"login"
                                        .clientName("GitHub")
                                        .build();

                                delegate = new InMemoryClientRegistrationRepository(registration);
                                log.info("Successfully created GitHub client registration");
                            } catch (Exception e) {
                                log.error("Error creating GitHub client registration", e);
                            }
                        } else {
                            log.info("GitHub config is not valid or not enabled");
                        }
                    }
                }
            }

            ClientRegistration registration = delegate != null ? delegate.findByRegistrationId(registrationId) : null;
            log.debug("Returning registration: {}", registration != null ? "found" : "not found");
            return registration;
        }
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
