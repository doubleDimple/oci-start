package com.doubledimple.ocicommon.bark.pojo;

import com.doubledimple.ocicommon.bark.exception.BarkException;
import lombok.Builder;
import lombok.Data;
import org.springframework.util.StringUtils;

/**
 * @version 1.0.0
 * @ClassName BarkCfg
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-04 21:29
 */
@Data
@Builder
public class BarkCfg {
    private String pushUrl;
    private String deviceKey;
    private Encryption encryption;

    public void valid() {
        if (!StringUtils.hasText(pushUrl)) {
            throw new BarkException("pushUrl is empty");
        }
        if (!StringUtils.hasText(deviceKey)) {
            throw new BarkException("deviceKey is empty");
        }
        if (!pushUrl.matches("^(https?)://[\\\\w.-]+\\\\.\\\\w{2,4}(/.*)?$")) {
            throw new BarkException("pushUrl is invalid");
        }
    }
}
