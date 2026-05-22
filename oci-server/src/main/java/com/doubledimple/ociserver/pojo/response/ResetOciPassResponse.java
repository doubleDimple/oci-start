package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName ResetOcipassRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-07 09:07
 */
@Data
public class ResetOciPassResponse {

    String loginUser;
    /**
    * 临时密码
    */
    String temporaryPassword;

    String resetTime;
}
