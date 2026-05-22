package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.Email;
import javax.validation.constraints.NotBlank;

/**
 * @version 1.0.0
 * @ClassName EmailReceiveAddRequest
 * @Description 添加收件人请求
 * @Author doubleDimple
 * @Date 2025-09-27 09:47
 */
@Data
public class EmailReceiveAddRequest {

    @NotBlank(message = "收件人姓名不能为空")
    private String name;

    @NotBlank(message = "邮箱地址不能为空")
    @Email(message = "邮箱格式不正确")
    private String email;
}
