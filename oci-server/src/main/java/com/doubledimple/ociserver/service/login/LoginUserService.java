package com.doubledimple.ociserver.service.login;

import cn.dev33.satoken.stp.StpUtil;
import cn.hutool.core.util.ObjectUtil;
import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.LoginUserRepository;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ocicommon.enums.LoginTypeEnum;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.PasswordUpdateRequest;
import com.doubledimple.ociserver.service.InstallAppService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.transaction.Transactional;
import java.text.Normalizer;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2;
import static com.doubledimple.ocicommon.utils.IpUtils.getClientIpAddress;
import static com.doubledimple.ociserver.utils.PingUtil.getCurrentPublicIpAndAddress;

@Service
@Transactional
@Slf4j
public class LoginUserService {

    private static final String FIRST_USER_INITIALIZED_KEY = "auth.first-user.initialized";
    private static final Set<String> RESERVED_FIRST_USER_NAMES = new HashSet<>(Arrays.asList(
            "root", "admin", "administrator", "superadmin", "superuser", "system", "guest", "test", "user"));
    private static final String ALREADY_INITIALIZED = "系统已完成首次注册，不能再创建第二个初始账号";

    @Resource
    private LoginUserRepository loginUserRepository;

    @Resource
    private SystemConfigRepository systemConfigRepository;

    @Resource
    private PasswordEncoder passwordEncoder;

    @Resource
    MessageFactory messageFactory;

    @Resource
    InstallAppService installAppService;

    /**
     * 验证用户名和密码，返回 LoginUser（失败抛异常）
     */
    public LoginUser validateCredentials(String username, String password) {
        LoginUser user = loginUserRepository.findByUsername(username)
                .orElseThrow(() -> new CredentialValidationException(true));

        if (!passwordEncoder.matches(password, user.getPassword())) {
            log.warn("用户 [{}] 密码验证失败", username);
            throw new CredentialValidationException(false);
        }

        return user;
    }

    /**
     * 根据用户名查找用户（内部使用）
     */
    public LoginUser findByUsername(String username) {
        return loginUserRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("用户不存在"));
    }

    public boolean isFirstTimeDeployment() {
        return !existsAnyUser();
    }

    public void registerFirstUser(String username, String password) {
        if (!isFirstTimeDeployment()) {
            throw new FirstRegistrationException(ALREADY_INITIALIZED);
        }
        if (!StringUtils.hasText(username)) {
            throw new FirstRegistrationException("用户名不能为空");
        }
        String trimmedUsername = username.trim();
        String normalizedUsername = Normalizer.normalize(trimmedUsername, Normalizer.Form.NFKC)
                .trim().toLowerCase(Locale.ROOT);
        if (!StringUtils.hasText(normalizedUsername)) {
            throw new FirstRegistrationException("用户名不能为空");
        }
        if (RESERVED_FIRST_USER_NAMES.contains(normalizedUsername)
                || normalizedUsername.matches("(?:admin|root)[0-9]+")) {
            throw new FirstRegistrationException("请使用专属用户名，不能使用 root、admin 等常见默认用户名及其纯数字后缀");
        }
        if (!StringUtils.hasText(password)) {
            throw new FirstRegistrationException("密码不能为空");
        }

        // The unique config_key is a persistent claim shared by concurrent requests/processes.
        // Flush it before creating the user; both writes roll back together if registration fails.
        SystemConfig initialized = new SystemConfig();
        initialized.setKey(FIRST_USER_INITIALIZED_KEY);
        initialized.setValue("true");
        initialized.setEnabled(true);
        try {
            systemConfigRepository.saveAndFlush(initialized);
        } catch (DataIntegrityViolationException e) {
            throw new FirstRegistrationException(ALREADY_INITIALIZED);
        }

        LoginUser user = new LoginUser();
        user.setUsername(trimmedUsername);
        user.setPassword(passwordEncoder.encode(password));
        user.setFirstUser(true);
        user.setLoginType(LoginTypeEnum.LOCAL);
        loginUserRepository.save(user);
    }

    public void updateUser(String currentUsername, String newUsername, String newPassword) {
        LoginUser user = loginUserRepository.findByUsername(currentUsername)
                .orElseThrow(() -> new RuntimeException("用户不存在"));

        if (newUsername != null && !newUsername.equals(currentUsername)) {
            if (loginUserRepository.existsByUsername(newUsername)) {
                throw new RuntimeException("Username already exists");
            }
            user.setUsername(newUsername);
        }

        if (newPassword != null) {
            user.setPassword(passwordEncoder.encode(newPassword));
        }

        loginUserRepository.save(user);
    }

    public LoginUser registerThirdPartyUser(String externalId, String username, LoginTypeEnum loginType) {
        Optional<LoginUser> existingUser = loginUserRepository
                .findByExternalIdAndLoginType(externalId, loginType);

        if (existingUser.isPresent()) {
            LoginUser user = existingUser.get();
            user.setLastLoginAt(LocalDateTime.now());
            return loginUserRepository.save(user);
        }

        LoginUser newUser = new LoginUser();
        String suffix = "_" + loginType.name().toLowerCase();
        newUser.setUsername(username + suffix);
        newUser.setExternalId(externalId);
        newUser.setPassword(passwordEncoder.encode(UUID.randomUUID().toString()));
        newUser.setLoginType(loginType);

        return loginUserRepository.save(newUser);
    }

    public boolean existsAnyUser() {
        return loginUserRepository.count() > 0 || systemConfigRepository.existsByKey(FIRST_USER_INITIALIZED_KEY);
    }

    public boolean updatePassword(PasswordUpdateRequest request, HttpServletRequest httpServletRequest) {
        String currentUsername = StpUtil.getLoginIdAsString();
        LoginUser user = loginUserRepository.findByUsername(currentUsername)
                .orElseThrow(() -> {
                    log.warn("用户 [{}] 不存在，登录验证失败", currentUsername);
                    final String clientIp = getClientIpAddress(httpServletRequest).replace('.', '_');
                    messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplateText(
                            String.format(MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2,
                                    getCurrentPublicIpAndAddress(httpServletRequest), currentUsername, clientIp, clientIp));
                    return new RuntimeException("用户名或密码错误");
                });

        if (request.getCurrentPassword() == null
                || !passwordEncoder.matches(request.getCurrentPassword(), user.getPassword())) {
            throw new AccountValidationException("currentPasswordIncorrect", "当前密码不正确");
        }

        boolean changed = false;
        if (StringUtils.hasText(request.getNewUsername())
                && !request.getNewUsername().equals(user.getUsername())) {
            if (loginUserRepository.existsByUsername(request.getNewUsername())) {
                throw new AccountValidationException("usernameExists", "新用户名已存在");
            }
            user.setUsername(request.getNewUsername());
            changed = true;
        }

        if (StringUtils.hasText(request.getNewPassword())) {
            if (!ObjectUtil.equals(request.getNewPassword(), request.getCurrentPassword())) {
                user.setPassword(passwordEncoder.encode(request.getNewPassword()));
                changed = true;
            }
        }
        if (changed) {
            loginUserRepository.save(user);
        }
        return changed;
    }

    /** The failure kind is internal; the response never reveals whether an account exists. */
    public static final class CredentialValidationException extends RuntimeException {
        private final boolean unknownUsername;

        private CredentialValidationException(boolean unknownUsername) {
            super("用户名或密码错误");
            this.unknownUsername = unknownUsername;
        }

        public boolean isUnknownUsername() {
            return unknownUsername;
        }
    }

    /** Only locally authored validation messages may leave the public first-registration endpoint. */
    public static final class FirstRegistrationException extends RuntimeException {
        private FirstRegistrationException(String message) {
            super(message);
        }
    }

    /** Only these explicit checks run before any account entity mutation. */
    public static final class AccountValidationException extends RuntimeException {
        private final String errorKey;

        private AccountValidationException(String errorKey, String message) {
            super(message);
            this.errorKey = errorKey;
        }

        public String getErrorKey() {
            return errorKey;
        }
    }
}
