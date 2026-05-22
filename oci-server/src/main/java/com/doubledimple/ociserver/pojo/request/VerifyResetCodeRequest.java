package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;

/**
 * @version 1.0.0
 * @ClassName VerifyResetCodeRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-08-02 06:00
 */
@Data
public class VerifyResetCodeRequest {

    @NotBlank(message = "用户名不能为空")
    private String username;

    @NotBlank(message = "验证码不能为空")
    private String verificationCode;

}
