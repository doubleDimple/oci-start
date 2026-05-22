package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;

/**
 * @author doubleDimple
 * @date 2024:12:01日 09:08
 */
@Data
public class VerificationRequest {
    @NotBlank(message = "用户名不能为空")
    private String username;

    @NotBlank(message = "验证码不能为空")
    private String verificationCode;
}
