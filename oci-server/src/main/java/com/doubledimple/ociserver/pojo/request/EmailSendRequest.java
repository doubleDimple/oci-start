package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotEmpty;
import javax.validation.constraints.NotNull;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName EmailSendRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-28 10:23
 */
@Data
public class EmailSendRequest {

    //标题
    @NotBlank(message = "邮箱主题不能为空")
    private String title;

    //内容
    @NotBlank(message = "邮箱内容不能为空")
    private String content;

    //启用邮箱服务的配置id
    @NotNull(message = "未选择邮箱配置服务的所属租户")
    private Long tenantEmailConfigId;

    //收件人id集合
    @NotEmpty(message = "收件人不能为空")
    private List<Long> emailReceiveIds;
}
