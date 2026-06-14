package com.doubledimple.ociserver.service.login;

import cn.dev33.satoken.stp.StpUtil;
import cn.hutool.core.util.ObjectUtil;
import cn.hutool.json.JSONUtil;
import com.doubledimple.dao.entity.LoginUser;
import com.doubledimple.dao.repository.LoginUserRepository;
import com.doubledimple.ocicommon.enums.LoginTypeEnum;
import com.doubledimple.ociserver.config.task.VersionCheckTask;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.PasswordUpdateRequest;
import com.doubledimple.ociserver.service.InstallAppService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.transaction.Transactional;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2;
import static com.doubledimple.ocicommon.utils.IpUtils.getClientIpAddress;
import static com.doubledimple.ociserver.utils.PingUtil.getCurrentPublicIpAndAddress;

@Service
@Transactional
@Slf4j
public class LoginUserService {

    @Resource
    private LoginUserRepository loginUserRepository;

    @Resource
    private PasswordEncoder passwordEncoder;

    @Resource
    VersionCheckTask versionCheckTask;

    @Resource
    MessageFactory messageFactory;

    @Resource
    InstallAppService installAppService;

    /**
     * 验证用户名和密码，返回 LoginUser（失败抛异常）
     */
    public LoginUser validateCredentials(String username, String password) {
        LoginUser user = loginUserRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("用户名或密码错误"));

        if (!passwordEncoder.matches(password, user.getPassword())) {
            log.warn("用户 [{}] 密码验证失败", username);
            throw new RuntimeException("用户名或密码错误");
        }

        versionCheckTask.checkVersion();
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
        return loginUserRepository.countByLoginType(LoginTypeEnum.LOCAL) == 0;
    }

    public void registerFirstUser(String username, String password) {
        if (!isFirstTimeDeployment()) {
            throw new RuntimeException("System already initialized");
        }

        LoginUser user = new LoginUser();
        user.setUsername(username);
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
        return loginUserRepository.count() > 0;
    }

    public void updatePassword(PasswordUpdateRequest request, HttpServletRequest httpServletRequest) {
        log.info("修改用户信息请求参数：{}", JSONUtil.toJsonStr(request));

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

        if (!passwordEncoder.matches(request.getCurrentPassword(), user.getPassword())) {
            throw new RuntimeException("当前密码不正确");
        }

        if (StringUtils.hasText(request.getNewUsername())
                && !request.getNewUsername().equals(user.getUsername())) {
            if (loginUserRepository.existsByUsername(request.getNewUsername())) {
                throw new RuntimeException("新用户名已存在");
            }
            user.setUsername(request.getNewUsername());
        }

        log.info("修改后的用户信息：{}", JSONUtil.toJsonStr(user));
        if (StringUtils.hasText(request.getNewPassword())) {
            if (!ObjectUtil.equals(request.getNewPassword(), request.getCurrentPassword())) {
                user.setPassword(passwordEncoder.encode(request.getNewPassword()));
            }
        }
        loginUserRepository.save(user);
    }
}
