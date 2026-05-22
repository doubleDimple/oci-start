package com.doubledimple.ociserver.pojo.response;


import lombok.Data;

/**
* @Description:
* @Param:
* @return:
* @Author: doubleDimple
* @Date: 8/2/25 6:02 AM
*/
@Data
public class ResetTokenResponse {
    private String resetToken;
    private long expiresIn; // 过期时间（秒）
}
