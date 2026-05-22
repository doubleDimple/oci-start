package com.doubledimple.ocicommon.bark.pojo;

import lombok.Builder;
import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName PushDetails
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-04 21:32
 */
@Data
@Builder
public class PushDetails {
    private String title;
    private String body;
    private String level;
    private String badge;
    private String autoCopy;
    private String copy;
    private String sound;
    private String icon;
    private String group;
    private String isArchive;
    private String category;
}
