package com.doubledimple.ociserver.pojo.request;


import lombok.Data;

import javax.validation.constraints.NotBlank;

@Data
public class ResetPasswordRequest {

    @NotBlank(message = "用户名不能为空")
    private String username;

}
