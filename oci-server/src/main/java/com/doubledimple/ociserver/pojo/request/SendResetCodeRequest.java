package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;

/**
* @Description:
* @Param:
* @return:
* @Author: doubleDimple
* @Date: 8/2/25 6:00 AM
*/
@Data
public class SendResetCodeRequest {
    @NotBlank(message = "用户名不能为空")
    private String username;
}
