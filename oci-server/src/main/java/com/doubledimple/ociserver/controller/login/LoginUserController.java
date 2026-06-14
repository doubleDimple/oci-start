package com.doubledimple.ociserver.controller.login;

import com.doubledimple.ociserver.config.annotations.CheckLoginUser;
import com.doubledimple.ociserver.config.context.UserContext;
import com.doubledimple.ociserver.config.init.Init;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.service.login.LoginUserService;
import com.doubledimple.ociserver.pojo.request.RegisterRequest;
import com.doubledimple.ociserver.pojo.request.UpdateUserRequest;
import org.apache.commons.lang3.StringUtils;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * @version 1.0.0
 * @ClassName LoginUserController
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-21 11:07
 */
@RestController
@RequestMapping("/api")
public class LoginUserController  extends BaseController {

    @Resource
    private LoginUserService loginUserService;

    @Resource
    SystemConfigService systemConfigService;

    @PostMapping("/register-first-user")
    public ResponseEntity<?> registerFirstUser(@RequestBody RegisterRequest request) {
        try {
            loginUserService.registerFirstUser(request.getUsername(), request.getPassword());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    //禁用turntile
    @GetMapping("/disTurnstile")
    @ResponseBody
    public ApiResponse disTurnstile(@RequestParam(value = "token", required = false) String token) {
        if (StringUtils.isBlank(token) || !token.equals(Init.turnstileBypassToken)) {
            return ApiResponse.error("Token无效、已过期或系统未开启Turnstile验证，禁用失败！");
        }
        systemConfigService.disTurnstile();
        Init.turnstileBypassToken = UUID.randomUUID().toString();

        return ApiResponse.success();
    }


    @PostMapping("/update-user")
    public ResponseEntity<?> updateUser(@RequestBody UpdateUserRequest request) {
        try {
            String currentUsername = com.doubledimple.ociserver.config.context.UserContext.getUsername();
            loginUserService.updateUser(
                    currentUsername,
                    request.getNewUsername(),
                    request.getNewPassword()
            );
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @GetMapping("/userInfo")
    @ResponseBody
    public ApiResponse getUserInfo() {
        try {
            final String username = UserContext.getUsername();

            Map<String, Object> userInfo = new HashMap<>();
            userInfo.put("username", username);

            return ApiResponse.success(userInfo);
        } catch (Exception e) {
            return ApiResponse.error("获取用户信息失败");
        }
    }
}
