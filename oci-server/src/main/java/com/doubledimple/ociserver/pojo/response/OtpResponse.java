package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

/**
 * @author doubleDimple
 * @date 2024:11:01日 23:21
 */
@Data
public class OtpResponse {

    private String otpCode;

    private String secretKey;
}
