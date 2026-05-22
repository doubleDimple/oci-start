package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;

/**
 * @author doubleDimple
 * @date 2024:12:01日 01:00
 */
@Data
public class UsernameRequest {
    @NotBlank(message = "用户名不能为空")
    private String username;
}
