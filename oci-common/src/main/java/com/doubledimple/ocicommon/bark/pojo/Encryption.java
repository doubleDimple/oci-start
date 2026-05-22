package com.doubledimple.ocicommon.bark.pojo;

import com.doubledimple.ocicommon.bark.exception.BarkException;
import lombok.Builder;
import lombok.Data;
import org.springframework.util.StringUtils;

/**
 * @version 1.0.0
 * @ClassName Encryption
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-04 21:30
 */
@Builder
@Data
public class Encryption {
    private String algorithm;
    private String mode;
    private String padding;
    private String key;
    private String iv;

    public void valid() {

        if (!StringUtils.hasText(this.padding)) {
            this.padding = "PKC7Padding";
        }
        if (!StringUtils.hasText(this.algorithm)) {
            this.mode = "AES";
        }

        if (!StringUtils.hasText(this.mode)) {
            throw new BarkException("AES Mode is empty");
        }

        if (!"ECB".equals(this.mode) && !"CBC".equals(this.mode)) {
            throw new BarkException("AES Mode is invalid, only support ECB or CBC");
        }

        if (StringUtils.hasText(this.iv)) {
            if (this.iv.length() != 16) {
                throw new BarkException("AES IV length is invalid, only support 16");
            }
        }

        if (!StringUtils.hasText(this.key)) {
            if (this.key.length() % 16 != 0) {
                throw new BarkException("AES Key length is invalid, only support AES128, AES192, AES256");
            }
        }
    }
}
