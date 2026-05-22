package com.doubledimple.ociserver.service.login;


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
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
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

/**
 * @version 1.0.0
 * @ClassName LoginUserService
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 11:02
 */
@Service
@Transactional
@Slf4j
public class LoginUserService implements UserDetailsService {

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

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        LoginUser user = loginUserRepository.findByUsername(username)
                .orElseThrow(() -> new UsernameNotFoundException("User not found"));

        //检查版本更新
        versionCheckTask.checkVersion();

        //安装app
        //installAppService.addOrUpdateInstallApp();

        return org.springframework.security.core.userdetails.User
                .withUsername(user.getUsername())
                .password(user.getPassword())
                .roles("USER")
                .build();
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
                .orElseThrow(() -> new UsernameNotFoundException("User not found"));

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

    // 添加GitHub用户注册/登录方法
    /**
     * 通用的第三方账号登录/注册逻辑
     * @param externalId 第三方平台的唯一ID (GitHub是id, Google是email)
     * @param username   第三方平台获取到的用户名或昵称
     * @param loginType  第三方登录类型枚举
     */
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
        String randomPassword = UUID.randomUUID().toString();
        newUser.setPassword(passwordEncoder.encode(randomPassword));

        newUser.setLoginType(loginType);

        return loginUserRepository.save(newUser);
    }

    public boolean existsAnyUser() {
        return loginUserRepository.count() > 0;
    }

    public void updatePassword(PasswordUpdateRequest request, HttpServletRequest httpServletRequest) {
        log.info("当前修改用户信息的请求参数是:{}", JSONUtil.toJsonStr(request));
        // 获取当前用户
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        LoginUser user = loginUserRepository.findByUsername(auth.getName())
                .orElseThrow(() -> {
                    log.warn("用户 [{}] 不存在，登录验证失败", auth.getName());
                    final String clientIpAddress = getClientIpAddress(httpServletRequest).replace('.', '_');
                    messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplateText(String.format(MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2,
                            getCurrentPublicIpAndAddress(httpServletRequest), auth.getName(),clientIpAddress,clientIpAddress));
                    return new RuntimeException("用户名或密码错误");
                });

        // 验证当前密码
        if (!passwordEncoder.matches(request.getCurrentPassword(), user.getPassword())) {
            throw new RuntimeException("当前密码不正确");
        }

        // 如果要更改用户名，检查新用户名是否已存在
        if (StringUtils.hasText(request.getNewUsername())
                && !request.getNewUsername().equals(user.getUsername())) {
            if (loginUserRepository.existsByUsername(request.getNewUsername())) {
                throw new RuntimeException("新用户名已存在");
            }
            user.setUsername(request.getNewUsername());
        }

        // 更新密码
        log.info("修改后的用户信息是:{}",JSONUtil.toJsonStr(user));
        if (StringUtils.hasText(request.getNewPassword())){
            if (!ObjectUtil.equals(request.getNewPassword(),request.getCurrentPassword() )){
                log.info("用户修改了密码,原密码是:{},修改后的密码是:{}",request.getCurrentPassword(),request.getNewPassword());
                user.setPassword(passwordEncoder.encode(request.getNewPassword()));
            }
        }
        loginUserRepository.save(user);
    }
}
