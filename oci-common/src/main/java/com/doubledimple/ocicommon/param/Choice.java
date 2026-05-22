package com.doubledimple.ocicommon.param;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName Choice
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-12 21:44
 */
@Data
public class Choice {
    public Integer index;
    public ChatMessage message;
    public String finish_reason;
}
